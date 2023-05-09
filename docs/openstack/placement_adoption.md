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
      template:
        containerImage: quay.io/podified-antelope-centos9/openstack-placement-api:current-podified
        databaseInstance: openstack
        secret: osp-secret
  '
  ```

## Post-checks

* See that Placement endpoints are defined and pointing to the
  podified FQDNs and that Placement API responds.

  ```
  export OS_CLIENT_CONFIG_FILE=clouds-adopted.yaml
  export OS_CLOUD=adopted

  openstack endpoint list | grep placement


  # Without OpenStack CLI placement plugin installed:
  PLACEMENT_PUBLIC_URL=$(openstack endpoint list -c 'Service Name' -c 'Service Type' -c URL | grep placement | grep public | awk '{ print $6; }')
  curl "$PLACEMENT_PUBLIC_URL"

  # With OpenStack CLI placement plugin installed:
  openstack resource class list
  ```
