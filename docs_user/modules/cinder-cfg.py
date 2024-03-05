#!/usr/bin/env python
# Helper tool for adoption of a Director deployed OpenStack.
# Conde is anything but good, though it should be somewhat useful.
# It helps create a draft patch file (cinder.patch) with the cinder
# configuration.
# It may also create a file (cinder-prereq.yaml) with manifests for secrets and
# MachineConfigs depending on the provider cinder configuruation file.
#
import argparse
import base64
import collections
import copy
import logging
import os

import yaml


LOG = logging
PATCH_FILE = 'cinder.patch'
PREREQ_FILE = 'cinder-prereq.yaml'

CINDER_TEMPLATE = """
spec:
  cinder:
    enabled: true
    apiOverride:
      route: {}
    template:
      databaseInstance: openstack
      secret: osp-secret
      cinderAPI:
        replicas: 3
        override:
          service:
            internal:
              metadata:
                annotations:
                  metallb.universe.tf/address-pool: internalapi
                  metallb.universe.tf/allow-shared-ip: internalapi
                  metallb.universe.tf/loadBalancerIPs: 172.17.0.80
              spec:
                type: LoadBalancer
      cinderScheduler:
        replicas: 1
      cinderBackup:
        networkAttachments:
        - storage
        replicas: 0
"""

EXTRAMOUNTS_CEPH = """
  extraMounts:
    - extraVol:
      - propagation:
        - CinderVolume
        - CinderBackup
        - Glance
        extraVolType: Ceph
        volumes:
        - name: ceph
          projected:
            sources:
            - secret:
                name: ceph-conf-files
        mounts:
        - name: ceph
          mountPath: "/etc/ceph"
          readOnly: true
"""

MACHINECONFIGS = {
    'iscsid': '''apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
    service: cinder
  name: 99-master-cinder-enable-iscsid
spec:
  config:
    ignition:
      version: 3.2.0
    systemd:
      units:
      - enabled: true
        name: iscsid.service
''',

    'multipathd': '''apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
    service: cinder
  name: 99-master-cinder-enable-multipathd
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
        - path: /etc/multipath.conf
          overwrite: false
          # Mode must be decimal, this is 0600
          mode: 384
          user:
            name: root
          group:
            name: root
          contents:
            # Source can be a http, https, tftp, s3, gs, or data as per rfc2397
            # This is the rfc2397 text/plain string format
            source: data:,defaults%20%7B%0A%20%20user_friendly_names%20no%0A%20%20recheck_wwid%20yes%0A%20%20skip_kpartx%20yes%0A%20%20find_multipaths%20yes%0A%7D%0A%0Ablacklist%20%7B%0A%7D
    systemd:
      units:
      - enabled: true
        name: multipathd.service
''',

    'nvmeof': '''apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
    service: cinder
  name: 99-master-cinder-load-nvme-fabrics
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
        - path: /etc/modules-load.d/nvme_fabrics.conf
          overwrite: false
          # Mode must be decimal, this is 0644
          mode: 420
          user:
            name: root
          group:
            name: root
          contents:
            # Source can be a http, https, tftp, s3, gs, or data as per rfc2397
            # This is the rfc2397 text/plain string format
            source: data:,nvme-fabric
'''
}

DRIVER_TO_IMAGE_NAME = {'PureISCSIDriver': 'pure',
                        'PureFCDriver': 'pure',
                        'PureNVMEDriver': 'pure',
                        'HPE3PARFCDriver': '3par',
                        'HPE3PARISCSIDriver': '3par',
                        'VNXDriver': 'dellemc',
                        'UnityDriver': 'dellemc',
                        'FJDXFCDriver': 'fujitsu',
                        'FJDXISCSIDriver': 'fujitsu'}

