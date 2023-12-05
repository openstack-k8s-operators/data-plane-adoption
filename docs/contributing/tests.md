Tests
=====

## Test suite information

The adoption docs repository also includes a test suite for Adoption.
There are targets in the Makefile which can be used to execute the
test suite:

* `test-minimal` - a minimal test scenario, the eventual set of
  services in this scenario should be the "core" services needed to
  launch a VM. This scenario assumes local storage backend for
  services like Glance and Cinder.

* `test-with-ceph` - like 'minimal' but with Ceph storage backend for
  Glance and Cinder.


## Configuring the test suite

* Create `tests/vars.yaml` and `tests/secrets.yaml` by copying the
  included samples (`tests/vars.sample.yaml`,
  `tests/secrets.sample.yaml`).

* Walk through the `tests/vars.yaml` and `tests/secrets.yaml` files
  and see if you need to edit any values. If you are using the
  documented development environment, majority of the defaults should
  work out of the box. The comments in the YAML files will guide you
  regarding the expected values. You may want to double check that
  these variables suit your environment:

  * `install_yamls_path`

  * `tripleo_passwords`

  * `controller*_ssh`

  * `edpm_privatekey_path`

  * `timesync_ntp_servers`


## Running the tests

The interface between the execution infrastructure and the test suite
is an Ansible inventory and variables files. Inventory and variable
samples are provided. To run the tests, follow this procedure:

* Install dependencies and create a venv:

  ```
  sudo dnf -y install python-devel
  pip install --user openstackclient osc_placement jmespath
  ansible-galaxy collection install community.general
  ```

* (on Centos9 Stream) Apply `jmespath` workarounds for ansible-core 2.15 and ansible 8.5:
  ```
  pip install --user ansible yq
  sudo su
  pip3.11 # answer yes to all to get python3.11 and pip3.11
  pip3.11 install --user jmespath
  yq '.' tests/vars.yaml |\
    jq '.ansible_python_interpreter="/bin/python3.11"' |\
    python -c "import json, yaml, sys; print(yaml.dump(json.load(sys.stdin)))" \
    > tests/vars_.yaml
	cp tests/vars_.yaml tests/vars.yaml
  ```

* Run `make test-with-ceph` (the documented development environment
  does include Ceph).

  If you are using Ceph-less environment, you should run `make
  test-minimal`.

## Making patches to the test suite

Please be aware of the following when changing the test suite:

* The test suite should follow the docs as much as possible.

  The purpose of the test suite is to verify what the user would run
  if they were following the docs. We don't want to loosely rewrite
  the docs into Ansible code following Ansible best practices. We want
  to test the exact same bash commands/snippets that are written in
  the docs. This often means that we should be using the `shell`
  module and do a verbatim copy/paste from docs, instead of using the
  best Ansible module for the task at hand.
