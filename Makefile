TEST_INVENTORY ?= tests/inventory.yaml

test-minimal:
	ANSIBLE_CONFIG=tests/ansible.cfg ansible-playbook -v -i $(TEST_INVENTORY) tests/playbooks/test_minimal.yaml
