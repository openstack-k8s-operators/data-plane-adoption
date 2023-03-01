TEST_INVENTORY ?= tests/inventory.sample-crc-vagrant.yaml
TEST_VARS ?= tests/vars.sample.yaml
TEST_SECRETS ?= tests/secrets.sample.yaml
TEST_OUTFILE := tests/test_minimal_out_$(shell date +%FT%T%Z).log

test-minimal:
	ANSIBLE_CONFIG=tests/ansible.cfg ansible-playbook -v -i $(TEST_INVENTORY) -e @$(TEST_VARS) -e @$(TEST_SECRETS) tests/playbooks/test_minimal.yaml | tee $(TEST_OUTFILE)
