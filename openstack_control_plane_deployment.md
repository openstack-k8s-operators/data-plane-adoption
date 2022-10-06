OpenStackControlPlane deployment
================================

First we create OpenStackControlPlane CR with

Here we create a Service resource inside OpenShift that will direct
MariaDB connections to the external MariaDB running on controllers.

Prerequisites
-------------

* Define shell variables:

  ```
  # The IP of MariaDB running on controller machines. Must be reachable
  # and connectable on port 3306 from OpenShift pods.
  EXTERNAL_MARIADB_IP=192.168.24.3

  # MariaDB root password on the original deployment.
  DB_ROOT_PASSWORD=SomePassword
  ADMIN_PASSWORD=SomePassword
  KEYSTONE_DATABASE_PASSWORD=SomePassword
  ```

Pre-checks
----------

Adoption
--------

* Create OSP secret.

  ```
  # in install_yamls
  make input
  ```

* Set passwords to match the original deployment:

  ```
  oc set data secret/osp-secret "DbRootPassword=$DB_ROOT_PASSWORD"
  oc set data secret/osp-secret "AdminPassword=$ADMIN_PASSWORD"
  oc set data secret/osp-secret "KeystoneDatabasePassword=$KEYSTONE_DATABASE_PASSWORD"
  ```

* Deploy OpenStackControlPlane. Note the following configuration specifics:

  * MariaDB template contains an `adoptionRedirect` definition.

  ```
  oc apply -f - <<EOF
  apiVersion: core.openstack.org/v1beta1
  kind: OpenStackControlPlane
  metadata:
    name: openstack
  spec:
    secret: osp-secret
    storageClass: local-storage
    keystoneTemplate:
      containerImage: quay.io/tripleotraincentos8/centos-binary-keystone:current-tripleo
      databaseInstance: openstack
    mariadbTemplate:
      adoptionRedirect:
        host: $EXTERNAL_MARIADB_IP
      containerImage: quay.io/tripleotraincentos8/centos-binary-mariadb:current-tripleo
      storageRequest: 500M
    rabbitmqTemplate:
      replicas: 1
    placementTemplate:
      containerImage: quay.io/tripleotraincentos8/centos-binary-placement-api:current-tripleo
  EOF
  ```

  > Currently this step attempts to do DB syncs and deploy all OpenStack
  > services. This may change going forward, to make OpenstackControlPlane
  > creation a less invasive/risky step.


Post-checks
-----------
