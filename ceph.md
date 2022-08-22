# Data Plane adoption - Ceph Migration


In this scenario, assuming Ceph is already >= 5, either for HCI or dedicated
Storage nodes, the daemons living in the OpenStack control plane should be
moved/migrated into the existing external RHEL nodes (typically the compute
nodes for an HCI environment or dedicated storage nodes in all the remaining
use cases).

## Requirements

- Ceph is >= 5 and managed by cephadm/orchestrator
- Ceph NFS (ganesha) migrated from a [TripleO based deployment to cephadm](https://bugzilla.redhat.com/show_bug.cgi?id=2044910)
- Both the Ceph public and cluster networks are propagated, via TripleO, to the target nodes
- Ceph Mons need to keep their IPs (to avoid cold migration).


## SCENARIO 1: Migrate mon and mgr from controller nodes


The goal of the first POC is to prove we are able to successfully drain a
controller node, in terms of ceph daemons, and move them to a different node.
The initial target of the POC is RBD only, which means we’re going to move only
mon and mgr daemons. For the purposes of this POC, we'll deploy a ceph cluster
with only mon, mgrs, and osds to simulate the environment a customer will be in
before starting the migration.
The goal of the first POC is to ensure that:
- We can keep the mon IP addresses moving them to the CephStorage nodes
- We can drain the existing controller nodes and shutting them down
- We can deploy additional monitors to the existing nodes, promoting them as
  \_admin nodes that can be used by administrators to manage the ceph cluster
  and perform day2 operations against it
- We can keep the cluster operational during the migration


### Prerequisites

The Storage Nodes should be configured to have both **storage** and **storage_mgmt**
network to make sure we can use both Ceph public and cluster networks.

This step is the only one where the interaction with TripleO is required. From
17+ we don’t have to run any stack update, however, we have commands that
should be performed to run os-net-config on the baremetal node and configure
additional networks.

Make sure the network is defined in metalsmith.yaml for the CephStorageNodes:

  ```
  - name: CephStorage
    count: 2
    instances:
      - hostname: oc0-ceph-0
        name: oc0-ceph-0
      - hostname: oc0-ceph-1
        name: oc0-ceph-1
    defaults:
      networks:
        - network: ctlplane
          vif: true
        - network: storage_cloud_0
            subnet: storage_cloud_0_subnet
        - network: storage_mgmt_cloud_0
            subnet: storage_mgmt_cloud_0_subnet
      network_config:
        template: templates/single_nic_vlans/single_nic_vlans_storage.j2
  ```

Then run:

```
openstack overcloud node provision \
  -o overcloud-baremetal-deployed-0.yaml --stack overcloud-0 \
  --network-config -y --concurrency 2 /home/stack/metalsmith-0.yam
```

Verify that the storage network is running on the node:

```
(undercloud) [CentOS-9 - stack@undercloud ~]$ ssh heat-admin@192.168.24.14 ip -o -4 a
Warning: Permanently added '192.168.24.14' (ED25519) to the list of known hosts.
1: lo    inet 127.0.0.1/8 scope host lo\       valid_lft forever preferred_lft forever
5: br-storage    inet 192.168.24.14/24 brd 192.168.24.255 scope global br-storage\       valid_lft forever preferred_lft forever
6: vlan1    inet 192.168.24.14/24 brd 192.168.24.255 scope global vlan1\       valid_lft forever preferred_lft forever
7: vlan11    inet 172.16.11.172/24 brd 172.16.11.255 scope global vlan11\       valid_lft forever preferred_lft forever
8: vlan12    inet 172.16.12.46/24 brd 172.16.12.255 scope global vlan12\       valid_lft forever preferred_lft forever
```



### Migrate mon(s) and mgr(s) on the two existing CephStorage nodes


Create a ceph spec based on the default roles with the mon/mgr on the
controller nodes.

```
openstack overcloud ceph spec -o ceph_spec.yaml -y  \
   --stack overcloud-0     overcloud-baremetal-deployed-0.yaml
```

Deploy the Ceph cluster

```
 openstack overcloud ceph deploy overcloud-baremetal-deployed-0.yaml \
    --stack overcloud-0 -o deployed_ceph.yaml \
    --network-data ~/oc0-network-data.yaml \
    --ceph-spec ~/ceph_spec.yaml
```


**Note**:

The ceph\_spec.yaml, which is the OSP generated description of the ceph cluster,
will be used, later in the process, as the basic template required by cephadm
to update the status/info of the daemons


Check the status of the cluster


```
[ceph: root@oc0-controller-0 /]# ceph -s
  cluster:
    id:     f6ec3ebe-26f7-56c8-985d-eb974e8e08e3
    health: HEALTH_OK

  services:
    mon: 3 daemons, quorum oc0-controller-0,oc0-controller-1,oc0-controller-2 (age 19m)
    mgr: oc0-controller-0.xzgtvo(active, since 32m), standbys: oc0-controller-1.mtxohd, oc0-controller-2.ahrgsk
    osd: 8 osds: 8 up (since 12m), 8 in (since 18m); 1 remapped pgs

  data:
    pools:   1 pools, 1 pgs
    objects: 0 objects, 0 B
    usage:   43 MiB used, 400 GiB / 400 GiB avail
    pgs:     1 active+clean

```


```
[ceph: root@oc0-controller-0 /]# ceph orch host ls
HOST              ADDR           LABELS          STATUS
oc0-ceph-0        192.168.24.14  osd
oc0-ceph-1        192.168.24.7   osd
oc0-controller-0  192.168.24.15  _admin mgr mon
oc0-controller-1  192.168.24.23  _admin mgr mon
oc0-controller-2  192.168.24.13  _admin mgr mon
```

The goal of the next section is to migrate the oc0-controller-{1,2} daemons
into oc0-ceph-{0,1} as the very basic scenario that demonstrates we can
actually make this kind of migration using cephadm.


### Migrate oc0-controller-1 into oc0-ceph-0


ssh into controller-0, then

`cephadm shell -v /home/ceph-admin/specs:/specs`

ssh into ceph-0, then


`sudo “watch podman ps”  # watch the new mon/mgr being deployed here`

(optional) if mgr is active in the source node, then:

```
ceph mgr fail <mgr instance>
```

From the cephadm shell, remove the labels on oc0-controller-1

```
    for label in mon mgr _admin; do
           ceph orch host rm label oc0-controller-1 $label;
    done
```

Add the missing labels to oc0-ceph-0

```
[ceph: root@oc0-controller-0 /]#
> for label in mon mgr _admin; do ceph orch host label add oc0-ceph-0 $label; done
Added label mon to host oc0-ceph-0
Added label mgr to host oc0-ceph-0
Added label _admin to host oc0-ceph-0
```

Drain and force-remove the oc0-controller-1 node

```
[ceph: root@oc0-controller-0 /]# ceph orch host drain oc0-controller-1
Scheduled to remove the following daemons from host 'oc0-controller-1'
type                 id
-------------------- ---------------
mon                  oc0-controller-1
mgr                  oc0-controller-1.mtxohd
crash                oc0-controller-1
```

```
[ceph: root@oc0-controller-0 /]# ceph orch host rm oc0-controller-1 --force
Removed  host 'oc0-controller-1'

[ceph: root@oc0-controller-0 /]# ceph orch host ls
HOST              ADDR           LABELS          STATUS
oc0-ceph-0        192.168.24.14  osd
oc0-ceph-1        192.168.24.7   osd
oc0-controller-0  192.168.24.15  mgr mon _admin
oc0-controller-2  192.168.24.13  _admin mgr mon
```


If you have only 3 mon nodes, and the drain of the node doesn’t work as
expected (the containers are still there), then SSH to controller-1 and
force-purge the containers in the node:

```
[root@oc0-controller-1 ~]# sudo podman ps
CONTAINER ID  IMAGE                                                                                        COMMAND               CREATED         STATUS             PORTS       NAMES
5c1ad36472bc  quay.io/ceph/daemon@sha256:320c364dcc8fc8120e2a42f54eb39ecdba12401a2546763b7bef15b02ce93bc4  -n mon.oc0-contro...  35 minutes ago  Up 35 minutes ago              ceph-f6ec3ebe-26f7-56c8-985d-eb974e8e08e3-mon-oc0-controller-1
3b14cc7bf4dd  quay.io/ceph/daemon@sha256:320c364dcc8fc8120e2a42f54eb39ecdba12401a2546763b7bef15b02ce93bc4  -n mgr.oc0-contro...  35 minutes ago  Up 35 minutes ago              ceph-f6ec3ebe-26f7-56c8-985d-eb974e8e08e3-mgr-oc0-controller-1-mtxohd

[root@oc0-controller-1 ~]# cephadm rm-cluster --fsid f6ec3ebe-26f7-56c8-985d-eb974e8e08e3 --force

[root@oc0-controller-1 ~]# sudo podman ps
CONTAINER ID  IMAGE       COMMAND     CREATED     STATUS      PORTS       NAMES
```

**Note:**
cephadm rm-cluster on a node which is not part of the cluster anymore has the
effect of removing all the containers and doing some cleanup on the filesystem.

Before shutting the oc0-controller-1 down, move the ip address (on the same
network) to the oc0-ceph-0 node:

```
mon_host = [v2:172.16.11.54:3300/0,v1:172.16.11.54:6789/0] [v2:172.16.11.121:3300/0,v1:172.16.11.121:6789/0] [v2:172.16.11.205:3300/0,v1:172.16.11.205:6789/0]

[root@oc0-controller-1 ~]# ip -o -4 a
1: lo    inet 127.0.0.1/8 scope host lo\       valid_lft forever preferred_lft forever
5: br-ex    inet 192.168.24.23/24 brd 192.168.24.255 scope global br-ex\       valid_lft forever preferred_lft forever
6: vlan100    inet 192.168.100.96/24 brd 192.168.100.255 scope global vlan100\       valid_lft forever preferred_lft forever
7: vlan12    inet 172.16.12.154/24 brd 172.16.12.255 scope global vlan12\       valid_lft forever preferred_lft forever
8: vlan11    inet 172.16.11.121/24 brd 172.16.11.255 scope global vlan11\       valid_lft forever preferred_lft forever
9: vlan13    inet 172.16.13.178/24 brd 172.16.13.255 scope global vlan13\       valid_lft forever preferred_lft forever
10: vlan70    inet 172.17.0.23/20 brd 172.17.15.255 scope global vlan70\       valid_lft forever preferred_lft forever
11: vlan1    inet 192.168.24.23/24 brd 192.168.24.255 scope global vlan1\       valid_lft forever preferred_lft forever
12: vlan14    inet 172.16.14.223/24 brd 172.16.14.255 scope global vlan14\       valid_lft forever preferred_lft forever
```

On the oc0-ceph-0:

```
[heat-admin@oc0-ceph-0 ~]$ ip -o -4 a
1: lo    inet 127.0.0.1/8 scope host lo\       valid_lft forever preferred_lft forever
5: br-storage    inet 192.168.24.14/24 brd 192.168.24.255 scope global br-storage\       valid_lft forever preferred_lft forever
6: vlan1    inet 192.168.24.14/24 brd 192.168.24.255 scope global vlan1\       valid_lft forever preferred_lft forever
7: vlan11    inet 172.16.11.172/24 brd 172.16.11.255 scope global vlan11\       valid_lft forever preferred_lft forever
8: vlan12    inet 172.16.12.46/24 brd 172.16.12.255 scope global vlan12\       valid_lft forever preferred_lft forever
[heat-admin@oc0-ceph-0 ~]$ sudo ip a add 172.16.11.121 dev vlan11
[heat-admin@oc0-ceph-0 ~]$ ip -o -4 a
1: lo    inet 127.0.0.1/8 scope host lo\       valid_lft forever preferred_lft forever
5: br-storage    inet 192.168.24.14/24 brd 192.168.24.255 scope global br-storage\       valid_lft forever preferred_lft forever
6: vlan1    inet 192.168.24.14/24 brd 192.168.24.255 scope global vlan1\       valid_lft forever preferred_lft forever
7: vlan11    inet 172.16.11.172/24 brd 172.16.11.255 scope global vlan11\       valid_lft forever preferred_lft forever
7: vlan11    inet 172.16.11.121/32 scope global vlan11\       valid_lft forever preferred_lft forever
8: vlan12    inet 172.16.12.46/24 brd 172.16.12.255 scope global vlan12\       valid_lft forever preferred_lft forever
```


Poweroff oc0-controller-1.

Add the new mon on oc0-ceph-0 using the old ip address:

```
[ceph: root@oc0-controller-0 /]# ceph orch daemon add mon oc0-ceph-0:172.16.11.121
Deployed mon.oc0-ceph-0 on host 'oc0-ceph-0'
```

Check the new container in the oc0-ceph-0 node:

```
b581dc8bbb78  quay.io/ceph/daemon@sha256:320c364dcc8fc8120e2a42f54eb39ecdba12401a2546763b7bef15b02ce93bc4  -n mon.oc0-ceph-0...  24 seconds ago  Up 24 seconds ago              ceph-f6ec3ebe-26f7-56c8-985d-eb974e8e08e3-mon-oc0-ceph-0
```

On the cephadm shell, backup the existing ceph_spec.yaml, edit the spec
removing any oc0-controller-1 entry, and replace it with oc0-ceph-0:


```
cp ceph_spec.yaml ceph_spec.yaml.bkp # backup the ceph_spec.yaml file

[ceph: root@oc0-controller-0 specs]# diff -u ceph_spec.yaml.bkp ceph_spec.yaml

--- ceph_spec.yaml.bkp  2022-07-29 15:41:34.516329643 +0000
+++ ceph_spec.yaml      2022-07-29 15:28:26.455329643 +0000
@@ -7,14 +7,6 @@
 - mgr
 service_type: host
 ---
-addr: 192.168.24.12
-hostname: oc0-controller-1
-labels:
-- _admin
-- mon
-- mgr
-service_type: host
----
 addr: 192.168.24.19
 hostname: oc0-controller-2
 labels:
@@ -38,7 +30,7 @@
 placement:
   hosts:
   - oc0-controller-0
-  - oc0-controller-1
+  - oc0-ceph-0
   - oc0-controller-2
 service_id: mon
 service_name: mon
@@ -47,8 +39,8 @@
 placement:
   hosts:
   - oc0-controller-0
-  - oc0-controller-1
   - oc0-controller-2
+  - oc0-ceph-0
 service_id: mgr
 service_name: mgr
 service_type: mgr
```

Apply the resulting spec:

```
ceph orch apply -i ceph_spec.yaml 

 The result of 12 is having a new mgr deployed on the oc0-ceph-0 node, and the spec reconciled within cephadm

[ceph: root@oc0-controller-0 specs]# ceph orch ls
NAME                     PORTS  RUNNING  REFRESHED  AGE  PLACEMENT
crash                               4/4  5m ago     61m  *
mgr                                 3/3  5m ago     69s  oc0-controller-0;oc0-ceph-0;oc0-controller-2
mon                                 3/3  5m ago     70s  oc0-controller-0;oc0-ceph-0;oc0-controller-2
osd.default_drive_group               8  2m ago     69s  oc0-ceph-0;oc0-ceph-1

[ceph: root@oc0-controller-0 specs]# ceph -s
  cluster:
    id:     f6ec3ebe-26f7-56c8-985d-eb974e8e08e3
    health: HEALTH_WARN
            1 stray host(s) with 1 daemon(s) not managed by cephadm

  services:
    mon: 3 daemons, quorum oc0-controller-0,oc0-controller-2,oc0-ceph-0 (age 5m)
    mgr: oc0-controller-0.xzgtvo(active, since 62m), standbys: oc0-controller-2.ahrgsk, oc0-ceph-0.hccsbb
    osd: 8 osds: 8 up (since 42m), 8 in (since 49m); 1 remapped pgs

  data:
    pools:   1 pools, 1 pgs
    objects: 0 objects, 0 B
    usage:   43 MiB used, 400 GiB / 400 GiB avail
    pgs:     1 active+clean
```

Fix the warning by refreshing the mgr:

```
ceph mgr fail oc0-controller-0.xzgtvo
```

And at this point the cluster is clean:

```
[ceph: root@oc0-controller-0 specs]# ceph -s
  cluster:
    id:     f6ec3ebe-26f7-56c8-985d-eb974e8e08e3
    health: HEALTH_OK

  services:
    mon: 3 daemons, quorum oc0-controller-0,oc0-controller-2,oc0-ceph-0 (age 7m)
    mgr: oc0-controller-2.ahrgsk(active, since 25s), standbys: oc0-controller-0.xzgtvo, oc0-ceph-0.hccsbb
    osd: 8 osds: 8 up (since 44m), 8 in (since 50m); 1 remapped pgs

  data:
    pools:   1 pools, 1 pgs
    objects: 0 objects, 0 B
    usage:   43 MiB used, 400 GiB / 400 GiB avail
    pgs:     1 active+clean
```

oc0-controller-1 has been removed and powered off without leaving traces on the ceph cluster.

The same approach and the same steps can be applied to migrate oc0-controller-2 to oc0-ceph-1.

### Screen Recording:

- [Externalize a TripleO deployed Ceph cluster](https://asciinema.org/a/508174)

## What’s next

## Useful resources

- [cephadm - deploy additional mon(s)](https://docs.ceph.com/en/pacific/cephadm/services/mon/#deploy-additional-monitors)
