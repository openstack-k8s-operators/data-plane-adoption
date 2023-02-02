# OpenStack control plane services deployment

## Prerequisites

* Previous Adoption steps completed. Notably, the service databases
  must already be imported into the podified MariaDB.

## Variables

(There are no shell variables necessary currently.)

## Pre-checks

## Procedure - OpenStack control plane services deployment

* Patch OpenStackControlPlane to deploy Keystone:

  ```
  oc patch openstackcontrolplane openstack --type=merge --patch '
  spec:
    keystone:
      enabled: true
      template:
        secret: osp-secret
        containerImage: quay.io/tripleozedcentos9/openstack-keystone:current-tripleo
        databaseInstance: openstack
  '
  ```

* Create a clouds.yaml file to talk to adopted Keystone:

  ```
  cat > clouds-adopted.yaml <<EOF
  clouds:
    adopted:
      auth:
        auth_url: http://keystone-public-openstack.apps-crc.testing
        password: $ADMIN_PASSWORD
        project_domain_name: Default
        project_name: admin
        user_domain_name: Default
        username: admin
      cacert: ''
      identity_api_version: '3'
      region_name: regionOne
      volume_api_version: '3'
  EOF
  ```

* Clean up old endpoints that still point to old control plane
  (everything except Keystone endpoints):

  ```
  export OS_CLIENT_CONFIG_FILE=clouds-adopted.yaml
  export OS_CLOUD=adopted

  openstack endpoint list | grep ' cinderv3 ' | awk '{ print $2; }' | xargs openstack endpoint delete
  openstack endpoint list | grep ' glance ' | awk '{ print $2; }' | xargs openstack endpoint delete
  openstack endpoint list | grep ' neutron ' | awk '{ print $2; }' | xargs openstack endpoint delete
  openstack endpoint list | grep ' nova ' | awk '{ print $2; }' | xargs openstack endpoint delete
  openstack endpoint list | grep ' placement ' | awk '{ print $2; }' | xargs openstack endpoint delete
  openstack endpoint list | grep ' swift ' | awk '{ print $2; }' | xargs openstack endpoint delete
  ```

* Deploy the rest of control plane services:

  ```
  oc patch openstackcontrolplane openstack --type=merge --patch '
  spec:
    # cinder:
    #   enabled: true
    #   template:
    #     cinderAPI:
    #       replicas: 1
    #       containerImage: quay.io/tripleozedcentos9/openstack-cinder-api:current-tripleo
    #     cinderScheduler:
    #       replicas: 1
    #       containerImage: quay.io/tripleozedcentos9/openstack-cinder-scheduler:current-tripleo
    #     cinderBackup:
    #       replicas: 1
    #       containerImage: quay.io/tripleozedcentos9/openstack-cinder-backup:current-tripleo
    #     cinderVolumes:
    #       volume1:
    #         containerImage: quay.io/tripleozedcentos9/openstack-cinder-volume:current-tripleo
    #         replicas: 1

    glance:
      enabled: true
      template:
        databaseInstance: openstack
        containerImage: quay.io/tripleozedcentos9/openstack-glance-api:current-tripleo
        storageClass: ""
        storageRequest: 10G
        glanceAPIInternal:
          containerImage: quay.io/tripleozedcentos9/openstack-glance-api:current-tripleo
        glanceAPIExternal:
          containerImage: quay.io/tripleozedcentos9/openstack-glance-api:current-tripleo

    placement:
      enabled: true
      template:
        containerImage: quay.io/tripleozedcentos9/openstack-placement-api:current-tripleo
        databaseInstance: openstack
        secret: osp-secret

    ovn:
      enabled: true
      template:
        ovnDBCluster:
          ovndbcluster-nb:
            replicas: 1
            containerImage: quay.io/tripleozedcentos9/openstack-ovn-nb-db-server:current-tripleo
            dbType: NB
            storageRequest: 10G
          ovndbcluster-sb:
            replicas: 1
            containerImage: quay.io/tripleozedcentos9/openstack-ovn-sb-db-server:current-tripleo
            dbType: SB
            storageRequest: 10G
        ovnNorthd:
          replicas: 1
          containerImage: quay.io/tripleozedcentos9/openstack-ovn-northd:current-tripleo

    ovs:
      enabled: true
      template:
        ovsContainerImage: "quay.io/skaplons/ovs:latest"
        ovnContainerImage: "quay.io/tripleozedcentos9/openstack-ovn-controller:current-tripleo"
        external-ids:
          system-id: "random"
          ovn-bridge: "br-int"
          ovn-encap-type: "geneve"

    neutron:
      enabled: true
      template:
        databaseInstance: openstack
        containerImage: quay.io/tripleozedcentos9/openstack-neutron-server:current-tripleo
        secret: osp-secret

    # nova:
    #   enabled: true
    #   template:
    #     secret: osp-secret
  '
  ```


## Post-checks

* See that endpoints are defined:

  ```
  export OS_CLIENT_CONFIG_FILE=clouds-adopted.yaml
  export OS_CLOUD=adopted

  openstack endpoint list
  ```