# Image location and whether it's outdated or not
IMAGES = {
    'pure': ('registry.connect.redhat.com/purestorage/'
             'openstack-cinder-volume-pure-rhosp-17-0', True),
    '3par': ('registry.connect.redhat.com/hpe3parcinder/'
             'openstack-cinder-volume-hpe3parcinder17-0', True),
    'dellemc': ('registry.connect.redhat.com/dellemc/',
                'openstack-cinder-volume-dellemc-rhosp16', True),
    'fujitsu': ('registry.connect.redhat.com/fujitsu/'
                'rhosp15-fujitsu-cinder-volume-161', True),
}


def str_presenter(dumper, data):
    """Configures yaml for dumping multiline strings

    Ref: https://stackoverflow.com/questions/8640959/how-can-i-control-what-scalar-form-pyyaml-uses-for-my-data
    """
    if data.count('\n') > 0:  # check for multiline string
        return dumper.represent_scalar('tag:yaml.org,2002:str',
                                       data, style='|')
    return dumper.represent_scalar('tag:yaml.org,2002:str', data)


yaml.add_representer(str, str_presenter)
yaml.representer.SafeRepresenter.add_representer(str, str_presenter)


class CinderTransformer(object):
    # None means remove the whole section
    remove_config = {
        'os_brick': None,
        'coordination': None,
        'oslo_messaging_rabbit': None,
        'oslo_concurrency': None,
        'database': ['connection'],
        'oslo_messaging_notifications': None,
        'keystone_authtoken': ['www_authenticate_uri',
                               'auth_url',
                               'memcached_servers',
                               # This should have been set in a secret
                               'password',
                               # We'll add this to Spec.ServiceUser
                               'username'],

        # "password" and "username" will probably not be like we want them
        # we usually want the cinder user to have access to the nova API
        'service_user': None,
        'barbican': None,
        'DEFAULT': ['transport_url', 'api_paste_config', 'log_dir',
                    'glance_api_servers', 'state_path',
                    'image_conversion_dir', 'volumes_dir'],
        # "password" and "username" will probably not be like we want them
        # we usually want the cinder user to have access to the nova API
        'nova': None,
    }

    def __init__(self, config_file, skip_machineconfig=False,
                 only_backends=False, name=None):
        self.config_file = config_file
        self.do_machineconfig = not skip_machineconfig
        self.do_only_backends = only_backends
        self.name = name

        self._backends = None
        self.processed_data = None
        self._username = None
        self._secrets = {}
        self._machineconfigs = []
        self._extra_volumes = []

        self.parse_config()
        self.sanity_checks()

    def parse_config(self):
        result_cfg = {}

        section_name = ''
        # Ignore anything that's out of a section at the beginning of the file
        section_options = 0

        for line in self.config_file:
            line = line.strip()
            # Remove comments
            if not line or line.startswith('#'):
                continue
            if line.startswith('[') and line.endswith(']'):
                section_name = line[1:-1]
                # Use setdefault in case section defined multiple times
                section_options = result_cfg.setdefault(
                    section_name, collections.OrderedDict())
                continue

            try:
                name, value = line.split('=', 1)
            except ValueError:
                LOG.warning('Line %s is not a configuration option', line)
                continue
            name = name.strip()
            if not name:
                LOG.warning('Weird line is not a valid configuration option '
                            'skipping it', line)
                continue

            # Don't use a dict because we can have multiOpt options
            section_options.setdefault(name, []).append(value.strip())

        # Remove empty sections
        result = {key: value for key, value in result_cfg.items() if value}
        self.config = result

    def get(self, section, option=None, default=None):
        res = self.config.get(section, {})
        if option is None:
            return res
        return res.get(option, default)

    def remove(self, section, option=None, logmsg=False):
        if option is None:
            if logmsg:
                LOG.info('Removing section %s', section)
            self.config.pop(section, None)
        else:
            if logmsg:
                LOG.info('Removing option %s from section %s', option, section)
            self.config.get(section, {}).pop(option, None)

    @property
    def username(self):
        if not self._username:
            self._username = self.get('keystone_authtoken', 'username')
        return self._username

    def sanity_checks(self):
        if not self.username:
            LOG.warning('Missing keystone username, will use default\n')

        if self.get('barbican'):
            LOG.warning("Barbican is configured but it won't match the new "
                        "deployment configuration, dropping it. Make sure "
                        "you update the path file include the right "
                        "configuration.")

        # TODO: Check ssh_hosts_key_file
        # TODO: netapp_copyoffload_tool_path
        # TODO: nfs_mount_point_base
        # TODO: disable_by_file_path
        # TODO: disable_by_file_paths
        # TODO: FC fc_fabric_ssh_cert_path

        policy_path = self.get('oslo_policy', 'policy_file')
        if policy_path:
            LOG.warning('Cinder is configured to use %s as policy file, '
                        'please ensure this file is available for the '
                        'podified cinder services using "extraMounts" or '
                        'remove the option.\n', policy_path)

        for section in self.backends + ['backend_defaults']:
            verify = self.get(section, 'driver_ssl_cert_verify')
            cert_path = self.get(section, 'driver_ssl_cert_path')
            if verify and cert_path:
                LOG.warning('Using certs in %s from %s, ensure certs are '
                            'available for the podified cinder services using '
                            '"extraMounts" or remove the option.\n',
                            section, cert_path)

        backends = self.get('DEFAULT', 'enabled_backends', [''])[-1].split(',')
        if not backends:
            LOG.warning('There are no backends configured, cinder volume will '
                        'not be configured.\n')
        else:
            valid_backends = self.backends
            if len(valid_backends) != len(backends):
                missing = ','.join(set(backends) - set(valid_backends))
                LOG.warning('Ignoring backends %s that are missing a '
                            'section.\n', missing)

        for backend in self.backends:
            image, outdated = self.get_image(self.get(backend))
            if outdated:
                LOG.error('Backend %s requires a vendor container image, but '
                          'there is no certified image available yet. Patch '
                          'will use the last known image for reference, but '
                          'IT WILL NOT WORK\n', backend)

        if any('RBDDriver' == self.get_driver(b) for b in self.backends):
            LOG.warning('Deployment uses Ceph, so make sure the Ceph '
                        'credentials and configuration are present in '
                        'OpenShift as a secret and then use the extra '
                        'volumes to make them available in all the services '
                        'that would need them. A reference is included in '
                        'the .path file\n')

        if not self.do_only_backends:
            username = self.username
            nova_username = self.get('nova', 'username')
            if nova_username and nova_username != username:
                LOG.warning('You were using user %s to talk to Nova, but in '
                            'podified we prefer using the service keystone '
                            'username, in this case %s. Dropping that '
                            'configuration.\n', nova_username, username)

        if self.using_protocol('fc'):
            LOG.warning('Configuration is using FC, please ensure all your '
                        'OpenShift nodes have HBAs or use labels to ensure '
                        'that Volume and Backup services are scheduled on '
                        'nodes with HBAs.\n')

        if not self.do_machineconfig:
            protocols = []
            if self.using_protocol('iscsi'):
                protocols.append('is running iscsid')
            if self.using_protocol('nvme'):
                protocols.append('have loaded nvme fabrics kernel modules')
            if self.using_multipath():
                protocols.append('is running multipathd')

            if protocols:
                msg = ' and '.join(protocols)
                LOG.warning('Make sure your deployment %s (may require using '
                            'MachineConfig).\n', msg)

    def using_multipath(self):
        if self.get('backend_defaults', 'use_multipath_for_image_xfer'):
            return True
        for backend in self.backends:
            if self.get(backend, 'use_multipath_for_image_xfer'):
                return True
        return False

    def using_protocol(self, protocol):
        for backend in self.backends:
            method_name = f'uses_{protocol}'
            if getattr(self, method_name)(backend):
                return True
        return False

    def get_driver(self, input):
        if isinstance(input, str):
            input = self.get(input)
        driver = input.get('volume_driver', ['lvm.LVMVolumeDriver'])
        class_name = driver[-1].rsplit('.')[-1]
        return class_name

    def uses_fc(self, backend_name):
        class_name = self.get_driver(backend_name)
        if 'fc' in class_name.lower():
            return True
        if ('NetAppDriver' == class_name
                and 'fc' == self.get(backend_name,
                                     'netapp_storage_protocol')[-1]):
            return True
        if (class_name in ('VNXDriver', 'UnityDriver')
                and 'FC' == self.get(backend_name, 'storage_protocol')[-1]):
            return True
        return False

    def uses_iscsi(self, backend_name):
        class_name = self.get_driver(backend_name)
        if 'iscsi' in class_name.lower():
            return True
        if ('NetAppDriver' == class_name
                and 'iscsi' == self.get(backend_name,
                                        'netapp_storage_protocol')[-1]):
            return True
        if (class_name in ('VNXDriver', 'UnityDriver')
                and 'iSCSI' == self.get(backend_name, 'storage_protocol')[-1]):
            return True

        if ('LVMVolumeDrivers' == class_name
                and self.get(backend_name, 'target_protocol')[-1]
                in ('lioadm', 'tgtadm', 'iscsictl')):
            return True
        return False

    def uses_nvme(self, backend_name):
        class_name = self.get_driver(backend_name)
        if 'nvme' in class_name.lower():
            return True
        if ('NetAppDriver' == class_name
                and 'iscsi' == self.get(backend_name,
                                        'netapp_storage_protocol')[-1]):
            return True

        if ('LVMVolumeDrivers' == class_name
                and 'nvme' in self.get(backend_name,
                                       'target_protocol')[-1]):
            return True
        return False

    @property
    def processed(self):
        return bool(self.processed_data)

    def _process(self):
        self.username  # Ensure we save the username

        # Remove sections and options defined in class's remove_config
        for section, options in list(self.remove_config.items()):
            for option in (options if options else [None]):
                self.remove(section, option)

        if self.do_machineconfig:
            if self.using_multipath():
                self._machineconfigs.append('multipathd')
            if self.using_protocol('iscsi'):
                self._machineconfigs.append('iscsid')
            if self.using_protocol('nvme'):
                self._machineconfigs.append('nvmeof')

        res = {}
        res.update(self.get_backup())
        res.update(self.get_volumes())
        res.update(self.get_scheduler())
        res.update(self.get_api())
        res.update(self.get_global())
        self.processed_data = res

    def get_image(self, config):
        class_name = self.get_driver(config)
        image_name = DRIVER_TO_IMAGE_NAME.get(class_name)
        if image_name:
            return IMAGES[image_name]
        return (None, None)

    def generate_patch(self):
        res = yaml.safe_load(CINDER_TEMPLATE)
        template = res['spec']['cinder']['template']

        if self.username:
            template['serviceUser'] = self.username[0]

        self.svc_cfg(template, 'global_defaults')
        self.svc_cfg(template['cinderAPI'], 'api')
        self.svc_cfg(template['cinderScheduler'], 'scheduler')
        if self.processed_data['backup']:
            self.svc_cfg(template['cinderBackup'], 'backup')
            template['cinderBackup']['replicas'] = 3

        vols = template.setdefault('cinderVolumes', {})
        # TODO: Uncomment once cinder-operator supports config for all volumes
        # self.svc_cfg(vols, 'volume_global')
        volumes = self.processed_data['volumes']

        if any('RBDDriver' == self.get_driver(v[k])
               for k, v in volumes.items()):
            res['spec'].update(yaml.load(EXTRAMOUNTS_CEPH,
                                         Loader=yaml.SafeLoader))

        for backend, config in volumes.items():
            # Names cannot use _ in the operator
            manifest_backend_name = backend.replace('_', '-')
            backend_data = vols[manifest_backend_name] = {
                'networkAttachments': ['storage'],
            }

            # TODO:Remove once cinder-operator supports config for all volumes
            config.update(self.processed_data['volume_global'])

            config.setdefault('DEFAULT', {})['enabled_backends'] = [backend]
            self.svc_cfg(backend_data, 'volumes', backend)

            image = self.get_image(config[backend])[0]
            if image:
                backend_data['containerImage'] = image
        return res

    def generate_manifest(self):
        # Generate Secrets
        template = {'apiVersion': 'v1',
                    'kind': 'Secret',
                    'metadata': {'name': None},
                    'data': {}}
        result = []
        for secret, files in self._secrets.items():
            new_secret = copy.deepcopy(template)
            new_secret['metadata']['name'] = secret
            for name, contents in files.items():
                LOG.debug('Encoding %s: %s\n', name, contents)
                contents = base64.b64encode(contents.encode()).decode()
                new_secret['data'][name] = contents
            result.append(new_secret)

        # Generate MachineConfig
        for name in self._machineconfigs:
            result.append(yaml.load(MACHINECONFIGS[name],
                                    Loader=yaml.SafeLoader))
        return result

    def write_manifest(self, output_file):
        if not self.processed:
            self._process()
        data = self.generate_manifest()
        manifest = ''
        for element in data:
            manifest += yaml.dump(element)
            manifest += '---\n'
        output_file.write(manifest)
        return bool(data)

    def write_patch(self, output_file):
        if not self.processed:
            self._process()
        data = self.generate_patch()
        patch = yaml.dump(data)
        output_file.write(patch)

    @staticmethod
    def options_to_str(options):
        res = ''
        for key, values in options.items():
            for value in values:
                res += key + '=' + value + '\n'
        return res

    def merge_remove(self, remove_config):
        res = copy.deepcopy(self.remove_config)
        for key, value in remove_config.items():
            if key in res:
                res[key].extend(value)
            else:
                res[key] = value
        self.remove_config = res

    def _sensitive_info(self, data):
        for key in data:
            if 'password' in key:
                return True
        return False

    def svc_cfg(self, template, section, subsection=None):
        name = 'cinder-' + section
        data = self.processed_data[section]
        if data and subsection:
            name += '-' + subsection
            data = data[subsection]
        if not data:
            return
        res = ''
        secret_res = ''
        for key, values in data.items():
            new_section = f'[{key}]\n' + self.options_to_str(values)
            if self._sensitive_info(values):
                secret_res += new_section
            else:
                res += new_section

        if res:
            template['customServiceConfig'] = res
        if secret_res:
            secret_name = self.name + name
            self._secrets[secret_name] = {name: secret_res}
            template['customServiceConfigSecrets'] = [secret_name]

    @property
    def backends(self):
        if self._backends is None:
            value = self.get('DEFAULT', 'enabled_backends', [''])[-1]
            value = value.split(',')
            self._backends = [backend for backend in value
                              if backend in self.config]
        return self._backends

    def get_global(self):
        res = {}
        if not self.do_only_backends:
            # Assume sections have been removed as they have been used
            res = {key: self.get(key) for key in self.config}
            return {'global_defaults': res}
        return {'global_defaults': res}

    def get_api(self):
        res = {}
        if not self.do_only_backends:
            # compute_api_class used by API and Volume services
            for key, value in list(self.get('DEFAULT').items()):
                if (key != 'compute_api_class'
                        and (key.startswith('api_')
                             or key.startswith('osapi_')
                             or key.endswith('_api_class'))):
                    res[key] = value
                    self.remove('DEFAULT', key)
            if res:
                res = {'DEFAULT': res}
        return {'api': res}

    def get_scheduler(self):
        res = {}
        if not self.do_only_backends:
            for key, value in list(self.get('DEFAULT').items()):
                if key.startswith('scheduler_'):
                    res[key] = value
                    self.remove('DEFAULT', key)
            if res:
                res = {'DEFAULT': res}
        return {'scheduler': res}

    def get_volumes(self):
        backend_defaults = self.get('backend_defaults')
        defaults = {}
        fc_zm = {}
        volumes = {}
        if backend_defaults:
            self.remove('backend_defaults')
            defaults['backend_defaults'] = backend_defaults

        if self.get('DEFAULT', 'zoning_mode') == ['fabric']:
            fc_zm['DEFAULT'] = {'zoning_mode': ['fabric']}
            self.remove('DEFAULT', 'zoning_mode')

            zone_manager_cfg = self.get('fc-zone-manager')
            fc_zm['fc-zone-manager'] = zone_manager_cfg
            self.remove('fc-zone-manager')

            fc_sections = zone_manager_cfg['fc_fabric_names'][-1].split(',')
            fc_fabric_cfg = {section: self.config[section]
                             for section in fc_sections
                             if section in self.config}
            fc_zm.update(fc_fabric_cfg)
            for section in fc_sections:
                self.remove(section)

        volumes = {backend: {backend: self.config[backend]}
                   for backend in self.backends}
        if fc_zm:
            for backend in volumes:
                if self.uses_fc(backend):
                    volumes[backend].update(fc_zm)

        self.remove('DEFAULT', 'enabled_backends')
        if volumes:
            for volume in volumes:
                self.remove(volume)
        return {'volume_global': defaults,
                'volumes': volumes,
                'fc_zonemgr': fc_zm}

    def get_backup(self):
        leave = ('backup_use_temp_snapshot',   # Used by the volume service
                 'backup_use_same_host')  # Used by the scheduler
        res = {}
        for key, value in list(self.get('DEFAULT').items()):
            if key.startswith('backup_') and key not in leave:
                res[key] = value
                self.remove('DEFAULT', key)
        if res:
            res = {'DEFAULT': res}
        return {'backup': res}


