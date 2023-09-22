# Cinder adoption

Adopting a director deployed Cinder service into OpenStack may require some
thought because it's not always a simple process.

Usually the adoption process entails:

- Checking existing limitations.
- Considering the placement of the cinder services.
- Preparing the OpenShift nodes where volume and backup services will run.
- Crafting the manifest based on the existing `cinder.conf` file.
- Deploying Cinder.
- Validating the new deployment.

This guide provides necessary knowledge to complete these steps in most
situations, but it still requires knowledge on how OpenStack services work and
the structure of a Cinder configuration file.

## Limitations

There are currently some limitations that are worth highlighting; some are
related to this guideline while some to the operator:

- There is no global `nodeSelector` for all cinder volumes, so it needs to be
specified per backend.  This may change in the future.

- There is no global `customServiceConfig` or `customServiceConfigSecrets` for
all cinder volumes, so it needs to be specified per backend.  This may change in
the future.

- Adoption of LVM backends, where the volume data is stored in the compute
nodes, is not currently being documented in this process. It may get documented
in the future.

- Support for Cinder backends that require kernel modules not included in RHEL
has not been tested in Operator deployed OpenStack so it is not documented in
this guide.

- Adoption of DCN/Edge deployment is not currently described in this guide.

## Prerequisites

* Previous Adoption steps completed. Notably, cinder service must have been
stopped and the service databases must already be imported into the podified
MariaDB.

* Storage network has been properly configured on the OpenShift cluster.

## Variables

No new environmental variables need to be defined, though we use the
`CONTROLLER1_SSH` that was defined in a previous step for the pre-checks.

## Pre-checks

We are going to need the contents of `cinder.conf`, so we may want to download
it to have it locally accessible:

```
$CONTROLLER1_SSH cat /var/lib/config-data/puppet-generated/cinder/etc/cinder/cinder.conf > cinder.conf
```

## Prepare OpenShift

As explained the [planning section](planning.md) before deploying OpenStack in
OpenShift we need to ensure that the networks are ready, that we have decided
the node selection, and also make sure any necessary changes to the OpenShift
nodes have been made.  For Cinder volume and backup services all these 3 must
be carefully considered.

### Node Selection

We may need, or want, to restrict the OpenShift nodes where cinder volume and
backup services can run.

The best example of when we need to do node selection for a specific cinder
service in when we deploy Cinder with the LVM driver. In that scenario the
LVM data where the volumes are stored only exists in a specific host, so we
need to pin the cinder-volume service to that specific OpenShift node.  Running
the service on any other OpenShift node would not work.  Since `nodeSelector`
only works on labels we cannot use the OpenShift host node name to restrict
the LVM backend and we'll need to identify it using a unique label, an existing
or new one:

```bash
$ oc label nodes worker0 lvm=cinder-volumes
```

```yaml
apiVersion: core.openstack.org/v1beta1
kind: OpenStackControlPlane
metadata:
  name: openstack
spec:
  secret: osp-secret
  storageClass: local-storage
  cinder:
    enabled: true
    template:
      cinderVolumes:
        lvm-iscsi:
          nodeSelector:
            lvm: cinder-volumes
< . . . >
```

As mentioned in the [Node Selector guide](node-selector.md), an example where we
need to use labels is when using FC storage and we don't have HBA cards in all
our OpenShift nodes. In this scenario we would need to restrict all the cinder
volume backends (not only the FC one) as well as the backup services.

Depending on the cinder backends, their configuration, and the usage of Cinder,
we can have network intensive cinder volume services with lots of I/O as well as
cinder backup services that are not only network intensive but also memory and
CPU intensive.  This may be a concern for the OpenShift human operators, and
they may want to use the `nodeSelector` to prevent these service from
interfering with their other OpenShift workloads

Please make sure to read the [Nodes Selector guide](node-selector) before
continuing, as we'll be referring to some of the concepts explained there in the
following sections.

