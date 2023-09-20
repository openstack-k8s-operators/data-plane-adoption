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

  * `edpm_chrony_ntp_servers`


## Running the tests

The interface between the execution infrastructure and the test suite
is an Ansible inventory and variables files. Inventory and variable
samples are provided. To run the tests, follow this procedure:

* Install dependencies and create a venv:

  ```
  sudo dnf -y install python-devel
  python3 -m venv venv
  source venv/bin/activate
  pip install openstackclient osc_placement jmespath
  ansible-galaxy collection install community.general
  ```

* Run `make test-with-ceph` (the documented development environment
  does include Ceph).

  If you are using Ceph-less environment, you should run `make
  test-minimal`.
