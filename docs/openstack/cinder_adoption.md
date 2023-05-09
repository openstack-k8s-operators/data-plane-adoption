# Cinder adoption

## Prerequisites

* Previous Adoption steps completed. Notably, the service databases
  must already be imported into the podified MariaDB.

## Variables

(There are no shell variables necessary currently.)

## Pre-checks

## Procedure - Cinder adoption

* Patch OpenStackControlPlane to deploy Cinder:

  ```
  oc patch openstackcontrolplane openstack --type=merge --patch '
  spec:
    cinder:
      enabled: true
      template:
        databaseInstance: openstack
        secret: osp-secret
        cinderAPI:
          replicas: 1
          containerImage: quay.io/tripleozedcentos9/openstack-cinder-api:current-tripleo
        cinderScheduler:
          replicas: 1
          containerImage: quay.io/tripleozedcentos9/openstack-cinder-scheduler:current-tripleo
        cinderBackup:
          replicas: 0 # backend needs to be configured
          containerImage: quay.io/tripleozedcentos9/openstack-cinder-backup:current-tripleo
        cinderVolumes:
          volume1:
            containerImage: quay.io/tripleozedcentos9/openstack-cinder-volume:current-tripleo
            replicas: 0 # backend needs to be configured
  '
  ```

## Post-checks

* See that Cinder endpoints are defined and pointing to the podified
  FQDNs:

  ```
  export OS_CLIENT_CONFIG_FILE=clouds-adopted.yaml
  export OS_CLOUD=adopted

  openstack endpoint list | grep cinder
  openstack volume type list
  ```
