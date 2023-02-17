TEST_INVENTORY ?= tests/inventory.yaml
TEST_VARS ?= tests/vars.yaml
TEST_SECRETS ?= tests/secrets.yaml

test-minimal:
	ANSIBLE_CONFIG=tests/ansible.cfg ansible-playbook -v -i $(TEST_INVENTORY) -e @$(TEST_VARS) -e @$(TEST_SECRETS) tests/playbooks/test_minimal.yaml
