## Prerequisites

* Previous Adoption steps completed. Notably, the service databases
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
      template:
        databaseInstance: openstack
        secret: osp-secret
        externalEndpoints:
        - endpoint: internal
          ipAddressPool: internalapi
          loadBalancerIPs:
          - 172.17.0.80
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
