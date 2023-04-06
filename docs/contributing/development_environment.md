Development environment
=======================

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

## Deployment of Ceph

```
HOSTNETWORK=false NETWORKS_ANNOTATION=\'[\{\"name\":\"storage\",\"namespace\":\"openstack\"\}]\' MON_IP=172.18.0.30 make ceph TIMEOUT=90
```

## Deployment of 17.1 Standalone with network isolation

Instructions for OSP 17.1 Standalone deployment with network isolation
are TBD, for now you can use the TripleO Wallaby Standalone without
network isolation as documented in the [original dev setup
repo](https://gitlab.cee.redhat.com/rhos-upgrades/data-plane-adoption-dev/-/tree/main/crc-and-vagrant).

That will mean you can only adopt the OpenStack without utilizing the
isolated networks.

## Cleanup of the environment

```
cd install_yamls/devsetup
make crc_cleanup
```
