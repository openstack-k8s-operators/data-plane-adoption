# OSPdO adoptinon

Currently this is staticly set up for two BMs one with vv one with OSPdO

## Envs setup:

CRC :

  git clone https://github.com/openstack-k8s-operators/install_yamls.git
  export PULL_SECRET=./pull-secret.txt
  export KUBEADMIN_PWD=12345678
  cd install_yamls/devsetup
  make download_tools
  export PULL_SECRET=~/pull-secret.txt
  export KUBEADMIN_PWD=12345678
  CPUS=12 MEMORY=25600 DISK=100 make crc
  cd ../
  eval $(crc oc-env)
  oc login -u kubeadmin -p 12345678 https://api.crc.testing:6443
  make crc_storage
  make mariadb MARIADB_IMG=quay.io/openstack-k8s-operators/mariadb-operator-index:latest
  make mariadb_deploy
  make keystone
  make keystone_deploy
  make rabbitmq
  make rabbitmq_deploy
  make openstack

OSPdO:
    Any OSPdO deployment from CI.