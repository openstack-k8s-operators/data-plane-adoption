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

If you want a less intrusive alternative (Go from RPM rather than
upstream etc.) that allows for basic testing, make sure to at least do
the following:

```
sudo dnf -y install \
    git \
    golang \
    guestfs-tools \
    dbus-x11 \
    libvirt \
    make

go env -w GOPROXY="https://proxy.golang.org,direct"
GO111MODULE=on go install sigs.k8s.io/kustomize/kustomize/v5@latest
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
EDPM_COMPUTE_VCPUS=8 EDPM_COMPUTE_RAM=20 EDPM_COMPUTE_DISK_SIZE=70 make edpm_compute

ssh -i ~/install_yamls/out/edpm/ansibleee-ssh-key-id_rsa root@192.168.122.100
```

## Deployment of Wallaby Standalone with network isolation

The steps in this section should be run on the edpm-compute-0 virtual
machine so that it's configured to host [TripleO Standalone](https://docs.openstack.org/project-deploy-guide/tripleo-docs/latest/deployment/standalone.html)
with Ceph.

Configure the repositories and install the necessary packages.
```
sudo dnf remove -y epel-release
sudo dnf update -y
sudo dnf install -y vim git curl util-linux lvm2 tmux wget
URL=https://trunk.rdoproject.org/centos9/component/tripleo/current/
RPM_NAME=$(curl $URL | grep python3-tripleo-repos | sed -e 's/<[^>]*>//g' | awk 'BEGIN { FS = ".rpm" } ; { print $1 }')
RPM=$RPM_NAME.rpm
sudo dnf install -y $URL$RPM
sudo -E tripleo-repos -b wallaby current-tripleo-dev ceph --stream
sudo dnf repolist
sudo dnf update -y
sudo dnf install -y podman python3-tripleoclient util-linux lvm2 cephadm
```
Set the hostname.
```
sudo hostnamectl set-hostname standalone.localdomain
sudo hostnamectl set-hostname standalone.localdomain --transient
```
Create a containers-prepare-parameters.yaml file.
```
openstack tripleo container image prepare default \
  --output-env-file $HOME/containers-prepare-parameters.yaml
```

### Networking

Use os-net-config to add VLAN interfaces which connect edpm-compute-0
to the isolated networks configured by `install_yamls`.
```
export GATEWAY=192.168.122.1
export CTLPLANE_IP=192.168.122.100
export INTERNAL_IP=$(sed -e 's/192.168.122/172.17.0/' <<<"$CTLPLANE_IP")
export STORAGE_IP=$(sed -e 's/192.168.122/172.18.0/' <<<"$CTLPLANE_IP")
export STORAGE_MGMT_IP=$(sed -e 's/192.168.122/172.20.0/' <<<"$CTLPLANE_IP")
export TENANT_IP=$(sed -e 's/192.168.122/172.19.0/' <<<"$CTLPLANE_IP")
export EXTERNAL_IP=$(sed -e 's/192.168.122/172.21.0/' <<<"$CTLPLANE_IP")

sudo mkdir -p /etc/os-net-config
cat << EOF | sudo tee /etc/os-net-config/config.yaml
network_config:
- type: ovs_bridge
  name: br-ctlplane
  mtu: 1500
  use_dhcp: false
  dns_servers:
  - $GATEWAY
  domain: []
  addresses:
  - ip_netmask: $CTLPLANE_IP/24
  routes:
  - ip_netmask: 0.0.0.0/0
    next_hop: $GATEWAY
  members:
  - type: interface
    name: nic1
    mtu: 1500
    # force the MAC address of the bridge to this interface
    primary: true

  # external
  - type: vlan
    mtu: 1500
    vlan_id: 44
    addresses:
    - ip_netmask: $EXTERNAL_IP/24
    routes: []

  # internal
  - type: vlan
    mtu: 1500
    vlan_id: 20
    addresses:
    - ip_netmask: $INTERNAL_IP/24
    routes: []

  # storage
  - type: vlan
    mtu: 1500
    vlan_id: 21
    addresses:
    - ip_netmask: $STORAGE_IP/24
    routes: []

  # storage_mgmt
  - type: vlan
    mtu: 1500
    vlan_id: 23
    addresses:
    - ip_netmask: $STORAGE_MGMT_IP/24
    routes: []

  # tenant
  - type: vlan
    mtu: 1500
    vlan_id: 22
    addresses:
    - ip_netmask: $TENANT_IP/24
    routes: []
EOF

cat << EOF | sudo tee /etc/cloud/cloud.cfg.d/99-edpm-disable-network-config.cfg
network:
  config: disabled
EOF

sudo systemctl enable network
sudo os-net-config -c /etc/os-net-config/config.yaml
```

