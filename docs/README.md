Data Plane Adoption procedure
=============================

## OpenStack adoption

This is a procedure for adopting an OpenStack cloud.

Perform the actions from the sub-documents in the following order:

* [Deploy podified backend services](backend_services_deployment.md)

* [Copy MariaDB data](mariadb_copy.md)

* [Keystone adoption](keystone_adoption.md)

* [Glance adoption](glance_adoption.md)

* [Adoption of other services](other_services_adoption.md)

If you face issues during adoption, check the
[Troubleshooting](troubleshooting.md) document for common problems and
solutions.

## Post-OpenStack Ceph adoption

If the environment includes Ceph and some of its services are
collocated on the Controller hosts ("internal Ceph"), then Ceph
services need to be moved out of Controller hosts as the last step of
the OpenStack adoption. Follow this documentation:

* [Ceph RBD migration](ceph_rbd.md)
* [Ceph RGW migration](ceph_rgw.md)