When selecting the nodes where cinder volume is going to run please remember
that cinder-volume may also use local storage when downloading a glance image
for the create volume from image operation, and it can require a considerable
amount of space when having concurrent operations and not using cinder volume
cache.

If we don't have nodes with enough local disk space for the temporary images we
can use a remote NFS location for the images. This is something that we had to
manually setup in Director deployments, but with operators we can easily do it
automatically using the extra volumes feature ()`extraMounts`.

### Transport protocols

Due to the specifics of the storage transport protocols some changes may be
required on the OpenShift side, and although this is something that must be
documented by the Vendor here wer are going to provide some generic
instructions that can serve as a guide for the different transport protocols.

Check the backend sections in our `cinder.conf` file that are listed in the
`enabled_backends` configuration option to figure out the transport storage
protocol used by the backend.

Depending on the backend we can find the transport protocol:

- Looking at the `volume_driver` configuration option, as it may contain the
  protocol itself: RBD, iSCSI, FC...

- Looking at the `target_protocol` configuration option

*Warning:* Any time a `MachineConfig` is used to make changes to OpenShift
nodes the node will reboot!!  Act accordingly.

#### NFS

There's nothing to do for NFS. OpenShift can connect to NFS backends without
any additional changes.

#### RBD/Ceph

There's nothing to do for RBD/Ceph in terms of preparing the nodes, OpenShift
can connect to Ceph backends without any additional changes. Credentials and
configuration files will need to be provided to the services though.

#### iSCSI

Connecting to iSCSI volumes requires that the iSCSI initiator is running on the
OpenShift hosts hosts where volume and backup services are going to run, because
the Linux Open iSCSI initiator doesn't currently support network namespaces, so
we must only run 1 instance of the service for the normal OpenShift usage, plus
the OpenShift CSI plugins, plus the OpenStack services.

If we are not already running `iscsid` on the OpenShift nodes then we'll need
to apply a `MachineConfig` similar to this one:

```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
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
```

Remember that if we are using labels to restrict the nodes where cinder
services are running we'll need to use a `MachineConfigPool` as described in
the [nodes selector guide](node-labels) to limit the effects of the
`MachineConfig` to only the nodes were our services may run.

If we are using a toy single node deployment to test the process we may need to
replace `worker` with `master` in the `MachineConfig`.

