# Data Plane Adoption

## Procedure documentation

Navigate to the
[documentation site](https://openstack-k8s-operators.github.io/data-plane-adoption).


### Rendering documentation locally

Install docs build requirements into virtualenv:

```
python3 -m venv local/docs-venv
source local/docs-venv/bin/activate
pip install -r docs/doc_requirements.txt
```

Serve docs site on localhost:

```
mkdocs serve
```

Click the link it outputs. As you save changes to files modified in your editor,
the browser will automatically show the new content.


## Procedure test suite

This repository also includes a test suite for Adoption. Currently
only one test target is defined:

* `minimal` - a minimal test scenario, the eventual set of services in
  this scenario should be the "core" services needed to launch a VM
  (without Ceph, to keep environment size requirements small and make
  it easy to set up).

We can add more scenarios as we go (e.g. one that includes Ceph).


### Running the tests

The interface between the execution infrastructure and the test suite
is an Ansible inventory and variables files. Inventory and variable
samples are provided. To run the tests, follow this procedure:

* Create `tests/inventory.yaml` file by copying and editing one of the
  included samples (e.g. `tests/inventory.sample-crc-vagrant.yaml`) to
  provide values valid in your environment.

* Create `tests/vars.yaml` and `tests/secrets.yaml`, likewise by
  copying and editing the included samples (`tests/vars.sample.yaml`,
  `tests/secrets.sample.yaml`).

* Run `make test-minimal`.
