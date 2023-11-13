## Prerequisites

* Previous Adoption steps completed. Notably,
  * the [service databases](mariadb_copy.md)
    must already be imported into the podified MariaDB.

## Variables

(There are no shell variables necessary currently.)

## Pre-checks

## Procedure - Keystone adoption

* Patch OpenStackControlPlane to deploy Keystone:

  ```
  oc patch openstackcontrolplane openstack --type=merge --patch '
  spec:
    keystone:
      enabled: true
      apiOverride:
        route: {}
      template:
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
        databaseInstance: openstack
        secret: osp-secret
  '
  ```

* Create alias to use `openstack` command in the adopted deployment:

  ```bash
  alias openstack="oc exec -t openstackclient -- openstack"
  ```

* Clean up old services and endpoints that still point to the old
  control plane (everything except Keystone service and endpoints):

  ```bash
  openstack endpoint list | grep keystone | awk '/admin/{ print $2; }' | xargs ${BASH_ALIASES[openstack]} endpoint delete || true

  for service in cinderv3 glance neutron nova placement swift; do
    openstack service list | awk "/ $service /{ print \$2; }" | xargs ${BASH_ALIASES[openstack]} service delete || true
  done
  ```

## Post-checks

* See that Keystone endpoints are defined and pointing to the podified
  FQDNs:

  ```bash
  openstack endpoint list | grep keystone
  ```
