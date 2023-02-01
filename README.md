Data Plane Adoption procedure
=============================

Work-in-progress documentation.


## Ceph adoption

If the environment includes Ceph and some of its services are
collocated on the Controller hosts ("internal Ceph"), then Ceph
services need to be moved out of Controller hosts as the last
step of the OpenStack adoption.
Follow this documentation:

* [Ceph cluster migration (RBD)](ceph.md)


## OpenStack adoption

This is a procedure for adopting an OpenStack cloud.

Perform the actions from the sub-documents in the following order:

* [Deploy podified backend services](backend_services_deployment.md)

* [Copy MariaDB data](mariadb_copy.md)

* [Deploy OpenStack control plane services](openstack_control_plane_deployment.md)

* [Glance Adoption](glance_adoption.md)

If you face issues during adoption, check the
[Troubleshooting](troubleshooting.md) document for common problems and
solutions.
