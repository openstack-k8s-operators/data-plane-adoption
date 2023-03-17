Data Plane Adoption procedure
=============================

## OpenStack adoption

This is a procedure for adopting an OpenStack cloud.

Perform the actions from the sub-documents in the following order:

* [Deploy podified backend services](openstack/backend_services_deployment.md)

* [Copy MariaDB data](openstack/mariadb_copy.md)

* [OVN adoption](openstack/ovn_adoption.md)

* [Keystone adoption](openstack/keystone_adoption.md)

* [Glance adoption](openstack/glance_adoption.md)

* [Placement adoption](openstack/placement_adoption.md)

* [Adoption of other services](openstack/other_services_adoption.md)

If you face issues during adoption, check the
[Troubleshooting](openstack/troubleshooting.md) document for common
problems and solutions.

## Post-OpenStack Ceph adoption

If the environment includes Ceph and some of its services are
collocated on the Controller hosts ("internal Ceph"), then Ceph
services need to be moved out of Controller hosts as the last step of
the OpenStack adoption. Follow this documentation:

* [Ceph RBD migration](ceph/ceph_rbd.md)
* [Ceph RGW migration](ceph/ceph_rgw.md)

-----

# Contributing

For information about contributing to the docs and how to run tests,
see:

* [Contributing to documentation](contributing/documentation.md) -
  how to build docs locally, docs patterns and tips.

* [Tests](contributing/tests.md) -
  information about the test suite and how to run it.
