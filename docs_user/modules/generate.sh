#!/bin/bash

set -euxo pipefail

bundle exec kramdoc -o openstack-autoscaling_adoption.adoc ../../docs/openstack/autoscaling_adoption.md
bundle exec kramdoc -o openstack-backend_services_deployment.adoc ../../docs/openstack/backend_services_deployment.md
bundle exec kramdoc -o openstack-ceph_backend_configuration.adoc ../../docs/openstack/ceph_backend_configuration.md
bundle exec kramdoc -o openstack-cinder_adoption.adoc ../../docs/openstack/cinder_adoption.md
bundle exec kramdoc -o openstack-edpm_adoption.adoc ../../docs/openstack/edpm_adoption.md
bundle exec kramdoc -o openstack-glance_adoption.adoc ../../docs/openstack/glance_adoption.md
bundle exec kramdoc -o openstack-heat_adoption.adoc ../../docs/openstack/heat_adoption.md
bundle exec kramdoc -o openstack-horizon_adoption.adoc ../../docs/openstack/horizon_adoption.md
bundle exec kramdoc -o openstack-ironic_adoption.adoc ../../docs/openstack/ironic_adoption.md
bundle exec kramdoc -o openstack-keystone_adoption.adoc ../../docs/openstack/keystone_adoption.md
bundle exec kramdoc -o openstack-manila_adoption.adoc ../../docs/openstack/manila_adoption.md
bundle exec kramdoc -o openstack-mariadb_copy.adoc ../../docs/openstack/mariadb_copy.md
bundle exec kramdoc -o openstack-neutron_adoption.adoc ../../docs/openstack/neutron_adoption.md
bundle exec kramdoc -o openstack-node-selector.adoc ../../docs/openstack/node-selector.md
bundle exec kramdoc -o openstack-nova_adoption.adoc ../../docs/openstack/nova_adoption.md
bundle exec kramdoc -o openstack-ovn_adoption.adoc ../../docs/openstack/ovn_adoption.md
bundle exec kramdoc -o openstack-placement_adoption.adoc ../../docs/openstack/placement_adoption.md
bundle exec kramdoc -o openstack-planning.adoc ../../docs/openstack/planning.md
bundle exec kramdoc -o openstack-pull_openstack_configuration.adoc ../../docs/openstack/pull_openstack_configuration.md
bundle exec kramdoc -o openstack-stop_openstack_services.adoc ../../docs/openstack/stop_openstack_services.md
bundle exec kramdoc -o openstack-telemetry_adoption.adoc ../../docs/openstack/telemetry_adoption.md
bundle exec kramdoc -o openstack-troubleshooting.adoc ../../docs/openstack/troubleshooting.md

# bundle exec kramdoc -o ceph-rbd_migration.adoc ../../docs/ceph/ceph_rbd.md
# bundle exec kramdoc -o ceph-rgw_migration.adoc ../../docs/ceph/ceph_rgw.md
