# Placement adoption

## Prerequisites

* Previous Adoption steps completed. Notably, the service databases
  must already be imported into the podified MariaDB.

## Variables

(There are no shell variables necessary currently.)

## Procedure - Placement adoption

* Patch OpenStackControlPlane to deploy Placement:

  ```
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

  ```
  alias openstack="oc exec -t openstackclient -- openstack"

  openstack endpoint list | grep placement


  # Without OpenStack CLI placement plugin installed:
  PLACEMENT_PUBLIC_URL=$(openstack endpoint list -c 'Service Name' -c 'Service Type' -c URL | grep placement | grep public | awk '{ print $6; }')
  curl "$PLACEMENT_PUBLIC_URL"

  # With OpenStack CLI placement plugin installed:
  openstack resource class list
  ```
