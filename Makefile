TEST_INVENTORY ?= tests/inventory.yaml
TEST_VARS ?= tests/vars.yaml
TEST_SECRETS ?= tests/secrets.yaml
TEST_OUTFILE := tests/logs/test_minimal_out_$(shell date +%FT%T%Z).log
TEST_CONFIG ?= tests/ansible.cfg
TEST_EXTRA_ARGS ?=

test-minimal:
	mkdir -p tests/logs
	ANSIBLE_CONFIG=$(TEST_CONFIG) ansible-playbook -v -i $(TEST_INVENTORY) -e @$(TEST_VARS) -e @$(TEST_SECRETS) $(TEST_EXTRA_ARGS) tests/playbooks/test_minimal.yaml 2>&1 | tee $(TEST_OUTFILE)
