TEST_INVENTORY ?= tests/inventory.yaml
TEST_VARS ?= tests/vars.yaml
TEST_SECRETS ?= tests/secrets_ospdo.yaml
TEST_CONFIG ?= tests/ansible.cfg


### TESTS ###

test-minimal: TEST_OUTFILE := tests/logs/test_minimal_out_$(shell date +%FT%T%Z).log
test-minimal:
	mkdir -p tests/logs
	ANSIBLE_CONFIG=$(TEST_CONFIG) ansible-playbook -v -i $(TEST_INVENTORY) -e @$(TEST_VARS) -e @$(TEST_SECRETS) tests/playbooks/test_minimal.yaml 2>&1 | tee $(TEST_OUTFILE)

test_ospdo: TEST_OUTFILE := tests/logs/test_minimal_out_$(shell date +%FT%T%Z).log
test_ospdo:
	mkdir -p tests/logs
	ANSIBLE_CONFIG=$(TEST_CONFIG) ansible-playbook -v -i $(TEST_INVENTORY) -e @$(TEST_VARS) -e @$(TEST_SECRETS) tests/playbooks/test_minimal_ospdo.yaml 2>&1 | tee $(TEST_OUTFILE)

test-with-ceph: TEST_OUTFILE := tests/logs/test_with_ceph_out_$(shell date +%FT%T%Z).log
test-with-ceph:
	mkdir -p tests/logs
	ANSIBLE_CONFIG=$(TEST_CONFIG) ansible-playbook -v -i $(TEST_INVENTORY) -e @$(TEST_VARS) -e @$(TEST_SECRETS) tests/playbooks/test_with_ceph.yaml 2>&1 | tee $(TEST_OUTFILE)

test-minimal-rhev: TEST_OUTFILE := tests/logs/test_minimal_rhev_out_$(shell date +%FT%T%Z).log
test-minimal-rhev:
	mkdir -p tests/logs
	ANSIBLE_CONFIG=$(TEST_CONFIG) ansible-playbook -v -i $(TEST_INVENTORY) -e @$(TEST_VARS) -e @$(TEST_SECRETS) tests/playbooks/test_minimal_rhev.yaml 2>&1 | tee $(TEST_OUTFILE)


### DOCS ###

## old style docs, to be removed after migration to asciidoc ##
mkdocs:
	if type mkocs &> /dev/null; then \
		MKDOCS="mkdocs"; \
	else \
		MKDOCS="./local/docs-venv/bin/mkdocs"; \
	fi; \
	$$MKDOCS build

mkdocs-dependencies:
	[ -e local/docs-venv ] || python3 -m venv local/docs-venv
	source local/docs-venv/bin/activate && pip install -r docs/doc_requirements.txt


## new-style docs ##

docs-dependencies: .bundle

.bundle:
	if ! type bundle; then \
		echo "Bundler not found. On Linux run 'sudo dnf install /usr/bin/bundle' to install it."; \
		exit 1; \
	fi

	bundle config set --local path 'local/bundle'; bundle install

docs: docs-user docs-dev

docs-user:
	@if type asciidoctor &> /dev/null; then \
		BUNDLE_EXEC=""; \
	else \
		BUNDLE_EXEC="bundle exec"; \
	fi; \
	echo "Running cd docs_user; $$BUNDLE_EXEC $(MAKE) html"; \
	cd docs_user; $$BUNDLE_EXEC $(MAKE) html

docs-dev:
	if type asciidoctor &> /dev/null; then \
		BUNDLE_EXEC=""; \
	else \
		BUNDLE_EXEC="bundle exec"; \
	fi; \
	echo "Running cd docs_dev; $$BUNDLE_EXEC $(MAKE) html"; \
	cd docs_dev; $$BUNDLE_EXEC $(MAKE) html

docs-clean:
	rm -r docs_build
