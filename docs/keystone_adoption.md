# Keystone adoption

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

## Post-checks

* See that Keystone endpoints are defined and pointing to the podified
  FQDNs:

  ```
  export OS_CLIENT_CONFIG_FILE=clouds-adopted.yaml
  export OS_CLOUD=adopted

  openstack endpoint list | grep keystone
  ```
