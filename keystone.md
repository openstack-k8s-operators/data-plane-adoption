Keystone adoption procedure
===========================

Prerequisites
-------------

* Service and Endpoints resources that will direct MariaDB connections
  to the external MariaDB running on original controllers exist.

* Currently we're using
  [install_yamls](https://github.com/openstack-k8s-operators/install_yamls)
  to deploy the Keystone operator and service, this is likely to
  change at some point.

Define shell variables:

```
# The Keystone database and admin user passwords from the original deployment.
KEYSTONE_DATABASE_PASSWORD=SomePassword
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

* MariaDBDatabase that doesn't depend on podified MariaDB (can use
  external DB). This needs to be implemented in a better way.
  [https://github.com/jistr/openstack-k8s-mariadb-operator/commit/aa9421cc10d0a60e20026806a1ef8a0a41388ef4](https://github.com/jistr/openstack-k8s-mariadb-operator/commit/aa9421cc10d0a60e20026806a1ef8a0a41388ef4)

Pre-checks
----------

Adoption
--------

Set Keystone database password:

```
oc set data secret/osp-secret "AdminPassword=$ADMIN_PASSWORD"
oc set data secret/osp-secret "KeystoneDatabasePassword=$KEYSTONE_DATABASE_PASSWORD"
```

Deploy Keystone operator from install_yamls:

```
make keystone KEYSTONE_IMG=quay.io/openstack-k8s-operators/keystone-operator-index:latest
```

Deploy Keystone from install_yamls:

```
make keystone_deploy
```

The operator is waiting for a database to be created. Label the
database CR as adopted, to signal the database is already created and
should just be connected to:

```
oc label mariadbdatabase keystone adopted=true
```

Now Keystone service should get deployed by the operator.

Post-checks
-----------
