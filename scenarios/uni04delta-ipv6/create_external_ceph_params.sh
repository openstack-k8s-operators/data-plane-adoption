#!/bin/bash
# Create external_ceph_params.yaml on undercloud

set -e  # Exit on any error

echo "Creating external Ceph parameters file..."

# Extract Ceph credentials
echo "Fetching Ceph credentials from osp-ext-ceph-uni04delta-ipv6-0..."
CEPH_OUTPUT=$(ssh osp-ext-ceph-uni04delta-ipv6-0 cat /etc/ceph/ceph.conf /etc/ceph/ceph.client.openstack.keyring)

FSID=$(echo "$CEPH_OUTPUT" | grep "fsid =" | awk '{print $3}')
KEY=$(echo "$CEPH_OUTPUT" | grep "key =" | awk '{print $3}' | tr -d '"')

if [ -z "$FSID" ] || [ -z "$KEY" ]; then
    echo "ERROR: Failed to extract FSID or KEY from Ceph configuration"
    exit 1
fi

echo "Found FSID: $FSID"
echo "Found Key: $KEY"

# Create the parameter file on undercloud
echo "Creating ~/external_ceph_params.yaml on osp-undercloud-0..."
ssh osp-undercloud-0 "cat > ~/external_ceph_params.yaml" <<EOC
parameter_defaults:
  CephClusterFSID: '$FSID'
  CephClientKey: '$KEY'
  CephManilaClientKey: '$KEY'
  CephExternalMonHost: '2620:cf:cf:cccc::6a,2620:cf:cf:cccc::6b,2620:cf:cf:cccc::6c'
EOC

echo "Successfully created ~/external_ceph_params.yaml on osp-undercloud-0"
echo ""
echo "File contents:"
ssh osp-undercloud-0 "cat ~/external_ceph_params.yaml"

# Below code copies the ceph admin keyring and conf files that are required for adoption pre-requisites

echo "Copying Ceph configuration files from osp-ext-ceph-uni04delta-ipv6-0 to osp-controller-0..."

echo "Creating directory on controller..."
ssh osp-controller-0 mkdir -p $HOME/ceph_client

ssh osp-ext-ceph-uni04delta-ipv6-0 sudo cat /etc/ceph/ceph.conf | ssh osp-controller-0 "cat > $HOME/ceph_client/ceph.conf"
ssh osp-ext-ceph-uni04delta-ipv6-0 sudo cat /etc/ceph/ceph.client.admin.keyring | ssh osp-controller-0 "cat > $HOME/ceph_client/ceph.client.admin.keyring"

echo " Done! Files copied to osp-controller-0:$HOME/ceph_client/"