The isolated networks from os-net-config config file above will
be lost when `openstack tripleo deploy` is run because the default
os-net-config template only has the Neutron public interface as a member.
To prevent this, copy
[this standalone.j2 template file](development_environment_examples/standalone.j2)
(which retains the VLANs above) into tripleo-ansible's `tripleo_network_config` role.
```
sudo cp standalone.j2 /usr/share/ansible/roles/tripleo_network_config/templates/standalone.j2
```

Assign VIPs to the networks created when os-net-config was run.
The tenant network on vlan22 does not require a VIP.
```
sudo ip addr add 172.17.0.2/32 dev vlan20
sudo ip addr add 172.18.0.2/32 dev vlan21
sudo ip addr add 172.20.0.2/32 dev vlan23
sudo ip addr add 172.21.0.2/32 dev vlan44
```

### NTP Server

Clock synchronization is important for both Ceph and OpenStack services, so
both `ceph deploy` and `tripleo deploy` commands will make use of chrony to
ensure the clock is properly in sync.

We'll use the `NTP_SERVER` environmental variable to define the NTP server to
use.

If we are running alls these commands in a system inside the Red Hat network we
should use the `clock.corp.redhat.com ` server:

```
export NTP_SERVER=clock.corp.redhat.com
```

And when running it from our own systems outside of the Red Hat network we can
use any available server:

```
export NTP_SERVER=pool.ntp.org
```

### Ceph

