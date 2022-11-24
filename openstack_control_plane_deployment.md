OpenStackControlPlane deployment
================================

The following instructions create OpenStackControlPlane CR with
MariaDB and RabbitMQ with adoption redirects in place. This will be
the foundation of the adopted podified control plane to which we will
be gradually adding services in later steps.

> Note: Currently MariaDB with redirection is implemented. Service
> subset deployment and RabbitMQ redirection are TBD.

Prerequisites
-------------

* Define shell variables. The following values are just illustrative,
  use values which are correct for your environment:

  ```
  # The IP of MariaDB running on controller machines. Must be reachable
  # and connectable on port 3306 from OpenShift pods.
  EXTERNAL_MARIADB_IP=192.168.24.3

  # MariaDB root password on the original deployment.
  DB_ROOT_PASSWORD=SomePassword
  ADMIN_PASSWORD=SomePassword
  KEYSTONE_DATABASE_PASSWORD=SomePassword
  ```

* The `openstack-operator` deployed, but `OpenStackControlPlane`
  **not** deployed.

  For developer/CI environments, the openstack operator can be deployed
  by running `make openstack` inside
  [install_yamls](https://github.com/openstack-k8s-operators/install_yamls)
  repo.

  For production environments, the deployment method will likely be
  different.

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
    (RabbitMQ templateshould contain a similar definition when it is
    implemented.)

  * All services except MariaDB and RabbitMQ have `enabled: false`.

  ```
  oc apply -f - <<EOF
  apiVersion: core.openstack.org/v1beta1
  kind: OpenStackControlPlane
  metadata:
    name: openstack
  spec:
    secret: osp-secret
    storageClass: local-storage
    mariadb:
      template:
        adoptionRedirect:
          host: $EXTERNAL_MARIADB_IP
        containerImage: quay.io/tripleowallabycentos9/openstack-mariadb:current-tripleo
        storageRequest: 500M
    rabbitmq:
      template:
        replicas: 1

    keystone:
      enabled: false
    cinder:
      enabled: false
    glance:
      enabled: false
    placement:
      enabled: false

  EOF
  ```

Post-checks
-----------
