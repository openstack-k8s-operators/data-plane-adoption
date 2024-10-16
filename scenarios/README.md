# OSP 17.1 scenarios

The files stored in this folder define different osp 17.1 deployments to be
tested with adoption. For each scenario, we have a <scenario_name>.yaml file
and folder with the same name. The yaml file contains variables that will be
used to customize the scenario, while the folder contains files that will be
used in the deployment (network_data, role files, etc.).

This scenario definition assumes that all relevant parameters to the
deployment are known, with the exception of infra-dependent values like ips or
hostnames.

## Scenario definition file

The scenario definition file (the <scenario_name>.yaml) has the following top
level sections:

- `undercloud`
- `stacks`
- `cloud_domain`
- `hostname_groups_map`
- `roles_groups_map`
- `hooks`

### Undercloud section

The undercloud section contains the following parameters (all optional):

- `config`: a list of options to set in `undercloud.conf` file, each entry is
a dictionary with the fields `section`, `option` and `value`.
- `undercloud_parameters_override`: path to a file that contains some parameters
for the undercloud setup, is passed through the `hieradata_override` option in
the `undercloud.conf`.
- `undercloud_parameters_defaults`: path to a file that contains
parameters_defaults for the undercloud, is passed through the `custom_env_files`
option in the `undercloud.conf`.
- `routes`: list of routes to define in the undercloud os_net_config template.
List of dictionaries with the fields `ip_netmask`, `next_hop` and `default`.
- `os_net_config_iface`: string with the name of the network interface to
assign to bridge, default is `nic2`.

### Stacks section

The stacks section contains list of stacks to be deployed. Typically, this will
be just one, commonly known as `overcloud`, but there can be arbitrarily many.
For each entry the following parameters can be passed:

- `stackname`: name of the stack deployment.
- `args`: list of cli arguments to use when deploying the stack.
- `vars`: list of environment files to use when deploying the stack.
- `network_data_file`:  path to the network_data file that defines the network
to use in the stack, required. This file can be a yaml or jinja file. It it
ends with `j2`, it will be treated as a template, otherwise it'll be copied as
is.
- `vips_data_file`:  path to the file defining the virtual ips to use in the
stack, required.
- `roles_file`: path to the file defining the roles of the different nodes
used in the stack, required.
- `config_download_file`: path to the config-download file used to pass
environment variables to the stack, required.
- `ceph_osd_spec_file`: path to the osd spec file used to deploy ceph when
applicable, optional.
- `deploy_command`: string with the stack deploy command to run verbatim,
if defined, it ignores the `vars` and `args` fields, optional.
- `stack_nodes`: list of groups for the inventory that contains the nodes that
will be part of the stack, required. This groups must be a subset of the groups
used as keys in `hostname_groups_map` and `roles_groups_map`.
- `routes`: list of routes to define in the nodes' os_net_config template.
List of dictionaries with the fields `ip_netmask`, `next_hop` and `default`.
- `os_net_config_iface`: string with the name of the network interface to
assign to bridge, default is `nic2`.

### Cloud domain

Name of the dns domain used for the overcloud, particularly relevant for tlse
environments.

### Hostname groups map

Map that relates ansible groups in the inventory produced by the infra creation
to role hostname format for 17.1 deployment. This allows to tell which nodes
belong to the overcloud without trying to rely on specific naming. Used to
build the hostnamemap. For example, let's assume that we have an inventory with
a group called `osp-computes` that contains the computes, and a group called
`osp-controllers` that contains the controllers, then a possible map would look
like:

```
hostname_groups_map:
  osp-computes: "overcloud-novacompute"
  osp-controllers: "overcloud-controller"
```

### Roles groups map

Map that relates ansible groups in the inventory produced by the infra creation
to OSP roles. This allows to build a tripleo-ansible-inventory which is used,
for example, to deploy Ceph. Continuing from the example mentioned in the
previous section, a possible value for this map would be:

```
hostname_groups_map:
  osp-computes: "Compute"
  osp-controllers: "Controller"
```

### Hooks

Hooks are a mechanism used in the ci-framework to run external code without
modifying the project's playbooks. See the [ci-framework
docs](https://ci-framework.readthedocs.io/en/latest/roles/run_hook.html) for
more details about how hooks are used in the ci-framework.

For deployment of osp 17.1, the following hooks are available:

- `pre_uc_run`, runs before deploying the undercloud
- `post_uc_run`, runs after deploying the undercloud
- `pre_oc_run`, runs before deploying the overcloud, but after provisioning
networks and virtual ips
- `post_oc_run`, runs after deploying the overcloud

Hooks provide flexibility to the users without adding too much complexity to
the ci-framework. An example of use case of hooks here, is to deploy ceph for
the scenarios that require it. Instead of having some flag in the code to
select whether we should deploy it or not, we can deploy it using the
`pre_oc_run`, like this:

```
pre_oc_run:
  - name: Deploy Ceph
    type: playbook
    source: "adoption_deploy_ceph.yml"
```

Since the `source` attribute is not an absolute path, this example assumes that
the `adoption_deploy_ceph.yml` playbook exists in the ci-framework (it
introduced alongside the role to consume the scenarios defined here by
[this PR](https://github.com/openstack-k8s-operators/ci-framework/pull/2297)).
