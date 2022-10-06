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

### Temporary hacks

To make the adoption procedure possible currently, hacks need to be
applied - custom Keystone operator and MariaDB operator need to be
deployed with the following patches that are not intened to be merged
upstream:

* Disabling of DB sync. This can be removed once Podified Control
  Plane starts using Zed content.
  [https://github.com/jistr/openstack-k8s-keystone-operator/commit/abb0a9f169405cbfd0d1cf5b8343aa55429e5e3f](https://github.com/jistr/openstack-k8s-keystone-operator/commit/abb0a9f169405cbfd0d1cf5b8343aa55429e5e3f)

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
