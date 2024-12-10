set -e

alias openstack="$OPENSTACK_COMMAND"

function wait_node_state() {
  local node_state=$1
  local retries=50
  local counter=0
  set +e
  until ! ${BASH_ALIASES[openstack]} baremetal node list -f value -c "Provisioning\ State" | grep -P "^(?!${node_state}).*$"; do
    if [[ "$counter" -eq "$retries" ]]; then
      echo "ERROR: Timeout. Nodes did not reach provisioning state: ${node_state}"
      exit 1
    fi
    echo "Waiting for nodes to reach provisioning state: ${node_state}"
    sleep 10
    ((counter++))
  done
  set -e
}

function wait_image_active() {
  local image_name=$1
  local retries=100
  local counter=0
  set +e
  until ! ${BASH_ALIASES[openstack]} image show  Fedora-Cloud-Base-38 -f value -c status | grep -P "^(?!active).*$"; do
    if [[ "$counter" -eq "$retries" ]]; then
      echo "ERROR: Timeout. Image: ${image_name} did not reach state: active"
      exit 1
    fi
    echo "Waiting for image \"${image_name}\" to reach state \"active\""
    sleep 10
    ((counter++))
  done
  set -e
}


# If the snapshot was reverted, and time is way off we get SSL issues in agent<->ironic connection
# Workaround by restarting chronyd.service
if [[ "${PRE_LAUNCH_IRONIC_RESTART_CHRONY,,}" != "false" ]]; then
  ssh -i $EDPM_PRIVATEKEY_PATH root@192.168.122.100 systemctl restart chronyd.service
  ssh -i $EDPM_PRIVATEKEY_PATH root@192.168.122.100 chronyc -a makestep
fi

# Enroll baremetal nodes
if [[ "${ENROLL_BMAAS_IRONIC_NODES,,}" != "false" ]]; then
  pushd ${INSTALL_YAMLS_PATH}/devsetup
  make --silent bmaas_generate_nodes_yaml | tail -n +2 | tee /tmp/ironic_nodes.yaml
  popd

  scp -i $EDPM_PRIVATEKEY_PATH /tmp/ironic_nodes.yaml root@192.168.122.100:/root/ironic_nodes.yaml
  ssh -i $EDPM_PRIVATEKEY_PATH root@192.168.122.100 OS_CLOUD=standalone openstack baremetal create /root/ironic_nodes.yaml
fi

export IRONIC_PYTHON_AGENT_RAMDISK_ID=$(${BASH_ALIASES[openstack]} image show deploy-ramdisk -c id -f value)
export IRONIC_PYTHON_AGENT_KERNEL_ID=$(${BASH_ALIASES[openstack]} image show deploy-kernel -c id -f value)
for node in $(${BASH_ALIASES[openstack]} baremetal node list -c UUID -f value); do
  ${BASH_ALIASES[openstack]} baremetal node set $node \
    --driver-info deploy_ramdisk=${IRONIC_PYTHON_AGENT_RAMDISK_ID} \
    --driver-info deploy_kernel=${IRONIC_PYTHON_AGENT_KERNEL_ID} \
    --resource-class baremetal \
    --property capabilities='boot_mode:uefi'
done

# Create a baremetal flavor
${BASH_ALIASES[openstack]} flavor create baremetal --ram 1024 --vcpus 1 --disk 15 \
  --property resources:VCPU=0 \
  --property resources:MEMORY_MB=0 \
  --property resources:DISK_GB=0 \
  --property resources:CUSTOM_BAREMETAL=1 \
  --property capabilities:boot_mode="uefi"

# Create image
IMG=Fedora-Cloud-Base-38-1.6.x86_64.qcow2
URL=https://download.fedoraproject.org/pub/fedora/linux/releases/38/Cloud/x86_64/images/$IMG
curl --silent --show-error -o /tmp/${IMG} -L $URL
DISK_FORMAT=$(qemu-img info /tmp/${IMG} | grep "file format:" | awk '{print $NF}')
${BASH_ALIASES[openstack]} image create --container-format bare --disk-format ${DISK_FORMAT} Fedora-Cloud-Base-38 < /tmp/${IMG}
wait_image_active Fedora-Cloud-Base-38


export BAREMETAL_NODES=$(${BASH_ALIASES[openstack]} baremetal node list -c UUID -f value)
# Manage nodes
for node in $BAREMETAL_NODES; do
  ${BASH_ALIASES[openstack]} baremetal node manage $node
done
wait_node_state "manageable"

# Inspect baremetal nodes
for node in $BAREMETAL_NODES; do
  ${BASH_ALIASES[openstack]} baremetal node inspect $node
  sleep 10
done
wait_node_state "manageable"

# Provide nodes
for node in $BAREMETAL_NODES; do
  ${BASH_ALIASES[openstack]} baremetal node provide $node
  sleep 10
done
wait_node_state "available"

# Wait for nova to be aware of the node
sleep 60

# Create an instance on baremetal
${BASH_ALIASES[openstack]} server show baremetal-test || {
    ${BASH_ALIASES[openstack]} server create baremetal-test --flavor baremetal --image Fedora-Cloud-Base-38 --nic net-id=provisioning --wait
}

# Wait for node to boot
sleep 60

# Check instance status and network connectivity
${BASH_ALIASES[openstack]} server show baremetal-test
ping -c 4 $(${BASH_ALIASES[openstack]} server show baremetal-test -f json -c addresses | jq -r .addresses.provisioning[0])
