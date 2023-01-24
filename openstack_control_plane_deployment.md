# OpenStack control plane services deployment

## Prerequisites

* Previous Adoption steps completed. Notably, the service databases
  must already be imported into the podified MariaDB.

## Variables

* Set the desired admin password for the podified deployment. This can
  be the original deployment's admin password or something else.

  ```
  ADMIN_PASSWORD=SomePassword
  ```

## Pre-checks

## Procedure - OpenStack control plane services deployment

* If the `$ADMIN_PASSWORD` is different than the already set password
  in `osp-secret`, amend the `AdminPassword` key in the `osp-secret`
  correspondingly:

  ```
  oc set data secret/osp-secret "AdminPassword=$ADMIN_PASSWORD"
  ```

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

## Post-checks

* Test that `openstack user list` works.

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

  export OS_CLIENT_CONFIG_FILE=clouds-adopted.yaml
  export OS_CLOUD=adopted

  openstack user list
  ```
