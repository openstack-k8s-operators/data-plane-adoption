# Nova adoption

> **NOTE** This example scenario describes a simple single-cell setup. Real
> multi-stack topology recommended for production use results in different
> cells DBs layout, and should be using different naming schemes (not covered
> here this time).

## Prerequisites

* Previous Adoption steps completed. Notably,
  * the [service databases](mariadb_copy.md)
    must already be imported into the podified MariaDB;
  * the [Keystone service](keystone_adoption.md) needs to be imported;
  * the [Placement service](placement_adoption.md) needs to be imported;
  * the [Glance service](glance_adoption.md) needs to be imported;
  * the [OVN DB services](ovn_adoption.md) need to be imported;
  * the [Neutron service](neutron_adoption.md) needs to be imported;
  * Required services specific topology [configuration collected](pull_openstack_configuration.md#get-services-topology-specific-configuration);
  * OpenStack services have been [stopped](stop_openstack_services.md)

## Variables

Define the shell variables and aliases used in the steps below. The values are
just illustrative, use values that are correct for your environment:

```bash
alias openstack="oc exec -t openstackclient -- openstack"
```

## Procedure - Nova adoption

> **NOTE**: We assume Nova Metadata deployed on the top level and not on each
> cell level, so this example imports it the same way. If the source deployment
> has a per cell metadata deployment, adjust the given below patch as needed.
> Metadata service cannot be run in `cell0`.

* Patch OpenStackControlPlane to deploy Nova:

  ```yaml
  oc patch openstackcontrolplane openstack -n openstack --type=merge --patch '
  spec:
    nova:
      enabled: true
      apiOverride:
        route: {}
      template:
        secret: osp-secret
        apiServiceTemplate:
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
          customServiceConfig: |
            [workarounds]
            disable_compute_service_check_for_ffu=true
        metadataServiceTemplate:
          enabled: true # deploy single nova metadata on the top level
          override:
            service:
              metadata:
                annotations:
                  metallb.universe.tf/address-pool: internalapi
                  metallb.universe.tf/allow-shared-ip: internalapi
                  metallb.universe.tf/loadBalancerIPs: 172.17.0.80
              spec:
                type: LoadBalancer
          customServiceConfig: |
            [workarounds]
            disable_compute_service_check_for_ffu=true
        schedulerServiceTemplate:
          customServiceConfig: |
            [workarounds]
            disable_compute_service_check_for_ffu=true
        cellTemplates:
          cell0:
            conductorServiceTemplate:
              customServiceConfig: |
                [workarounds]
                disable_compute_service_check_for_ffu=true
          cell1:
            metadataServiceTemplate:
              enabled: false # enable here to run it in a cell instead
              override:
                  service:
                    metadata:
                      annotations:
                        metallb.universe.tf/address-pool: internalapi
                        metallb.universe.tf/allow-shared-ip: internalapi
                        metallb.universe.tf/loadBalancerIPs: 172.17.0.80
                    spec:
                      type: LoadBalancer
              customServiceConfig: |
                [workarounds]
                disable_compute_service_check_for_ffu=true
            conductorServiceTemplate:
              customServiceConfig: |
                [workarounds]
                disable_compute_service_check_for_ffu=true
  '
  ```

* Wait for Nova control plane services' CRs to become ready:

  ```bash
  oc get nova --field-selector metadata.name=nova-api -o jsonpath='{.items[0].status.conditions}' \
  | jq -e '.[]|select(.type=="Ready" and .status=="True")'
  oc get novaapis --field-selector metadata.name=nova-api -o jsonpath='{.items[0].status.conditions}' \
  | jq -e '.[]|select(.type=="Ready" and .status=="True")'
  oc get novacells --field-selector metadata.name=nova-cell0 -o jsonpath='{.items[0].status.conditions}' \
  | jq -e '.[]|select(.type=="Ready" and .status=="True")'
  oc get novacells --field-selector metadata.name=nova-cell1 -o jsonpath='{.items[0].status.conditions}' \
  | jq -e '.[]|select(.type=="Ready" and .status=="True")'
  oc get novaconductors --field-selector metadata.name=nova-cell0-conductor -o jsonpath='{.items[0].status.conditions}' \
  | jq -e '.[]|select(.type=="Ready" and .status=="True")'
  oc get novaconductors --field-selector metadata.name=nova-cell1-conductor -o jsonpath='{.items[0].status.conditions}' \
  | jq -e '.[]|select(.type=="Ready" and .status=="True")'
  oc get novametadata --field-selector metadata.name=nova-metadata -o jsonpath='{.items[0].status.conditions}' \
  | jq -e '.[]|select(.type=="Ready" and .status=="True")'
  oc get novanovncproxies --field-selector metadata.name=nova-cell1-novncproxy -o jsonpath='{.items[0].status.conditions}' \
  | jq -e '.[]|select(.type=="Ready" and .status=="True")'
  oc get novaschedulers --field-selector metadata.name=nova-scheduler -o jsonpath='{.items[0].status.conditions}' \
  | jq -e '.[]|select(.type=="Ready" and .status=="True")'
  ```

  The local Conductor services will be started for each cell, while the superconductor runs in `cell0`.
  Note that ``disable_compute_service_check_for_ffu`` is mandatory for all imported Nova services, until
  the [external dataplane imported](edpm_adoption.md), and until Nova Compute services fast-forward upgraded.

## Post-checks

* Check that Nova endpoints are defined and pointing to the
  podified FQDNs and that Nova API responds.

  ```bash
  openstack endpoint list | grep nova
  openstack server list
  ```

Compare the following outputs with the topology specific configuration
[collected earlier](pull_openstack_configuration.md#get-services-topology-specific-configuration):

* Query the superconductor for cell1 existance:

  ```bash
  oc rsh nova-cell0-conductor-0 nova-manage cell_v2 list_cells | grep -F '| cell1 |'
  ```

  The expected changes to happen:
  * cell1's `nova` DB and user name become `nova_cell1`.
  * Default cell is renamed to `cell1` (in a multi-cell setup, it should become indexed as the last cell instead).
  * RabbitMQ transport URL no longer uses `guest`.

* Verify no Nova compute dataplane disruptions during the adoption/upgrade process:

  ```bash
  $CONTROLLER_SSH sudo podman exec -it libvirt_virtqemud virsh list --all | grep 'instance-00000001   running'
  ```

  * Verify if Nova services control the existing VM instance:

  ```bash
  openstack server list | grep -qF '| test | ACTIVE |' && openstack server stop test
  openstack server list | grep -qF '| test | SHUTOFF |'
  $CONTROLLER_SSH sudo podman exec -it libvirt_virtqemud virsh list --all | grep 'instance-00000001   shut off'

  openstack server list | grep -qF '| test | SHUTOFF |' && openstack server start test
  openstack server list | grep -F '| test | ACTIVE |'
  $CONTROLLER_SSH sudo podman exec -it libvirt_virtqemud virsh list --all | grep 'instance-00000001   running'
  ```
  Note that in this guide, the same host acts as a controller, and also as a compute.
