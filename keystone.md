Keystone adoption procedure
===========================

Prerequisites
-------------

* Service and Endpoints resources that will direct MariaDB connections
  to the external MariaDB running on original controllers exist.

* Define shell variables:

  ```
  ADMIN_PASSWORD=SomePassword
  ```

Pre-checks
----------

Adoption
--------

Currently the adoption is being performed by deploying
OpenStackControlPlane. This may change going forward, to make
OpenstackControlPlane creation a less invasive/risky step.

Post-checks
-----------

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
