# Info for AI agents about data-plane-adoption repository

## Overview

This repository contains the documentation and automated tests for a procedure called "Adoption" or "Data Plane Adoption". The adoption is a semi-in-place upgrade from Red Hat OpenStack Platform 17.1 (RHOSP 17.1, OSP 17.1) to Red Hat OpenStack Services on OpenShift (RHOSO 18).

High level overview of the adoption procedure:

- Start with a source OSP 17.1 cloud.
- Stop control plane services (disables cloud management but workloads keep functioning intact).
- Copy MariaDB and OVN databases from the source cloud to new DB services started in OpenShift pods (the first piece of the new RHOSO 18 cloud).
- Deploy a new RHOSO 18 OpenStack control plane in OpenShift pods (backed by the new DBs with copied data).
- Upgrade the services on the data plane from OSP 17.1 to RHOSO 18. The new RHOSO 18 services are configured to talk to the new RHOSO 18 control plane. (The data plane is typically mainly composed of Nova Compute hosts but other host types are possible.)
- If the old OSP 17.1 controller hosts are now unused (depending on service configuration), they can be decomissioned or re-purposed.

The docs source can render into two documentation site outputs. The first is for the typical use case: OSP 17.1 clouds managed by OSP Director (upstream name TripleO). The second is for OSP 17.1 clouds managed by OSP Director Operator (OSPDO). The procedures are very similar at the high level but to ensure streamlined docs for each use case, we make separate renders.

There are other adjacent procedures described or linked in the repo that are optional or based on the service configuration of the cloud. These include:

- Migration of Ceph monitor services from OSP 17.1 controller hosts.
- Migration of Swift data from OSP 17.1 controller hosts.
- Upgrade of data plane hosts from RHEL 9.2 to a newer RHEL release (after adoption).

## Tech stack

- `make` commands are the usual entry point for rendering docs and running tests.
- Docs are written in AsciiDoctor format.
- Tests are written in Ansible.
- OSP 17.1 control plane and data plane runs on RHEL 9.2 with services in Podman containers.
- RHOSO 18 data plane also runs on RHEL 9.2 during adoption with services in Podman containers.
- RHOSO 18 control plane runs in OpenShift pods.

## Conventions

- There should be parity between the docs and the tests. There may be some legitimate minor differences to account for CI specifics, but in general the intent of the tests is to verify the procedure and the commands from the docs.
- Tests use the `shell` Ansible module liberally, we do not strive for "beautiful Ansible that just uses Python modules". Using `shell` tends to allow verbatim correspondence of tests to the commands/snippets in the docs, which is more important than having beautiful Ansible code.
- Docs must support multiple variants (upstream/downstream/OSPDO). Do not hardcode product names like "Red Hat OpenStack Services on OpenShift". Use the AsciiDoctor attributes defined in `docs_user/adoption-attributes.adoc` (e.g. `{rhos_long}`, `{OpenStackShort}`).

## Important

- When amending the procedure/commands in docs, try to make matching changes to the tests, and vice versa. Ask to be provided with the context for this as needed. Do not test something different from what is being documented. If you suspect your edit may break docs-tests parity, alert the user prominently. At the explicit request of the user you may break the docs-tests parity, but don't make that decision on your own.
- If you come across a pre-existing meaningful difference between the docs and the tests that makes completing your task difficult or impossible, alert the user instead of completing your task, and ask for further guidance.

## Repository map

- `docs_build` - Generated content. Do not read or edit files in this directory as a source of truth. Always use `docs_user` or `docs_dev`.
  - `docs_build/adoption-dev/index-upstream.html` - Rendered developer documentation.
  - `docs_build/adoption-user/index-{upstream,downstream,downstream-ospdo}.html` - Rendered user documentation (the adoption procedure).
- `docs_dev` - Sources for developer documentation.
- `docs_user` - Sources for user documentation (the adoption procedure).
  - `main.adoc` is the root.
  - `*-attributes.adoc` files distinguish upstream and downstream variants.
  - `assemblies` are higher-level building blocks.
  - `modules` are lower-level building blocks.
- `docs_user` - Sources for user documentation (the adoption procedure).
- `Makefile` - The main Makefile for docs building and running tests. For docs it calls nested `make` using `docs_dev/Makefile` and `docs_user/Makefile`.
- `scenarios` - Configuration of  CI jobs doing end-to-end testing.
- `tests` - Ansible test suite utilized in the end-to-end tests.
  - `vars.sample.yaml,secrets.sample.yaml` - Example files with variables and secrets that are typically customized before running end-to-end tests.
  - `roles` - Roles implementing parts of the test suite. These roughly map to sections in the adoption documentation.
- `zuul.d` - Settings for which upstream CI jobs to run on this repo. The jobs themselves are defined in a different repo.

## Building docs

`make docs` is the easiest way to build both user docs in all variants and developer docs.

More detailed info is in `docs_dev/assemblies/documentation.adoc`.

## Running tests

Running end-to-end tests is complex, it involves setting up an Adoption dev/test environment, configuring the test suite for that environment with `vars.yaml` and `secrets.yaml`, and launching one of the test make targets, e.g. `make test-minimal`.

More detailed info is in:

- `docs_dev/assemblies/development_environment.adoc`
- `docs_dev/assemblies/tests.adoc`
