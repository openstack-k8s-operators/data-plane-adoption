set -euxo pipefail

alias openstack="$OPENSTACK_COMMAND"

function wait_node_state() {
  local target_state=$1
  local nodes=$2
  local retries=120
  local counter=0
  set +e

  until true; do
    local all_in_state=true
    for node in $nodes; do
      local current_state=$(${BASH_ALIASES[openstack]} baremetal node show $node -c provision_state -f value)
      if [[ "$current_state" != "$target_state" ]]; then
        all_in_state=false
        break
      fi
    done

    if [[ "$all_in_state" == "true" ]]; then
      break
    fi

    if [[ "$counter" -eq "$retries" ]]; then
      echo "ERROR: Timeout. Nodes did not reach provisioning state: ${target_state}"
      exit 1
    fi

    echo "Waiting for nodes to reach provisioning state: ${target_state}"
    sleep 10
    ((counter++))
  done

  set -euxo pipefail
}

# Manage nodes
if [[ "${IRONIC_POST_ADOPTION_MANAGE_NODES,,}" == "true" ]]; then
  echo "Managing baremetal nodes..."

  # Get list of nodes that are not in active state
  BAREMETAL_NODES=$(${BASH_ALIASES[openstack]} baremetal node list -c UUID -c "Provisioning State" -f value | awk '$2 != "active" {print $1}')

  # Manage nodes
  for node in $BAREMETAL_NODES; do
    ${BASH_ALIASES[openstack]} baremetal node manage $node
  done

  # Allow time for state transitions to begin
  sleep 10

  # Wait for nodes to reach manageable state
  wait_node_state "manageable" "$BAREMETAL_NODES"

  echo "Nodes successfully managed"
fi

# Inspect baremetal nodes
if [[ "${IRONIC_POST_ADOPTION_INSPECT_NODES,,}" == "true" ]]; then
  echo "Inspecting baremetal nodes..."

  # Get list of nodes in manageable state
  BAREMETAL_NODES=$(${BASH_ALIASES[openstack]} baremetal node list -c UUID -c "Provisioning State" -f value | awk '$2 == "manageable" {print $1}')

  # Inspect nodes
  for node in $BAREMETAL_NODES; do
    ${BASH_ALIASES[openstack]} baremetal node inspect $node
    sleep 10
  done

  # Allow time for inspection to begin
  sleep 10

  # Wait for nodes to reach manageable state (after inspection)
  wait_node_state "manageable" "$BAREMETAL_NODES"

  echo "Nodes successfully inspected"
fi

# Provide nodes
if [[ "${IRONIC_POST_ADOPTION_PROVIDE_NODES,,}" == "true" ]]; then
  echo "Providing baremetal nodes..."

  # Get list of nodes in manageable state
  BAREMETAL_NODES=$(${BASH_ALIASES[openstack]} baremetal node list -c UUID -c "Provisioning State" -f value | awk '$2 == "manageable" {print $1}')

  # Provide nodes
  for node in $BAREMETAL_NODES; do
    ${BASH_ALIASES[openstack]} baremetal node provide $node
    sleep 10
  done

  # Allow time for cleaning to begin
  sleep 10

  # Wait for nodes to reach available state
  wait_node_state "available" "$BAREMETAL_NODES"

  echo "Nodes successfully provided"
fi
