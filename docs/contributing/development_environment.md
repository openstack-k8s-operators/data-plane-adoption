Development environment
=======================

-----

*This is a guide for install_yamls based Adoption environment. It is
a work in progress. For now please use the previous
[CRC and Vagrant TripleO Standalone](https://gitlab.cee.redhat.com/rhos-upgrades/data-plane-adoption-dev/-/tree/main/crc-and-vagrant)
development environment guide.*

-----

The Adoption development environment utilizes
[install_yamls](https://github.com/openstack-k8s-operators/install_yamls)
for CRC VM creation and for creation of the VM that hosts the original
OpenStack (currently in Standalone configuration).

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

## Deployment of 17.1 Standalone with network isolation

Instructions for OSP 17.1 Standalone deployment with network isolation
are TBD, for now you can use the TripleO Wallaby Standalone without
network isolation as documented in the [original dev setup
repo](https://gitlab.cee.redhat.com/rhos-upgrades/data-plane-adoption-dev/-/tree/main/crc-and-vagrant).

That will mean you can only adopt the OpenStack without utilizing the
isolated networks.

```
cd install_yamls/devsetup
EDPM_COMPUTE_VCPUS=8 EDPM_COMPUTE_RAM=20 EDPM_COMPUTE_DISK_SIZE=70 make edpm_compute

ssh -i ~/install_yamls/out/edpm/ansibleee-ssh-key-id_rsa root@192.168.122.100
```

In the compute node:

```
export GATEWAY=192.168.122.1
export CTLPLANE_IP=192.168.122.100
export CTLPLANE_VIP=192.168.122.99
export INTERNAL_IP=$(sed -e 's/192.168.122/172.17.0/' <<<"$CTLPLANE_IP")
export STORAGE_IP=$(sed -e 's/192.168.122/172.18.0/' <<<"$CTLPLANE_IP")
export TENANT_IP=$(sed -e 's/192.168.122/172.10.0/' <<<"$CTLPLANE_IP")
export EXTERNAL_IP=$(sed -e 's/192.168.122/172.19.0/' <<<"$CTLPLANE_IP")
export NEUTRON_INTERFACE=vlan44
export NTP_SERVER=clock.corp.redhat.com

sudo hostnamectl set-hostname standalone.localdomain
sudo hostnamectl set-hostname standalone.localdomain --transient

sudo dnf remove -y epel-release
sudo dnf update -y
sudo dnf install -y vim git curl util-linux lvm2 tmux wget
url=https://trunk.rdoproject.org/centos9/component/tripleo/current/
rpm_name=$(curl $url | grep python3-tripleo-repos | sed -e 's/<[^>]*>//g' | awk 'BEGIN { FS = ".rpm" } ; { print $1 }')
rpm=$rpm_name.rpm
sudo dnf install -y $url$rpm
sudo -E tripleo-repos -b wallaby current-tripleo-dev ceph --stream
sudo dnf repolist
sudo dnf update -y
sudo dnf install -y podman python3-tripleoclient

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

cat << EOF > $HOME/standalone_parameters.yaml
parameter_defaults:
  CloudName: $CTLPLANE_IP
  # ControlPlaneStaticRoutes: []
  ControlPlaneStaticRoutes:
    - ip_netmask: 0.0.0.0/0
      next_hop: $GATEWAY
      default: true
  DeploymentUser: $USER
  DnsServers:
    - $GATEWAY
  DockerInsecureRegistryAddress:
    - $CTLPLANE_IP:8787
  NeutronPublicInterface: $NEUTRON_INTERFACE
  NtpServer: $NTP_SERVER
  CloudDomain: localdomain
  NeutronDnsDomain: localdomain
  NeutronBridgeMappings: datacentre:br-ctlplane
  NeutronPhysicalBridge: br-ctlplane
  StandaloneEnableRoutedNetworks: false
  StandaloneHomeDir: $HOME
  InterfaceLocalMtu: 1500
  NovaComputeLibvirtType: qemu
EOF

openstack tripleo container image prepare default \
  --output-env-file $HOME/containers-prepare-parameters.yaml

cat << EOF > $HOME/standalone.sh
set -euxo pipefail

if podman ps | grep keystone; then
    echo "Looks like OpenStack is already deployed, not re-deploying."
    exit 0
fi

sudo openstack tripleo deploy \
  --templates \
  --local-ip=$CTLPLANE_IP/24 \
  --control-virtual-ip=$CTLPLANE_VIP \
  -e /usr/share/openstack-tripleo-heat-templates/environments/standalone/standalone-tripleo.yaml \
  -r /usr/share/openstack-tripleo-heat-templates/roles/Standalone.yaml \
  -e "$HOME/containers-prepare-parameters.yaml" \
  -e "$HOME/standalone_parameters.yaml" \
  -e /usr/share/openstack-tripleo-heat-templates/environments/low-memory-usage.yaml \
  --output-dir $HOME

export OS_CLOUD=standalone
openstack endpoint list
EOF

bash standalone.sh | tee standalone.log
```

## Cleanup of the environment

```
cd install_yamls/devsetup
make crc_cleanup
```
