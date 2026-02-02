set -euxo pipefail

alias openstack="$OPENSTACK_COMMAND"

function wait_node_state() {
  local node_state=$1
  local retries=120
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
  set -euxo pipefail
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
  set -euxo pipefail
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
${BASH_ALIASES[openstack]} flavor delete baremetal || true
${BASH_ALIASES[openstack]} flavor create baremetal --ram 1024 --vcpus 1 --disk 15 \
  --property resources:VCPU=0 \
  --property resources:MEMORY_MB=0 \
  --property resources:DISK_GB=0 \
  --property resources:CUSTOM_BAREMETAL=1 \
  --property capabilities:boot_mode="uefi"

# Create image
IMG=CentOS-Stream-GenericCloud-x86_64-9-latest.x86_64.qcow2
URL=https://cloud.centos.org/centos/9-stream/x86_64/images/$IMG
curl --silent --show-error -o /tmp/${IMG} -L $URL
DISK_FORMAT=$(qemu-img info /tmp/${IMG} | grep "file format:" | awk '{print $NF}')
${BASH_ALIASES[openstack]} image delete CentOS-Stream-GenericCloud-x86_64-9 || true
${BASH_ALIASES[openstack]} image create \
  --container-format bare \
  --disk-format ${DISK_FORMAT} \
  --property hw_firmware_type=uefi \
  --property hw_machine_type=q35 \
  CentOS-Stream-GenericCloud-x86_64-9 < /tmp/${IMG}
wait_image_active CentOS-Stream-GenericCloud-x86_64-9


export BAREMETAL_NODES=$(${BASH_ALIASES[openstack]} baremetal node list -c UUID -f value)

# Check if any nodes are active (in use by instances)
ACTIVE_NODES=$(${BASH_ALIASES[openstack]} baremetal node list -c "Provisioning State" -f value | grep -c "active" || true)

if [ "$ACTIVE_NODES" -eq 0 ]; then
  echo "No active nodes found, proceeding with node management operations"

  # Manage nodes
  if [[ "${PRE_LAUNCH_IRONIC_MANAGE_NODES,,}" != "false" ]]; then
    for node in $BAREMETAL_NODES; do
      ${BASH_ALIASES[openstack]} baremetal node manage $node
    done
    wait_node_state "manageable"

    # Inspect baremetal nodes
    if [[ "${PRE_LAUNCH_IRONIC_INSPECT_NODES,,}" != "false" ]]; then
      for node in $BAREMETAL_NODES; do
        ${BASH_ALIASES[openstack]} baremetal node inspect $node
        sleep 10
      done
      wait_node_state "manageable"
    else
      echo "Skipping inspect nodes (PRE_LAUNCH_IRONIC_INSPECT_NODES=false)"
    fi

    # Provide nodes
    if [[ "${PRE_LAUNCH_IRONIC_PROVIDE_NODES,,}" != "false" ]]; then
      for node in $BAREMETAL_NODES; do
        ${BASH_ALIASES[openstack]} baremetal node provide $node
        sleep 10
      done
      wait_node_state "available"
    else
      echo "Skipping provide nodes (PRE_LAUNCH_IRONIC_PROVIDE_NODES=false)"
    fi
  else
    echo "Skipping all node management operations (PRE_LAUNCH_IRONIC_MANAGE_NODES=false)"
    echo "Note: Inspect and Provide steps require nodes to be in manageable state first"
  fi
else
  echo "Found $ACTIVE_NODES active node(s), skipping node management operations"
fi

# Create test instance on baremetal
if [[ "${PRE_LAUNCH_IRONIC_CREATE_INSTANCE,,}" != "false" ]]; then
  # Wait for nova to be aware of the node
  sleep 60

  # Create an instance on baremetal
  ${BASH_ALIASES[openstack]} server show test-baremetal || {
      ${BASH_ALIASES[openstack]} server create test-baremetal --flavor baremetal --image CentOS-Stream-GenericCloud-x86_64-9 --nic net-id=provisioning --wait
  }

  # Wait for node to boot
  sleep 60

  # Check instance status and network connectivity
  ${BASH_ALIASES[openstack]} server show test-baremetal
  ping -c 4 $(${BASH_ALIASES[openstack]} server show test-baremetal -f json -c addresses | jq -r .addresses.provisioning[0])
else
  echo "Skipping test instance creation (PRE_LAUNCH_IRONIC_CREATE_INSTANCE=false)"
fi
