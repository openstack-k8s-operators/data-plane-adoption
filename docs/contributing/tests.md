Tests
=====

## Test suite information

The adoption docs repository also includes a test suite for Adoption.
Currently, only one test target is defined:

* `minimal` - a minimal test scenario, the eventual set of services in
  this scenario should be the "core" services needed to launch a VM
  (without Ceph, to keep environment size requirements small and make
  it easy to set up).

We can add more scenarios as we go (e.g. one that includes Ceph).


## Running the tests

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


## Running tests on systems where /bin/sh is not /bin/bash

ansible.builtin.command and ansible.builtin.shell use /bin/sh by default.
for portability reason when using either command or shell modules you should
not assume /bin/sh is bash and assume it is simply a posix compliant shell

In this repo that requirement is relax for the ansible.builtin.shell
module as we configure module_defaults

```
  module_defaults:
    ansible.builtin.shell:
      executable: /bin/bash
```

module_defaults are configure per playbook play so if you are adding a new
play or playbook you will need to copy this to ensure compatibility

note the command module always uses /bin/sh so we should avoid bash specific
syntax when using command or just use the shell module instead.
