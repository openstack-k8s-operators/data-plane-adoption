Data Plane Adoption procedure
=============================

Work-in-progress documentation.


## Ceph adoption

If the environment includes Ceph and some of its services are
collocated on the Controller hosts ("internal Ceph"), then Ceph
services need to be moved out of Controller hosts before starting
OpenStack adoption. Follow this documentation:

* [Ceph cluster migration](ceph.md)


## OpenStack adoption

First deploy a minimal podified control plane:

* [OpenStackControlPlane deployment](openstack_control_plane_deployment.md)

Then perform the individual services adoption procedures in the
following order:

* [Keystone adoption](keystone.md)

* [MariaDB adoption](mariadb.md)

If you face issues during adoption, check the
[Troubleshooting](troubleshooting.md) document for common problems and
solutions.
