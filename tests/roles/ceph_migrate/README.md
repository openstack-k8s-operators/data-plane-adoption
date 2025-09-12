Role Name
=========

The goal of this role is to `externalize` a TripleO deployed Ceph cluster. It is
intended to be run in CI, where a `multinode` TripleO environment with deployed
Ceph exists.
It **does not** migrate OSDs, hence no data movement is involved.
It assumes that both `source` and `target` nodes are part of the Ceph cluster,
and the high level procedure does the following:

1. It loads the information from the existing Ceph cluster (deployed daemons,
   status of the cluster, hostmap, services, monmap, osdmap)
2. It validates the retrieved information (the cluster is healthy and it's in a
   valid state), and fail if one of the defined conditions is not met
3. It starts performing the migration with the following order:
   - Ceph Monitoring Stack
   - Ceph MDS
   - Ceph RGW
   - Ceph MGR
   - Ceph MON
4. It dumps the result of the performed migration

Requirements
------------

In order to be able to run the playbook associated with this role, a `3+3`
topology is at least required (3 Controller, 3 HCI/CephStorage nodes).
If such topology is not available, it's still possible to run the playbook and
perform (as an example) the migration of a single node using tags and passing
overrides.
To migrate only a subset of Mon/Mgr, it is possible to customize the list of
`decomm_nodes` and `target_nodes` passing the following override:

```
decomm_nodes:
  - controller-0
target_nodes:
  - cephstorage-0
```

The list of `decomm_nodes` and `target_nodes` is built through the hostnames of
the nodes that are part of the TripleO inventory.
An alternative method to retrieve such information is to run, from the first
controller, the `cephadm shell -- ceph orch host ls` command, and get the list
of nodes from the gathered hostmap.

Overrides
---------

```yaml
ifeval::["{build}" == "downstream"]
ceph_container_ns: undercloud-0.ctlplane.redhat.local:8787/rh-osbs
ceph_container_image: rhceph
ceph_container_tag: 6-311
endif::[]
ifeval::["{build}" == "upstream"]
ceph_container_ns: quay.io/ceph
ceph_container_image: ceph
ceph_container_tag: v18
ceph_haproxy_container_image: "quay.io/ceph/haproxy:2.3"
ceph_keepalived_container_image: "quay.io/ceph/keepalived:2.1.5"
ceph_alertmanager_container_image: "quay.io/prometheus/alertmanager:v0.25.0"
ceph_grafana_container_image: "quay.io/ceph/ceph-grafana:9.4.7"
ceph_node_exporter_container_image: "quay.io/prometheus/node-exporter:v1.5.0"
ceph_prometheus_container_image: "quay.io/prometheus/prometheus:v2.43.0"
ceph_spec_render_dir: "/home/tripleo-admin"
endif::[]

ceph_rgw_virtual_ips_list:
  - 172.17.3.99/24
#  - 10.0.0.99/24 # this requires the external network on the cephstorage node

ceph_daemons_layout:
  monitoring: true
  rbd: true
  rgw: true
  mds: true

decomm_nodes:
  - controller-0
  - controller-1
  - controller-2

target_nodes:
  - cephstorage-0
  - cephstorage-1
  - cephstorage-2
```

As per the above, it is possible to provide a set of overrides to customize the
behavior of the role execution.
The `ceph_daemons_layout` struct can be used to entirely skip daemons that can't
be applied to the current topology: if the `Ceph dashboard` is not deployed and
`Manila` is not part of the overcloud deployment, we can pass the following
struct to skip those sections:

```
ceph_daemons_layout:
  monitoring: false
  rbd: true
  rgw: true
  mds: false
```

For the same reason, if the overcloud has been deployed with `cephadm-rbd-only.yaml`,
`RGW` can be skipped following the same approach.
An important override that should be provided is the list of `decomm_nodes` and
`target_nodes`: the first list maps to the second list (via `zip` function) to
make sure that each source node has a corresponding target node where the daemons
can be redeployed.
In the example above:

```
controller-0  maps to cephstorage-0
controller-1  maps to cephstorage-1
controller-2  maps to cephstorage-2
```

Dependencies
------------

Great part of the commands executed against an existing Ceph cluster return a
`json` formatted output.
To easily process this output, and minimize the amount of tasks required to
analyze the `stdout` of a registered variable, the `community.general.json_query`
module has been extensively used, and it has been added in the `requirements.yaml`
of the project.

Playbook
--------

The playbook that executes the Ceph migration can be found in [playbooks/](../../playbooks/test_externalize_ceph.yaml)
directory and can be run with the following command:

```
ansible-playbook -i <inventory> $PLAYBOOK_DIR/test_externalize_ceph.yaml -e @overrides.yaml
```

- `overrides.yaml` can be built as described earlier.
- `inventory` should be replaced by the inventory used to connect to the TripleO
  deployed nodes.

It is possible to execute the migration of a specific Ceph daemon type using the
tags.
For example, the RGW migration only can be triggered with the following:

```
ansible-playbook -i <inventory> $PLAYBOOK_DIR/test_externalize_ceph.yaml -e @overrides.yaml --tags ceph_rgw
```
