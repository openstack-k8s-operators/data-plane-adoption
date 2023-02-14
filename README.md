Data Plane Adoption procedure
=============================

Work-in-progress [documentation](https://openstack-k8s-operators.github.io/data-plane-adoption).


Docs Testing
------------

Cross-platform:

```
pip install -r docs/doc_requirements.txt
```

Then:

```
mkdocs serve
```

Click the link it outputs. As you save changes to files modified in your editor,
the browser will automatically show the new content.


# Tests

This repository also includes a test suite for Adoption. Currently
only one test target is defined:

* `minimal` - a minimal test scenario, the eventual set of services in
  this scenario should be the "core" services needed to launch a VM
  (without Ceph, to keep environment size requirements small and make
  it easy to set up).

We can add more scenarios as we go (e.g. one that includes Ceph).

## Executing the tests

The interface between the execution infrastructure and the test suite
is an Ansible inventory file. Inventory samples are provided. To
execute the tests, follow this procedure.

* Create `tests/inventory.yaml` file by copying and editing one of the
  included samples (e.g. `tests/inventory.sample-crc-vagrant.yaml`) to
  provide values valid in your environment.

* Run `make test-minimal`.
