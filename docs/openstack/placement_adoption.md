# Placement adoption

## Prerequisites

* Previous Adoption steps completed. Notably,
  * the [service databases](mariadb_copy.md)
    must already be imported into the podified MariaDB.
  * the [Keystone service](keystone_adoption.md) needs to be imported.
  * the Memcached operator needs to be deployed (nothing to import for it from
    the source environment).

## Variables

(There are no shell variables necessary currently.)

## Procedure - Placement adoption

* Patch OpenStackControlPlane to deploy Placement:

  ```bash
  oc patch openstackcontrolplane openstack --type=merge --patch '
  spec:
    placement:
      enabled: true
      apiOverride:
        route: {}
      template:
        databaseInstance: openstack
        secret: osp-secret
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
  '
  ```

## Post-checks

* See that Placement endpoints are defined and pointing to the
  podified FQDNs and that Placement API responds.

  ```bash
  alias openstack="oc exec -t openstackclient -- openstack"

  openstack endpoint list | grep placement


  # Without OpenStack CLI placement plugin installed:
  PLACEMENT_PUBLIC_URL=$(openstack endpoint list -c 'Service Name' -c 'Service Type' -c URL | grep placement | grep public | awk '{ print $6; }')
  oc exec -t openstackclient -- curl "$PLACEMENT_PUBLIC_URL"

  # With OpenStack CLI placement plugin installed:
  openstack resource class list
  ```
