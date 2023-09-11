Development environment
=======================

-----

*This is a guide for an install_yamls based Adoption environment with
network isolation as an alternative to the
[CRC and Vagrant TripleO Standalone](https://gitlab.cee.redhat.com/rhos-upgrades/data-plane-adoption-dev/-/tree/main/crc-and-vagrant)
development environment guide.*

-----

The Adoption development environment utilizes
[install_yamls](https://github.com/openstack-k8s-operators/install_yamls)
for CRC VM creation and for creation of the VM that hosts the original
Wallaby OpenStack in Standalone configuration.

## Environment prep

Get install_yamls:

```
git clone https://github.com/openstack-k8s-operators/install_yamls.git
```

Install tools for operator development:

```
cd install_yamls/devsetup
make download_tools
```

## Deployment of CRC with network isolation


```
cd install_yamls/devsetup
PULL_SECRET=$HOME/pull-secret.txt CPUS=12 MEMORY=40000 DISK=100 make crc

eval $(crc oc-env)
oc login -u kubeadmin -p 12345678 https://api.crc.testing:6443

make crc_attach_default_interface

cd ..  # back to install_yamls
make crc_storage
make input
make openstack
```
Use the [install_yamls devsetup](https://github.com/openstack-k8s-operators/install_yamls/tree/main/devsetup)
to create a virtual machine connected to the isolated networks.

Create the edpm-compute-0 virtual machine.
```
cd install_yamls/devsetup
make standalone
```

### Convenience steps

To make our life easier we can copy the deployment passwords we'll be using
in the [backend services deployment phase of the data plane adoption](
https://openstack-k8s-operators.github.io/data-plane-adoption/openstack/backend_services_deployment/).

```
scp -i ~/install_yamls/out/edpm/ansibleee-ssh-key-id_rsa root@192.168.122.100:/root/tripleo-standalone-passwords.yaml ~/
```

If we want to be able to easily run `openstack` commands from the host without
actually installing the package and copying the configuration file from the VM
we can create a simple alias:

```
alias openstack="ssh -i ~/install_yamls/out/edpm/ansibleee-ssh-key-id_rsa root@192.168.122.100 OS_CLOUD=standalone openstack"
```

### Route networks

Route VLAN20 to have access to the MariaDB cluster:

```
EDPM_BRIDGE=$(sudo virsh dumpxml edpm-compute-0 | grep -oP "(?<=bridge=').*(?=')")
sudo ip link add link $EDPM_BRIDGE name vlan20 type vlan id 20
sudo ip addr add dev vlan20 172.17.0.222/24
sudo ip link set up dev vlan20
```

### Snapshot/revert

When the deployment of the Standalone OpenStack is finished, it's a
good time to snapshot the machine, so that multiple Adoption attempts
can be done without having to deploy from scratch.

```
cd install_yamls/devsetup
make standalone_snapshot
```

And when you wish to revert the Standalone deployment to the
snapshotted state:

```
cd install_yamls/devsetup
make standalone_revert
```

Similar snapshot could be done for the CRC virtual machine, but the
developer environment reset on CRC side can be done sufficiently via
the install_yamls `*_cleanup` targets. This is further detailed in
the section:
[Reset the environment to pre-adoption state](https://openstack-k8s-operators.github.io/data-plane-adoption/contributing/development_environment/#reset-the-environment-to-pre-adoption-state)

### Create a workload to adopt

```
export OS_CLOUD=standalone
source ~/install_yamls/devsetup/scripts/edpm-deploy-instance.sh
```
Confirm the image UUID can be seen in Ceph's images pool.
```
sudo cephadm shell -- rbd -p images ls -l
```

Create a Cinder volume, a backup from it, and snapshot it.
```
openstack volume create --image cirros --bootable --size 1 disk
openstack volume backup create --name backup disk
openstack volume snapshot create --volume disk snapshot
```

Add volume to the test VM
```
openstack server add volume test disk
```

## Performing the Data Plane Adoption

The development environment is now set up, you can go to the [Adoption
documentation](https://openstack-k8s-operators.github.io/data-plane-adoption/)
and perform adoption manually, or run the [test
suite](https://openstack-k8s-operators.github.io/data-plane-adoption/contributing/tests/)
against your environment.

## Reset the environment to pre-adoption state

The development environment must be rolled back in case we want to execute another Adoption run.

Delete the data-plane and control-plane resources from the CRC vm
```
oc delete osdp openstack
oc delete oscp openstack
```

Revert the standalone vm to the snapshotted state

```
cd install_yamls/devsetup
make standalone_revert
```
Clean up and initialize the storage PVs in CRC vm
```
cd ..
make crc_storage_cleanup
make crc_storage
```

## Experimenting with an additional compute node

The following is not on the critical path of preparing the development
environment for Adoption, but it shows how to make the environment
work with an additional compute node VM.

The remaining steps should be completed on the hypervisor hosting crc
and edpm-compute-0.

### Deploy NG Control Plane with Ceph

Export the Ceph configuration from edpm-compute-0 into a secret.
```
SSH=$(ssh -i ~/install_yamls/out/edpm/ansibleee-ssh-key-id_rsa root@192.168.122.100)
KEY=$($SSH "cat /etc/ceph/ceph.client.openstack.keyring | base64 -w 0")
CONF=$($SSH "cat /etc/ceph/ceph.conf | base64 -w 0")

cat <<EOF > ceph_secret.yaml
apiVersion: v1
data:
  ceph.client.openstack.keyring: $KEY
  ceph.conf: $CONF
kind: Secret
metadata:
  name: ceph-conf-files
  namespace: openstack
type: Opaque
EOF

oc create -f ceph_secret.yaml
```
Deploy the NG control plane with Ceph as backend for Glance and
Cinder. As described in
[the install_yamls README](https://github.com/openstack-k8s-operators/install_yamls/tree/main),
use the sample config located at
[https://github.com/openstack-k8s-operators/openstack-operator/blob/main/config/samples/core_v1beta1_openstackcontrolplane_network_isolation_ceph.yaml](https://github.com/openstack-k8s-operators/openstack-operator/blob/main/config/samples/core_v1beta1_openstackcontrolplane_network_isolation_ceph.yaml)
but make sure to replace the `_FSID_` in the sample with the one from
the secret created in the previous step.
```
curl -o /tmp/core_v1beta1_openstackcontrolplane_network_isolation_ceph.yaml https://raw.githubusercontent.com/openstack-k8s-operators/openstack-operator/main/config/samples/core_v1beta1_openstackcontrolplane_network_isolation_ceph.yaml
FSID=$(oc get secret ceph-conf-files -o json | jq -r '.data."ceph.conf"' | base64 -d | grep fsid | sed -e 's/fsid = //') && echo $FSID
sed -i "s/_FSID_/${FSID}/" /tmp/core_v1beta1_openstackcontrolplane_network_isolation_ceph.yaml
oc apply -f /tmp/core_v1beta1_openstackcontrolplane_network_isolation_ceph.yaml
```

A NG control plane which uses the same Ceph backend should now be
functional. If you create a test image on the NG system to confirm
it works from the configuration above, be sure to read the warning
in the next section.

Before beginning adoption testing or development you may wish to
deploy an EDPM node as described in the following section.

### Warning about two OpenStacks and one Ceph

Though workloads can be created in the NG deployment to test, be
careful not to confuse them with workloads from the Wallaby cluster
to be migrated. The following scenario is now possible.

A Glance image exists on the Wallaby OpenStack to be adopted.
```
[stack@standalone standalone]$ export OS_CLOUD=standalone
[stack@standalone standalone]$ openstack image list
+--------------------------------------+--------+--------+
| ID                                   | Name   | Status |
+--------------------------------------+--------+--------+
| 33a43519-a960-4cd0-a593-eca56ee553aa | cirros | active |
+--------------------------------------+--------+--------+
[stack@standalone standalone]$
```
If you now create an image with the NG cluster, then a Glance image
will exsit on the NG OpenStack which will adopt the workloads of the
wallaby.
```
[fultonj@hamfast ng]$ export OS_CLOUD=default
[fultonj@hamfast ng]$ export OS_PASSWORD=12345678
[fultonj@hamfast ng]$ openstack image list
+--------------------------------------+--------+--------+
| ID                                   | Name   | Status |
+--------------------------------------+--------+--------+
| 4ebccb29-193b-4d52-9ffd-034d440e073c | cirros | active |
+--------------------------------------+--------+--------+
[fultonj@hamfast ng]$
```
Both Glance images are stored in the same Ceph pool.
```
[stack@standalone standalone]$ sudo cephadm shell -- rbd -p images ls -l
Inferring fsid 7133115f-7751-5c2f-88bd-fbff2f140791
Using recent ceph image quay.rdoproject.org/tripleowallabycentos9/daemon@sha256:aa259dd2439dfaa60b27c9ebb4fb310cdf1e8e62aa7467df350baf22c5d992d8
NAME                                       SIZE     PARENT  FMT  PROT  LOCK
33a43519-a960-4cd0-a593-eca56ee553aa         273 B            2
33a43519-a960-4cd0-a593-eca56ee553aa@snap    273 B            2  yes
4ebccb29-193b-4d52-9ffd-034d440e073c       112 MiB            2
4ebccb29-193b-4d52-9ffd-034d440e073c@snap  112 MiB            2  yes
[stack@standalone standalone]$
```
However, as far as each Glance service is concerned each has one
image. Thus, in order to avoid confusion during adoption the test
Glance image on the NG OpenStack should be deleted.
```
openstack image delete 4ebccb29-193b-4d52-9ffd-034d440e073c
```
Connecting the NG OpenStack to the existing Ceph cluster is part of
the adoption procedure so that the data migration can be minimized
but understand the implications of the above example.

### Deploy edpm-compute-1

edpm-compute-0 is not available as a standard EDPM system to be
managed by [edpm-ansible](https://openstack-k8s-operators.github.io/edpm-ansible)
or
[dataplane-operator](https://openstack-k8s-operators.github.io/dataplane-operator)
because it hosts the wallaby deployment which will be adopted
and after adoption it will only host the Ceph server.

Use the [install_yamls devsetup](https://github.com/openstack-k8s-operators/install_yamls/tree/main/devsetup)
to create additional virtual machines and be sure
that the `EDPM_COMPUTE_SUFFIX` is set to `1` or greater.
Do not set `EDPM_COMPUTE_SUFFIX` to `0` or you could delete
the Wallaby system created in the previous section.

When deploying EDPM nodes add an `extraMounts` like the following in
the `OpenStackDataPlaneNodeSet` CR `nodeTemplate` so that they will be
configured to use the same Ceph cluster.

```
    edpm-compute:
      nodeTemplate:
        extraMounts:
        - extraVolType: Ceph
          volumes:
          - name: ceph
            secret:
              secretName: ceph-conf-files
          mounts:
          - name: ceph
            mountPath: "/etc/ceph"
            readOnly: true
```

A NG data plane which uses the same Ceph backend should now be
functional. Be careful about not confusing new workloads to test the
NG OpenStack with the Wallaby OpenStack as described in the previous
section.

### Begin Adoption Testing or Development

We should now have:

- An NG glance service based on Antelope running on CRC
- An TripleO-deployed glance serviced running on edpm-compute-0
- Both services have the same Ceph backend
- Each service has their own independent database

An environment above is assumed to be available in the
[Glance Adoption documentation](https://openstack-k8s-operators.github.io/data-plane-adoption/openstack/glance_adoption). You
may now follow other Data Plane Adoption procedures described in the
[documentation](https://openstack-k8s-operators.github.io/data-plane-adoption).
The same pattern can be applied to other services.
