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
  oc wait --for condition=Ready --timeout=300s Nova/nova
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
