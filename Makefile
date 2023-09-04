TEST_INVENTORY ?= tests/inventory.yaml
TEST_VARS ?= tests/vars.yaml
TEST_SECRETS ?= tests/secrets.yaml
TEST_CONFIG ?= tests/ansible.cfg

test-minimal: TEST_OUTFILE := tests/logs/test_minimal_out_$(shell date +%FT%T%Z).log
test-minimal:
	mkdir -p tests/logs
	ANSIBLE_CONFIG=$(TEST_CONFIG) ansible-playbook -v -i $(TEST_INVENTORY) -e @$(TEST_VARS) -e @$(TEST_SECRETS) tests/playbooks/test_minimal.yaml 2>&1 | tee $(TEST_OUTFILE)

test-with-ceph: TEST_OUTFILE := tests/logs/test_with_ceph_out_$(shell date +%FT%T%Z).log
test-with-ceph:
	mkdir -p tests/logs
	ANSIBLE_CONFIG=$(TEST_CONFIG) ansible-playbook -v -i $(TEST_INVENTORY) -e @$(TEST_VARS) -e @$(TEST_SECRETS) tests/playbooks/test_with_ceph.yaml 2>&1 | tee $(TEST_OUTFILE)