For production deployments using iSCSI volumes we always recommend setting up
multipathing, please look at the [multipathing section](#multipathing) to see
how to configure it.

**TODO:** Add, or at least mention, the Nova eDPM side for iSCSI.

#### FC

There's nothing to do for FC volumes to work, but the *cinder volume and cinder
backup services need to run in an OpenShift host that has HBAs*, so if there
are nodes that don't have HBAs then we'll need to use labels to restrict where
these services can run, as mentioned in the [node labels section](#node-labels).

This also means that for virtualized OpenShift clusters using FC we'll need to
expose the host's HBAs inside the VM.

For production deployments using FC volumes we always recommend setting up
multipathing, please look at the [multipathing section](#multipathing) to see
how to configure it.

#### NVMe-oF

Connecting to NVMe-oF volumes requires that the nvme kernel modules are loaded
on the OpenShift hosts.

If we are not already loading the `nvme-fabrics` module on the OpenShift nodes
where volume and backup services are going to run then we'll need to apply a
`MachineConfig` similar to this one:

```
apiVersion: machineconfiguration.openshift.io/v1
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
            # Source can be a http, https, tftp, s3, gs, or data as defined in rfc2397.
            # This is the rfc2397 text/plain string format
            source: data:,nvme-fabrics
```

Remember that if we are using labels to restrict the nodes where cinder
services are running we'll need to use a `MachineConfigPool` as described in
the [nodes selector guide](node-labels) to limit the effects of the
`MachineConfig` to only the nodes were our services may run.

If we are using a toy single node deployment to test the process we may need to
replace `worker` with `master` in the `MachineConfig`.

We are only loading the `nvme-fabrics` module because it takes care of loading
the transport specific modules (tcp, rdma, fc) as needed.

For production deployments using NVMe-oF volumes we always recommend using
multipathing. For NVMe-oF volumes OpenStack uses native multipathing, called
[ANA](https://nvmexpress.org/faq-items/what-is-ana-nvme-multipathing/).

Once the OpenShift nodes have rebooted and are loading the `nvme-fabrics` module
we can confirm that the Operating System is configured and supports ANA by
checking on the host:

```
cat /sys/module/nvme_core/parameters/multipath
```

**Attention:** ANA doesn't use the Linux Multipathing Device Mapper, but the
*current OpenStack
code requires `multipathd` on compute nodes to be running for Nova to be able to
use multipathing, so please remember to follow the multipathing part for compute
nodes on the [multipathing section](#multipathing).

**TODO:** Add, or at least mention, the Nova eDPM side for NVMe-oF.

#### Multipathing

For iSCSI and FC protocols we always recommend using multipathing, which
has 4 parts:

- Prepare the OpenShift hosts
- Configure the Cinder services
- Prepare the Nova computes
- Configure the Nova service

To prepare the OpenShift hosts we need to ensure that the Linux Multipath
Device Mapper is configured and running on the OpenShift hosts, and we do
that using `MachineConfig` like this one:

```yaml
# Includes the /etc/multipathd.conf contents and the systemd unit changes
apiVersion: machineconfiguration.openshift.io/v1
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
            # Source can be a http, https, tftp, s3, gs, or data as defined in rfc2397.
            # This is the rfc2397 text/plain string format
            source: data:,defaults%20%7B%0A%20%20user_friendly_names%20no%0A%20%20recheck_wwid%20yes%0A%20%20skip_kpartx%20yes%0A%20%20find_multipaths%20yes%0A%7D%0A%0Ablacklist%20%7B%0A%7D
    systemd:
      units:
      - enabled: true
        name: multipathd.service
```

Remember that if we are using labels to restrict the nodes where cinder
services are running we'll need to use a `MachineConfigPool` as described in
the [nodes selector guide](node-labels) to limit the effects of the
`MachineConfig` to only the nodes were our services may run.

If we are using a toy single node deployment to test the process we may need to
replace `worker` with `master` in the `MachineConfig`.

To configure the cinder services to use multipathing we need to enable the
`use_multipath_for_image_xfer` configuration option in all the backend sections
and in the `[DEFAULT]` section for the backup service, but in Podified
deployments we don't need to worry about it, because that's the default. So as
long as we don't override it setting `use_multipath_for_image_xfer = false` then
multipathing will work as long as the service is running on the OpenShift host.

**TODO:** Add, or at least mention, the Nova eDPM side for Multipathing once
it's implemented.

## Configurations

As described in the [planning](planning.md) Cinder is configured using
configuration snippets instead of using obscure configuration parameters
defined by the installer.

The recommended way to deploy Cinder volume backends has changed to remove old
limitations, add flexibility, and improve operations in general.

When deploying with Director we used to run a single Cinder volume service with
all our backends (each backend would run on its own process), and even though
that way of deploying is still supported, we don't recommend it. We recommend
using a volume service per backend since it's a superior deployment model.

So for an LVM and a Ceph backend we would have 2 entries in `cinderVolume` and,
as mentioned in the limitations section, we cannot set global defaults for all
volume services, so we would have to define it for each of them, like this:

```yaml
apiVersion: core.openstack.org/v1beta1
kind: OpenStackControlPlane
metadata:
  name: openstack
spec:
  cinder:
    enabled: true
    template:
      cinderVolume:
        lvm:
          customServiceConfig: |
            [DEFAULT]
            debug = True
            [lvm]
< . . . >
        ceph:
          customServiceConfig: |
            [DEFAULT]
            debug = True
            [ceph]
< . . . >
```

Reminder that for volume backends that have sensitive information using `Secret`
and the `customServiceConfigSecrets` key is the recommended way to go.

## Prepare the configuration

For adoption instead of using a whole deployment manifest we'll use a targeted
patch, like we did with other services, and in this patch we will enable the
different cinder services with their specific configurations.

**WARNING:** Check that all configuration options are still valid for the new
OpenStack version, since configuration options may have been deprecated,
removed, or added. This applies to both backend driver specific configuration
options and other generic options.

There are 2 ways to prepare a cinder configuration for adoption, tailor-making
it or doing it quick and dirty. There is no difference in how Cinder will
operate with both methods, so we are free to chose, though we recommend
tailor-making it whenever possible.

The high level explanation of the tailor-made approach is:

1. Determine what part of the configuration is generic for all the cinder
services and remove anything that would change when deployed in OpenShift, like
the `connection` in the `[dabase]` section, the `transport_url` and `log_dir` in
`[DEFAULT]`, the whole `[coordination]` section.  This configuration goes into
the `customServiceConfig` (or a `Secret` and then used in
`customServiceConfigSecrets`) at the `cinder: template:` level.

2. Determine if there's any scheduler specific configuration and add it to the
`customServiceConfig` section in `cinder: template: cinderScheduler`.

3. Determine if there's any API specific configuration and add it to the
`customServiceConfig` section in `cinder: template: cinderAPI`.

4. If we have cinder backup deployed, then we'll get the cinder backup relevant
configuration options and add them to `customServiceConfig` (or a `Secret` and
then used in `customServiceConfigSecrets`) at the `cinder: template:
cinderBackup:` level. We should remove the `host` configuration in the
`[DEFAULT]` section to facilitate supporting multiple replicas in the future.

5. Determine the individual volume backend configuration for each of the
drivers. The configuration will not only be the specific driver section, it
should also include the `[backend_defaults]` section and FC zoning sections is
they are being used, because the cinder operator doesn't support a
`customServiceConfig` section global for all volume services.  Each backend
would have its own section under `cinder: template: cinderVolumes` and the
configuration would go in `customServiceConfig` (or a `Secret` and then used in
`customServiceConfigSecrets`).

6. Check if any of the cinder volume drivers being used requires a custom vendor
image. If they do, find the location of the image in the vendor's instruction
available in the w [OpenStack Cinder ecosystem
page](https://catalog.redhat.com/software/search?target_platforms=Red%20Hat%20OpenStack%20Platform&p=1&functionalCategories=Data%20storage)
and add it under the specific's driver section using the `containerImage` key.
For example, if we had a Pure Storage array and the driver was already certified
for OSP18, then we would have something like this:

   ```yaml
   spec:
     cinder:
       enabled: true
       template:
         cinderVolume:
           pure:
             containerImage: registry.connect.redhat.com/purestorage/openstack-cinder-volume-pure-rhosp-18-0'
             customServiceConfigSecrets:
               - openstack-cinder-pure-cfg
   < . . . >
   ```

7. External files: Cinder services sometimes use external files, for example for
a custom policy, or to store credentials, or SSL CA bundles to connect to a
storage array, and we need to make those files available to the right
containers. To achieve this we'll use `Secrets` or `ConfigMap` to store the
information in OpenShift and then the `extraMounts` key. For example, for the
Ceph credentials stored in a `Secret` called `ceph-conf-files` we would patch
the top level `extraMounts` in `OpenstackControlPlane`:

   ```yaml
   spec:
     extraMounts:
     - extraVol:
       - extraVolType: Ceph
         mounts:
         - mountPath: /etc/ceph
           name: ceph
           readOnly: true
         propagation:
         - CinderVolume
         - CinderBackup
         - Glance
         volumes:
         - name: ceph
           projected:
             sources:
             - secret:
                 name: ceph-conf-files
   ```
   But for a service specific one, like the API policy, we would do it directly
   on the service itself, in this example we include the cinder API
   configuration that references the policy we are adding from a `ConfigMap`
   called `my-cinder-conf` that has a key `policy` with the contents of the
   policy:
   ```yaml
   spec:
     cinder:
       enabled: true
       template:
         cinderAPI:
           customServiceConfig: |
              [oslo_policy]
              policy_file=/etc/cinder/api/policy.yaml
         extraMounts:
         - extraVol:
           - extraVolType: Ceph
             mounts:
             - mountPath: /etc/cinder/api
               name: policy
               readOnly: true
             propagation:
             - CinderAPI
             volumes:
             - name: policy
               projected:
                 sources:
                 - configMap:
                     name: my-cinder-conf
                     items:
                       - key: policy
                         path: policy.yaml
   ```

The quick and dirty process is more straightforward:

1. Create an agnostic configuration file removing any specifics from the old
deployment's `cinder.conf` file, like the `connection` in the `[dabase]`
section, the `transport_url` and `log_dir` in `[DEFAULT]`, the whole
`[coordination]` section, etc..

2. Assuming the configuration has sensitive information, drop the modified
contents of the whole file into a `Secret`.

3. Reference this secret in all the services, creating a cinder volumes section
for each backend and just adding the respective `enabled_backends` option.

4. Add external files as mentioned in the last bullet of the tailor-made
configuration explanation.

Example of what the quick and dirty configuration patch would look like:

   ```yaml
   spec:
     cinder:
       enabled: true
       template:
         cinderAPI:
           customServiceConfigSecrets:
             - cinder-conf
         cinderScheduler:
           customServiceConfigSecrets:
             - cinder-conf
         cinderBackup:
           customServiceConfigSecrets:
             - cinder-conf
         cinderVolume:
           lvm1:
             customServiceConfig: |
               [DEFAULT]
               enabled_backends = lvm1
             customServiceConfigSecrets:
               - cinder-conf
           lvm2:
             customServiceConfig: |
               [DEFAULT]
               enabled_backends = lvm2
             customServiceConfigSecrets:
               - cinder-conf
   ```

### Configuration generation helper tool

Creating the right Cinder configuration files to deploy using Operators may
sometimes be a complicated experience, especially the first times, so we have a
helper tool that can create a draft of the files from a `cinder.conf` file.

This tool is not meant to be a automation tool, it's mostly to help us get the
gist of it, maybe point out some potential pitfalls and reminders.

**Attention:** The tools requires `PyYAML` Python package to be installed (`pip
install PyYAML`).

This [cinder-cfg.py script](helpers/cinder-cfg.py) defaults to reading the
`cinder.conf` file from the current directory (unless `--config` option is used)
and outputs files to the current directory (unless `--out-dir` option is used).

In the output directory we'll always get a `cinder.patch` file with the Cinder
specific configuration patch to apply to the `OpenStackControlPlane` CR but we
may also get an additional file called `cinder-prereq.yaml` file with some
`Secrets` and `MachineConfigs`.

Example of an invocation setting input and output explicitly to the defaults for
a Ceph backend:

```bash
$ python cinder-cfg.py --config cinder.conf --out-dir ./
WARNING:root:Cinder is configured to use ['/etc/cinder/policy.yaml'] as policy file, please ensure this file is available for the podified cinder services using "extraMounts" or remove the option.

WARNING:root:Deployment uses Ceph, so make sure the Ceph credentials and configuration are present in OpenShift as a asecret and then use the extra volumes to make them available in all the services that would need them.

WARNING:root:You were using user ['nova'] to talk to Nova, but in podified we prefer using the service keystone username, in this case ['cinder']. Dropping that configuration.

WARNING:root:ALWAYS REVIEW RESULTS, OUTPUT IS JUST A ROUGH DRAFT!!

Output written at ./: cinder.patch
```

The script outputs some warnings to let us know things we may need to do
manually -adding the custom policy, provide the ceph configuration files- and
also let us know a change in how the `service_user` has been removed.

A different example when using multiple backends, one of them being a 3PAR FC
could be:

```
$ python cinder-cfg.py --config cinder.conf --out-dir ./
WARNING:root:Cinder is configured to use ['/etc/cinder/policy.yaml'] as policy file, please ensure this file is available for the podified cinder services using "extraMounts" or remove the option.

ERROR:root:Backend hpe_fc requires a vendor container image, but there is no certified image available yet. Patch will use the last known image for reference, but IT WILL NOT WORK

WARNING:root:Deployment uses Ceph, so make sure the Ceph credentials and configuration are present in OpenShift as a asecret and then use the extra volumes to make them available in all the services that would need them.

WARNING:root:You were using user ['nova'] to talk to Nova, but in podified we prefer using the service keystone username, in this case ['cinder']. Dropping that configuration.

WARNING:root:Configuration is using FC, please ensure all your OpenShift nodes have HBAs or use labels to ensure that Volume and Backup services are scheduled on nodes with HBAs.

WARNING:root:ALWAYS REVIEW RESULTS, OUTPUT IS JUST A ROUGH DRAFT!!

Output written at ./: cinder.patch, cinder-prereq.yaml
```

In this case we can see that there are additional messages, so let's quickly go over them:

- There's one message mentioning how this backend driver needs external vendor
dependencies so the standard container image will not work. Unfortunately this
image is still not available, so an older image is used in the output patch file
for reference. We can then replace this image with one we build ourselves or
with a Red Hat official one once the image is available. In this case we can see
in our `cinder.patch` file:
  ```
        cinderVolumes:
        hpe-fc:
          containerImage: registry.connect.redhat.com/hpe3parcinder/openstack-cinder-volume-hpe3parcinder17-0
  ```
- The FC message reminds us that this transport protocol requires specific HBA
cards to be present on the nodes where cinder services are running.

- In this case we also see that it has created the `cinder-prereq.yaml` file and
if we look into it we'll see there is one `MachineConfig` and one `Secret`. The
`MachineConfig` is called `99-master-cinder-enable-multipathd` and like the name
suggests enables multipathing on all the OCP worker nodes. The `Secret` is
called `openstackcinder-volumes-hpe_fc` and contains the 3PAR backend
configuration because it has sensitive information (credentials), and in the
`cinder.patch` file we'll see that it uses this configuration:
  ```
     cinderVolumes:
        hpe-fc:
          customServiceConfigSecrets:
          - openstackcinder-volumes-hpe_fc
  ```

## Procedure - Cinder adoption

Assuming we have already stopped cinder services, prepared the OpenShift nodes,
deployed the OpenStack operators and a bare OpenStack manifest, and migrated the
database, and prepared the patch manifest with the Cinder service configuration,
all that's left is to apply the patch and wait for the operator to apply the
changes and deploy the Cinder services.

Our recommendation is to write the patch manifest into a file, for example
`cinder.patch` and then apply it with something like:

```bash
oc patch openstackcontrolplane openstack --type=merge --patch-file=cinder.patch
```

For example, for the RBD deployment from the Development Guide the
`cinder.patch` would look like this:

```yaml
spec:
  extraMounts:
  - extraVol:
    - extraVolType: Ceph
      mounts:
      - mountPath: /etc/ceph
        name: ceph
        readOnly: true
      propagation:
      - CinderVolume
      - CinderBackup
      - Glance
      volumes:
      - name: ceph
        projected:
          sources:
          - secret:
              name: ceph-conf-files
  cinder:
    enabled: true
    apiOverride:
      route: {}
    template:
      databaseInstance: openstack
      secret: osp-secret
      cinderAPI:
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
        replicas: 1
        customServiceConfig: |
          [DEFAULT]
          default_volume_type=tripleo
      cinderScheduler:
        replicas: 1
      cinderBackup:
        networkAttachments:
        - storage
        replicas: 1
        customServiceConfig: |
          [DEFAULT]
          backup_driver=cinder.backup.drivers.ceph.CephBackupDriver
          backup_ceph_conf=/etc/ceph/ceph.conf
          backup_ceph_user=openstack
          backup_ceph_pool=backups
      cinderVolumes:
        ceph:
          networkAttachments:
          - storage
          replicas: 1
          customServiceConfig: |
            [tripleo_ceph]
            backend_host=hostgroup
            volume_backend_name=tripleo_ceph
            volume_driver=cinder.volume.drivers.rbd.RBDDriver
            rbd_ceph_conf=/etc/ceph/ceph.conf
            rbd_user=openstack
            rbd_pool=volumes
            rbd_flatten_volume_from_snapshot=False
            report_discard_supported=True
```

Once the services have been deployed we'll need to clean up the old scheduler
and backup services which will appear as being down while we have others that
appear as being up:

```bash
openstack volume service list

+------------------+------------------------+------+---------+-------+----------------------------+
| Binary           | Host                   | Zone | Status  | State | Updated At                 |
+------------------+------------------------+------+---------+-------+----------------------------+
| cinder-backup    | standalone.localdomain | nova | enabled | down  | 2023-06-28T11:00:59.000000 |
| cinder-scheduler | standalone.localdomain | nova | enabled | down  | 2023-06-28T11:00:29.000000 |
| cinder-volume    | hostgroup@tripleo_ceph | nova | enabled | up    | 2023-06-28T17:00:03.000000 |
| cinder-scheduler | cinder-scheduler-0     | nova | enabled | up    | 2023-06-28T17:00:02.000000 |
| cinder-backup    | cinder-backup-0        | nova | enabled | up    | 2023-06-28T17:00:01.000000 |
+------------------+------------------------+------+---------+-------+----------------------------+
```

In this case we need to remove services for hosts `standalone.localdomain`

```bash
oc exec -it cinder-scheduler-0 -- cinder-manage service remove cinder-backup standalone.localdomain
oc exec -it cinder-scheduler-0 -- cinder-manage service remove cinder-scheduler standalone.localdomain
```

The reason why we haven't preserved the name of the backup service is because
we have taken the opportunity to change its configuration to support
Active-Active, even though we are not doing so right now because we have 1
replica.

Now that we have the Cinder services running we know that the DB schema
migration has been completed and we can proceed to apply the DB data migrations.
While it is not necessary to run these data migrations at this precise moment,
because we can just run them right before the next upgrade, we consider that for
adoption it's best to run them now to make sure there are no issues before
running production workloads on the deployment.

The command to run the DB data migrations is:

```bash
oc exec -it cinder-scheduler-0 -- cinder-manage db online_data_migrations
```

## Post-checks

Before we can run any checks we need to set the right cloud configuration for
the `openstack` command to be able to connect to our OpenShift control plane.

Just like we did in the KeyStone adoption step we ensure we have the `openstack` alias defined:

```bash
alias openstack="oc exec -t openstackclient -- openstack"
```

Now we can run a set of tests to confirm that the deployment is there using our
old database contents:

* See that Cinder endpoints are defined and pointing to the podified
  FQDNs:

  ```
  openstack endpoint list --service cinderv3
  ```

* Check that the cinder services are running and up. The API won't show but if
  you get a response you know it's up as well:

  ```
  openstack volume service list
  ```

* Check that our old volume types, volumes, snapshots, and backups are there:

  ```
  openstack volume type list
  openstack volume list
  openstack volume snapshot list
  openstack volume backup list
  ```

To confirm that everything not only looks good but it's also properly working
we recommend doing some basic operations:

- Create a volume from an image to check that the connection to glance is
  working.
  ```bash
  openstack volume create --image cirros --bootable --size 1 disk_new
  ```

- Backup the old attached volume to a new backup. Example:
  ```bash
  openstack --os-volume-api-version 3.47 volume create --backup backup restored
  ```

We don't boot a nova instance using the new volume from image or try to detach
the old volume because nova and cinder are still not connected.