WARNING_MSG = 'ALWAYS REVIEW RESULTS, OUTPUT IS JUST A ROUGH DRAFT!!\n'


def arg_parser():
    parser = argparse.ArgumentParser(
        description=('Cinder Configuration Migration Helper: '
                     'From Director to Operator'),
        epilog=WARNING_MSG)
    parser.add_argument('-b', '--only-backends', action='store_true',
                        help=('Only keep the volume and backup related '
                              'sections and drop everything else.'))
    parser.add_argument('-c', '--config',
                        type=argparse.FileType('rt'), default='cinder.conf',
                        help=('Cinder configuration to convert (defaults to '
                              'cinder.conf)'))
    parser.add_argument('-o', '--out-dir', default='.',
                        help=('Directory to write the resulting patch and '
                              'manifest (defaults to current directory)'))
    parser.add_argument('-m', '--no-machineconfig', action='store_true',
                        help=('Assume OpenShift has all storage related '
                              'services or kernel modules loaded so there is '
                              'no need to generate the MachineConfig objects '
                              'in the manifest'))
    parser.add_argument('-n', '--name', default='openstack',
                        help=('Name of the OpenStackControlPlane object '
                              'deployed in OpenShift. Defaults to openstack'))
    parser.add_argument('-v', '--verbose', action='count', default=0,
                        help=("Increase verbose level each time it's passed, "
                              "-v=Info, -vv=Debug")),
    args = parser.parse_args()
    return args

# TODO: Do the extra mounts for all file warnings
# TODO: Support labels for Cinder services
# TODO: Support changing IPs
# TODO: Service user: Maybe don't just remove it? For director it is fine


LOG_LEVELS = {0: logging.WARNING, 1: logging.INFO, 2: logging.DEBUG}


if __name__ == '__main__':
    args = arg_parser()
    LOG.basicConfig(level=LOG_LEVELS[min(args.verbose, 2)])
    transformer = CinderTransformer(args.config, args.no_machineconfig,
                                    args.only_backends, args.name)
    with open(os.path.join(args.out_dir, PATCH_FILE), 'wt') as f:
        transformer.write_patch(f)
    with open(os.path.join(args.out_dir, PREREQ_FILE), 'wt') as f:
        wrote_manifests = transformer.write_manifest(f)
    LOG.warning(WARNING_MSG)
    file_names = ['cinder.patch']
    if wrote_manifests:
        file_names.append(PREREQ_FILE)
    else:
        os.remove(PREREQ_FILE)
    print(f'Output written at {args.out_dir}: {", ".join(file_names)}')
