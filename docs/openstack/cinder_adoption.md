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
          externalEndpoints:
          - endpoint: internal
            ipAddressPool: internalapi
            loadBalancerIPs:
            - 172.17.0.80
        cinderBackup:
          networkAttachments:
          - storage
          replicas: 0 # backend needs to be configured
        cinderVolumes:
          volume1:
            networkAttachments:
            - storage
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