These steps are based on [TripleO Standalone](https://docs.openstack.org/project-deploy-guide/tripleo-docs/latest/deployment/standalone.html)
to configure Ceph on the Standalone node to simulate an HCI or
internal Ceph adoption. Ceph will be configured to use the Storage
network (vlan21) and Storage Management network (vlan23). The storage
management network, is not configured by default in an NG environment
and does not need to be accessed by the NG environment as it is only
used by Ceph (AKA the `cluster_network`) to make OSD replicas and NG
will not be deploying Ceph. Post adoption this network will remain
isolated and the Ceph cluster may be considered external.

Assign the IP from vlan21 to a variable representing the Ceph IP.
```
export CEPH_IP=172.18.0.100
```
Create a block device with logical volumes to be used as an OSD.
```
sudo dd if=/dev/zero of=/var/lib/ceph-osd.img bs=1 count=0 seek=7G
sudo losetup /dev/loop3 /var/lib/ceph-osd.img
sudo pvcreate /dev/loop3
sudo vgcreate vg2 /dev/loop3
sudo lvcreate -n data-lv2 -l +100%FREE vg2
```
Create an OSD spec file which references the block device.
```
cat <<EOF > $HOME/osd_spec.yaml
data_devices:
  paths:
    - /dev/vg2/data-lv2
EOF
```
Use the Ceph IP and OSD spec file to create a Ceph spec file which
will describe the Ceph cluster in a format cephadm can parse.
```
sudo openstack overcloud ceph spec \
   --standalone \
   --mon-ip $CEPH_IP \
   --osd-spec $HOME/osd_spec.yaml \
   --output $HOME/ceph_spec.yaml
```
Create the ceph-admin user by passing the Ceph spec created earlier.
```
sudo openstack overcloud ceph user enable \
   --standalone \
   $HOME/ceph_spec.yaml
```
Though Ceph will be configured to run on a single host via the
--single-host-defaults option, this deployment only has a single OSD so
it cannot replicate data even on the same host. Create an initial Ceph
configuration to disable replication:
```
cat <<EOF > $HOME/initial_ceph.conf
[global]
osd pool default size = 1
[mon]
mon_warn_on_pool_no_redundancy = false
EOF
```
Use the files created in the previous steps to install Ceph. Use
[this network_data.yaml file](development_environment_examples/network_data.yaml)
so that Ceph uses the isolated networks for storage and storage management.

```
sudo openstack overcloud ceph deploy \
     --mon-ip $CEPH_IP \
     --ceph-spec $HOME/ceph_spec.yaml \
     --config $HOME/initial_ceph.conf \
     --standalone \
     --single-host-defaults \
     --skip-hosts-config \
     --skip-container-registry-config \
     --skip-user-create \
     --network-data network_data.yaml \
     --ntp-server $NTP_SERVER \
     --output $HOME/deployed_ceph.yaml
```
Ceph should now be installed. Use `sudo cephadm shell -- ceph -s`
to confirm the Ceph cluster health.

### OpenStack

Use the files created in the previous steps including
[this network_data.yaml file](development_environment_examples/network_data.yaml)
and
[this deployed_network.yaml file](development_environment_examples/deployed_network.yaml).
The deployed_network.yaml file hard codes the IPs and VIPs configured
from the Networking section.

Create standalone_parameters.yaml file and deploy standalone OpenStack
using the following commands.

Remember that should have exported the `NTP_SERVER` environmental variable
earlier in the process.

```
export NEUTRON_INTERFACE=eth0
export CTLPLANE_IP=192.168.122.100
export CTLPLANE_VIP=192.168.122.99
export CIDR=24
export DNS_SERVERS=192.168.122.1
export GATEWAY=192.168.122.1
export BRIDGE="br-ctlplane"

cat <<EOF > standalone_parameters.yaml
parameter_defaults:
  CloudName: $CTLPLANE_IP
  ControlPlaneStaticRoutes:
    - ip_netmask: 0.0.0.0/0
      next_hop: $GATEWAY
      default: true
  Debug: true
  DeploymentUser: $USER
  DnsServers: $DNS_SERVERS
  NtpServer: $NTP_SERVER
  # needed for vip & pacemaker
  KernelIpNonLocalBind: 1
  DockerInsecureRegistryAddress:
  - $CTLPLANE_IP:8787
  NeutronPublicInterface: $NEUTRON_INTERFACE
  # domain name used by the host
  NeutronDnsDomain: localdomain
  # re-use ctlplane bridge for public net
  NeutronBridgeMappings: datacentre:$BRIDGE
  NeutronPhysicalBridge: $BRIDGE
  StandaloneEnableRoutedNetworks: false
  StandaloneHomeDir: $HOME
  InterfaceLocalMtu: 1500
  # Needed if running in a VM
  NovaComputeLibvirtType: qemu
  ValidateGatewaysIcmp: false
  ValidateControllersIcmp: false
EOF

sudo openstack tripleo deploy \
  --templates /usr/share/openstack-tripleo-heat-templates \
  --standalone-role Standalone \
  -e /usr/share/openstack-tripleo-heat-templates/environments/standalone/standalone-tripleo.yaml \
  -e /usr/share/openstack-tripleo-heat-templates/environments/low-memory-usage.yaml \
  -e ~/containers-prepare-parameters.yaml \
  -e standalone_parameters.yaml \
  -e /usr/share/openstack-tripleo-heat-templates/environments/cephadm/cephadm.yaml \
  -e ~/deployed_ceph.yaml \
  -e /usr/share/openstack-tripleo-heat-templates/environments/deployed-network-environment.yaml \
  -e deployed_network.yaml \
  -r /usr/share/openstack-tripleo-heat-templates/roles/Standalone.yaml \
  -n network_data.yaml \
  --local-ip=$CTLPLANE_IP/$CIDR \
  --control-virtual-ip=$CTLPLANE_VIP \
  --output-dir $HOME
```

### Snapshot/revert

When the deployment of the Standalone OpenStack is finished, it's a
good time to snapshot the machine, so that multiple Adoption attempts
can be done without having to deploy from scratch.

```
# Virtiofs share prevents snapshotting, detach it first.
sudo virsh detach-device-alias edpm-compute-0 fs0 --live

sudo virsh snapshot-create-as --atomic --domain edpm-compute-0 --name clean
```

And when you wish to revert the Standalone deployment to the
snapshotted state:

```
sudo virsh snapshot-revert --domain edpm-compute-0 --name clean
```

Similar snapshot could be done for the CRC virtual machine, but the
developer environment reset on CRC side can be done sufficiently via
the install_yamls `*_cleanup` targets.

### Create a workload to adopt

For this example we'll upload a Glance image and confirm it's using
the Ceph cluster. Later you can adopt the Glance image in the NG
deployment.

Download a cirros image and convert it to raw format for Ceph.
```
IMG=cirros-0.5.2-x86_64-disk.img
URL=http://download.cirros-cloud.net/0.5.2/$IMG
RAW=$(echo $IMG | sed s/img/raw/g)
curl -L -# $URL > $IMG
qemu-img convert -f qcow2 -O raw $IMG $RAW
```
Upload the image to Glance.
```
export OS_CLOUD=standalone
openstack image create cirros --disk-format=raw --container-format=bare < $RAW
```
Confirm the image UUID can be seen in Ceph's images pool.
```
sudo cephadm shell -- rbd -p images ls -l
```

## Performing the Data Plane Adoption

The development environment is now set up, you can go to the [Adoption
documentation](https://openstack-k8s-operators.github.io/data-plane-adoption/)
and perform adoption manually, or run the [test
suite](https://openstack-k8s-operators.github.io/data-plane-adoption/contributing/tests/)
against your environment.

----

----

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
the `OpenStackDataPlane` CR `nodeTemplate` so that they will be
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
