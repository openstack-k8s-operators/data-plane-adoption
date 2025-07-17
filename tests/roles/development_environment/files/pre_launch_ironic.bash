set -o pipefail

alias openstack="$OPENSTACK_COMMAND"

INSTANCE_NAME="test-baremetal"
FLAVOR_NAME="baremetal"
IMAGE_NAME="CentOS-Stream-GenericCloud-x86_64-9"
IMAGE_FILE="CentOS-Stream-GenericCloud-x86_64-9-latest.x86_64.qcow2"
IMAGE_URL="https://cloud.centos.org/centos/9-stream/x86_64/images"
NETWORK_NAME="provisioning"

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
  set -e
}

function wait_image_active() {
  local image_name=$1
  local retries=100
  local counter=0
  set +e
  until ! ${BASH_ALIASES[openstack]} image show "${image_name}" -f value -c status | grep -P "^(?!active).*$"; do
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

function cleanup_resources() {
  echo "=== Starting cleanup of existing resources ==="

  # Clean up instance
  echo "Checking for existing ${INSTANCE_NAME} instance..."
  if ${BASH_ALIASES[openstack]} server show ${INSTANCE_NAME} &>/dev/null; then
    echo "Deleting existing ${INSTANCE_NAME} instance..."
    ${BASH_ALIASES[openstack]} server delete ${INSTANCE_NAME} --wait || true
    echo "Instance deleted."
  else
    echo "No ${INSTANCE_NAME} instance found."
  fi
  
  : <<'END_COMMENT'
  # Clean up nodes
  echo "Checking for existing nodes..."
  local existing_nodes=$(${BASH_ALIASES[openstack]} baremetal node list -c UUID -f value 2>/dev/null || true)
  if [[ -n "$existing_nodes" ]]; then
    echo "Found existing nodes. Deleting them..."
    for node in $existing_nodes; do
      local current_state=$(${BASH_ALIASES[openstack]} baremetal node show $node -c provision_state -f value 2>/dev/null || echo "unknown")
      echo "Deleting node $node (current state: $current_state)..."

      if [[ "$current_state" == "active" ]]; then
        echo "Node is active, attempting to delete directly..."
      fi

      ${BASH_ALIASES[openstack]} baremetal node delete $node || true
    done
    echo "Waiting for all nodes to be fully deleted..."
    
    # Wait for all nodes to be completely removed
    local retries=30
    local counter=0
    while [[ $counter -lt $retries ]]; do
      local remaining_nodes=$(${BASH_ALIASES[openstack]} baremetal node list -c UUID -f value 2>/dev/null || true)
      if [[ -z "$remaining_nodes" ]]; then
        echo "All nodes successfully deleted."
        break
      fi
      echo "Still waiting for nodes to be deleted... (attempt $((counter+1))/$retries)"
      sleep 10
      ((counter++))
    done
    
    if [[ $counter -eq $retries ]]; then
      echo "WARNING: Some nodes may still exist after cleanup timeout"
    fi
  else
    echo "No existing nodes found."
  fi

  # Clean up image
  echo "Checking for existing ${IMAGE_NAME} image..."
  local existing_images=$(${BASH_ALIASES[openstack]} image list --name ${IMAGE_NAME} -f value -c ID 2>/dev/null || true)
  if [[ -n "$existing_images" ]]; then
    echo "Deleting existing ${IMAGE_NAME} image(s)..."
    for image_id in $existing_images; do
      echo "Deleting image ID: $image_id"
      ${BASH_ALIASES[openstack]} image delete $image_id || true
    done
    echo "Image(s) deleted."
  else
    echo "No ${IMAGE_NAME} image found."
  fi

END_COMMENT

  # Clean up flavor
  echo "Checking for existing ${FLAVOR_NAME} flavor..."
  if ${BASH_ALIASES[openstack]} flavor show ${FLAVOR_NAME} &>/dev/null; then
    echo "Deleting existing ${FLAVOR_NAME} flavor..."
    ${BASH_ALIASES[openstack]} flavor delete ${FLAVOR_NAME} || true
    echo "Flavor deleted."
  else
    echo "No ${FLAVOR_NAME} flavor found."
  fi

  echo "=== Cleanup completed ==="
  echo ""
}

# Cleanup first
cleanup_resources

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
${OPENSTACK_COMMAND} flavor create ${FLAVOR_NAME} --ram 1024 --vcpus 1 --disk 15 \
--property resources:VCPU=0 \
--property resources:MEMORY_MB=0 \
--property resources:DISK_GB=0 \
--property resources:CUSTOM_BAREMETAL=1 \
--property capabilities:boot_mode=uefi

# Create image
if ! ${BASH_ALIASES[openstack]} image show ${IMAGE_NAME} &>/dev/null; then
  echo "Creating ${IMAGE_NAME} image..."
  IMG=${IMAGE_FILE}
  URL=${IMAGE_URL}/$IMG
  curl --silent --show-error -o /tmp/${IMG} -L $URL
  DISK_FORMAT=$(qemu-img info /tmp/${IMG} | grep "file format:" | awk '{print $NF}')
  ${BASH_ALIASES[openstack]} image create \
    --container-format bare \
    --disk-format ${DISK_FORMAT} \
    --property hw_firmware_type=uefi \
    --property hw_machine_type=q35 \
    ${IMAGE_NAME} < /tmp/${IMG}
  wait_image_active ${IMAGE_NAME}
else
  echo "Image '${IMAGE_NAME}' already exists. Skipping creation."
fi


export BAREMETAL_NODES=$(${BASH_ALIASES[openstack]} baremetal node list -c UUID -f value)

# Check if we have any nodes to work with
if [[ -z "$BAREMETAL_NODES" ]]; then
  echo "ERROR: No baremetal nodes found after enrollment."
  echo "Current ENROLL_BMAAS_IRONIC_NODES setting: ${ENROLL_BMAAS_IRONIC_NODES}"
  
  if [[ "${ENROLL_BMAAS_IRONIC_NODES,,}" == "true" ]]; then
    echo "Node enrollment was enabled but no nodes were created."
    echo "Please check if the node enrollment process completed successfully."
    echo "Check the output above for any enrollment errors."
  fi
  exit 1
fi

echo "Found baremetal nodes: $BAREMETAL_NODES"

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
${BASH_ALIASES[openstack]} server show ${INSTANCE_NAME} || {
    ${BASH_ALIASES[openstack]} server create ${INSTANCE_NAME} --flavor ${FLAVOR_NAME} --image ${IMAGE_NAME} --nic net-id=${NETWORK_NAME} --wait
}

# Wait for node to boot
sleep 60

# Check instance status and network connectivity
${BASH_ALIASES[openstack]} server show ${INSTANCE_NAME}
ping -c 4 $(${BASH_ALIASES[openstack]} server show ${INSTANCE_NAME} -f json -c addresses | jq -r .addresses.${NETWORK_NAME}[0])

