TEST_INVENTORY ?= tests/inventory.yaml
TEST_VARS ?= tests/vars.yaml
TEST_CEPH_OVERRIDES ?= tests/ceph_overrides.yaml
TEST_SECRETS ?= tests/secrets.yaml
TEST_CONFIG ?= tests/ansible.cfg
TEST_ARGS ?=

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ TESTS

test-minimal: TEST_OUTFILE := tests/logs/test_minimal_out_$(shell date +%FT%T%Z).log
test-minimal:  ## Launch minimal test suite
	mkdir -p tests/logs
	ANSIBLE_CONFIG=$(TEST_CONFIG) ansible-playbook -v -i $(TEST_INVENTORY) -e @$(TEST_VARS) -e @$(TEST_SECRETS) $(TEST_ARGS) tests/playbooks/test_minimal.yaml 2>&1 | tee $(TEST_OUTFILE)

test-with-ceph: TEST_OUTFILE := tests/logs/test_with_ceph_out_$(shell date +%FT%T%Z).log
test-with-ceph:  ## Launch test suite with ceph
	mkdir -p tests/logs
	ANSIBLE_CONFIG=$(TEST_CONFIG) ansible-playbook -v -i $(TEST_INVENTORY) -e @$(TEST_VARS) -e @$(TEST_SECRETS) $(TEST_ARGS) tests/playbooks/test_with_ceph.yaml 2>&1 | tee $(TEST_OUTFILE)

test-tripleo-requirements: TEST_OUTFILE := tests/logs/test_tripleo_requirements_out_$(shell date +%FT%T%Z).log
test-tripleo-requirements:  ## Launch test suite related to the ceph migration
	mkdir -p tests/logs
	ANSIBLE_CONFIG=$(TEST_CONFIG) ansible-playbook -v -i $(TEST_INVENTORY) -e @$(TEST_VARS) -e @$(TEST_CEPH_OVERRIDES) -e @$(TEST_SECRETS) $(TEST_ARGS) tests/playbooks/test_tripleo_adoption_requirements.yaml 2>&1 | tee $(TEST_OUTFILE)

test-ceph-migration: TEST_OUTFILE := tests/logs/test_ceph_migration_out_$(shell date +%FT%T%Z).log
test-ceph-migration:  ## Launch test suite related to the ceph migration
	mkdir -p tests/logs
	ANSIBLE_CONFIG=$(TEST_CONFIG) ansible-playbook -v -i $(TEST_INVENTORY) -e @$(TEST_VARS) -e @$(TEST_CEPH_OVERRIDES) -e @$(TEST_SECRETS) $(TEST_ARGS) tests/playbooks/test_externalize_ceph.yaml 2>&1 | tee $(TEST_OUTFILE)

test-swift-migration: TEST_OUTFILE := tests/logs/test_swift_migration_out_$(shell date +%FT%T%Z).log
test-swift-migration:
	mkdir -p tests/logs
	ANSIBLE_CONFIG=$(TEST_CONFIG) ansible-playbook -v -i $(TEST_INVENTORY) -e @$(TEST_VARS) -e @$(TEST_SECRETS) $(TEST_ARGS) tests/playbooks/test_swift_migration.yaml 2>&1 | tee $(TEST_OUTFILE)

test-rollback-minimal: TEST_OUTFILE := tests/logs/test_rollback_minimal_out_$(shell date +%FT%T%Z).log
test-rollback-minimal:
	mkdir -p tests/logs
	ANSIBLE_CONFIG=$(TEST_CONFIG) ansible-playbook -v -i $(TEST_INVENTORY) -e @$(TEST_VARS) -e @$(TEST_SECRETS) $(TEST_ARGS) tests/playbooks/test_rollback_minimal.yaml 2>&1 | tee $(TEST_OUTFILE)

test-rollback-with-ceph: TEST_OUTFILE := tests/logs/test_rollback_with_ceph_out_$(shell date +%FT%T%Z).log
test-rollback-with-ceph:
	mkdir -p tests/logs
	ANSIBLE_CONFIG=$(TEST_CONFIG) ansible-playbook -v -i $(TEST_INVENTORY) -e @$(TEST_VARS) -e @$(TEST_SECRETS) $(TEST_ARGS) tests/playbooks/test_rollback_with_ceph.yaml 2>&1 | tee $(TEST_OUTFILE)

test-with-ironic: TEST_OUTFILE := tests/logs/test_with_ironic_out_$(shell date +%FT%T%Z).log
test-with-ironic: ## Launch test suite with Ironic
	mkdir -p tests/logs
	ANSIBLE_CONFIG=$(TEST_CONFIG) ansible-playbook -v -i $(TEST_INVENTORY) -e @$(TEST_VARS) -e @$(TEST_SECRETS) tests/playbooks/test_with_ironic.yaml 2>&1 | tee $(TEST_OUTFILE)

##@ DOCS

docs-dependencies: .bundle

.bundle: ## Attempt to install bundle
	if ! type bundle; then \
		echo "Bundler not found. On Linux run 'sudo dnf install /usr/bin/bundle' to install it."; \
		exit 1; \
	fi

	bundle config set --local path 'local/bundle'; bundle install

docs: docs-dependencies docs-user-all-variants docs-dev ## Build documentation

docs-user-all-variants:
	cd docs_user; BUILD=upstream $(MAKE) html
	cd docs_user; BUILD=downstream $(MAKE) html

docs-user:
	cd docs_user; $(MAKE) html

docs-user-open:
	cd docs_user; $(MAKE) open-html

docs-user-watch:
	cd docs_user; $(MAKE) watch-html

docs-dev:
	cd docs_dev; $(MAKE) html

docs-dev-open:
	cd docs_dev; $(MAKE) open-html

docs-dev-watch:
	cd docs_dev; $(MAKE) watch-html

docs-clean:  ## Cleanup documentation
	rm -r docs_build
