# Data Plane adoption - Ceph RGW Migration

In this scenario, assuming Ceph is already >= 5, either for HCI or dedicated
Storage nodes, the RGW daemons living in the OpenStack Controller nodes will be
migrated into the existing external RHEL nodes (typically the Compute nodes
for an HCI environment or CephStorage nodes in the remaining use cases).

## Requirements

* Ceph is >= 5 and managed by cephadm/orchestrator
* An undercloud is still available: nodes and networks are managed by TripleO

## Ceph Daemon Cardinality

**Ceph 5+** applies [strict constraints][0] in the way daemons can be colocated
within the same node. The resulting topology depends on the available hardware,
as well as the amount of Ceph services present in the Controller nodes which are
going to be retired. The following document describes the procedure required
to migrate the RGW component (and keep an HA model using the [Ceph Ingress
daemon][1] in a common TripleO scenario where Controller nodes represent the
[spec placement][2] where the service is deployed. As a general rule, the
number of services that can be migrated depends on the number of available
nodes in the cluster. The following diagrams cover the distribution of the Ceph
daemons on the CephStorage nodes where at least three nodes are required in a
scenario that sees only RGW and RBD (no dashboard):


|    |                     |             |
|----|---------------------|-------------|
| osd | mon/mgr/crash      | rgw/ingress |
| osd | mon/mgr/crash      | rgw/ingress |
| osd | mon/mgr/crash      | rgw/ingress |


With dashboard, and without Manila at least four nodes are required (dashboard
has no failover):

|     |                     |             |
|-----|---------------------|-------------|
| osd | mon/mgr/crash | rgw/ingress       |
| osd | mon/mgr/crash | rgw/ingress       |
| osd | mon/mgr/crash | dashboard/grafana |
| osd | rgw/ingress   | (free)            |


With dashboard and Manila 5 nodes minimum are required (and dashboard has no
failover):

|     |                     |                         |
|-----|---------------------|-------------------------|
| osd | mon/mgr/crash       | rgw/ingress             |
| osd | mon/mgr/crash       | rgw/ingress             |
| osd | mon/mgr/crash       | mds/ganesha/ingress     |
| osd | rgw/ingress         | mds/ganesha/ingress     |
| osd | mds/ganesha/ingress | dashboard/grafana       |


## Current Status


```
(undercloud) [stack@undercloud-0 ~]$ metalsmith list


    +------------------------+    +----------------+
    | IP Addresses           |    |  Hostname      |
    +------------------------+    +----------------+
    | ctlplane=192.168.24.25 |    | cephstorage-0  |
    | ctlplane=192.168.24.10 |    | cephstorage-1  |
    | ctlplane=192.168.24.32 |    | cephstorage-2  |
    | ctlplane=192.168.24.28 |    | compute-0      |
    | ctlplane=192.168.24.26 |    | compute-1      |
    | ctlplane=192.168.24.43 |    | controller-0   |
    | ctlplane=192.168.24.7  |    | controller-1   |
    | ctlplane=192.168.24.41 |    | controller-2   |
    +------------------------+    +----------------+

```

SSH into `controller-0` and check the `pacemaker` status: this will help
identify the relevant information that we need to know before starting the
RGW migration.


```
Full List of Resources:
  * ip-192.168.24.46	(ocf:heartbeat:IPaddr2):     	Started controller-0
  * ip-10.0.0.103   	(ocf:heartbeat:IPaddr2):     	Started controller-1
  * ip-172.17.1.129 	(ocf:heartbeat:IPaddr2):     	Started controller-2
  * ip-172.17.3.68  	(ocf:heartbeat:IPaddr2):     	Started controller-0
  * ip-172.17.4.37  	(ocf:heartbeat:IPaddr2):     	Started controller-1
  * Container bundle set: haproxy-bundle

[undercloud-0.ctlplane.redhat.local:8787/rh-osbs/rhosp17-openstack-haproxy:pcmklatest]:
    * haproxy-bundle-podman-0   (ocf:heartbeat:podman):  Started controller-2
    * haproxy-bundle-podman-1   (ocf:heartbeat:podman):  Started controller-0
    * haproxy-bundle-podman-2   (ocf:heartbeat:podman):  Started controller-1

```

Use the `ip` command to identify the ranges of the storage networks.

```
[heat-admin@controller-0 ~]$ ip -o -4 a

1: lo	inet 127.0.0.1/8 scope host lo\   	valid_lft forever preferred_lft forever
2: enp1s0	inet 192.168.24.45/24 brd 192.168.24.255 scope global enp1s0\   	valid_lft forever preferred_lft forever
2: enp1s0	inet 192.168.24.46/32 brd 192.168.24.255 scope global enp1s0\   	valid_lft forever preferred_lft forever
7: br-ex	inet 10.0.0.122/24 brd 10.0.0.255 scope global br-ex\   	valid_lft forever preferred_lft forever
8: vlan70	inet 172.17.5.22/24 brd 172.17.5.255 scope global vlan70\   	valid_lft forever preferred_lft forever
8: vlan70	inet 172.17.5.94/32 brd 172.17.5.255 scope global vlan70\   	valid_lft forever preferred_lft forever
9: vlan50	inet 172.17.2.140/24 brd 172.17.2.255 scope global vlan50\   	valid_lft forever preferred_lft forever
10: vlan30	inet 172.17.3.73/24 brd 172.17.3.255 scope global vlan30\   	valid_lft forever preferred_lft forever
10: vlan30	inet 172.17.3.68/32 brd 172.17.3.255 scope global vlan30\   	valid_lft forever preferred_lft forever
11: vlan20	inet 172.17.1.88/24 brd 172.17.1.255 scope global vlan20\   	valid_lft forever preferred_lft forever
12: vlan40	inet 172.17.4.24/24 brd 172.17.4.255 scope global vlan40\   	valid_lft forever preferred_lft forever
```

In this example:

* vlan30 represents the Storage Network, where the new RGW instances should be
  started on the CephStorage nodes
* br-ex represents the External Network, which is where in the current
  environment, haproxy has the frontend VIP assigned


## Prerequisite: check the frontend network (Controller nodes)

Identify the network that we previously had in haproxy and propagate it (via
TripleO) to the CephStorage nodes. This network is used to reserve a new VIP
that will be owned by Ceph and used as the entry point for the RGW service.


ssh into `controller-0` and check the current HaProxy configuration until we
find `ceph_rgw` section:


```
$ less /var/lib/config-data/puppet-generated/haproxy/etc/haproxy/haproxy.cfg

...
...
listen ceph_rgw
  bind 10.0.0.103:8080 transparent
  bind 172.17.3.68:8080 transparent
  mode http
  balance leastconn
  http-request set-header X-Forwarded-Proto https if { ssl_fc }
  http-request set-header X-Forwarded-Proto http if !{ ssl_fc }
  http-request set-header X-Forwarded-Port %[dst_port]
  option httpchk GET /swift/healthcheck
  option httplog
  option forwardfor
  server controller-0.storage.redhat.local 172.17.3.73:8080 check fall 5 inter 2000 rise 2
  server controller-1.storage.redhat.local 172.17.3.146:8080 check fall 5 inter 2000 rise 2
  server controller-2.storage.redhat.local 172.17.3.156:8080 check fall 5 inter 2000 rise 2
```


Double check the network used as HaProxy frontend:

```
[controller-0]$ ip -o -4 a

...
7: br-ex	inet 10.0.0.106/24 brd 10.0.0.255 scope global br-ex\   	valid_lft forever preferred_lft forever
...

```

As described in the previous section, the check on controller-0 shows that we
are exposing the services using the external network, which is not present in
the CephStorage nodes, and we need to propagate it via TripleO.


## Propagate the `HaProxy` frontend network to `CephStorage` nodes

Change the nic template used to define the ceph-storage network interfaces and
add the new config section.

```
---
network_config:
- type: interface
  name: nic1
  use_dhcp: false
  dns_servers: {{ ctlplane_dns_nameservers }}
  addresses:
  - ip_netmask: {{ ctlplane_ip }}/{{ ctlplane_subnet_cidr }}
  routes: {{ ctlplane_host_routes }}
- type: vlan
  vlan_id: {{ storage_mgmt_vlan_id }}
  device: nic1
  addresses:
  - ip_netmask: {{ storage_mgmt_ip }}/{{ storage_mgmt_cidr }}
  routes: {{ storage_mgmt_host_routes }}
- type: interface
  name: nic2
  use_dhcp: false
  defroute: false
- type: vlan
  vlan_id: {{ storage_vlan_id }}
  device: nic2
  addresses:
  - ip_netmask: {{ storage_ip }}/{{ storage_cidr }}
  routes: {{ storage_host_routes }}
- type: ovs_bridge
  name: {{ neutron_physical_bridge_name }}
  dns_servers: {{ ctlplane_dns_nameservers }}
  domain: {{ dns_search_domains }}
  use_dhcp: false
  addresses:
  - ip_netmask: {{ external_ip }}/{{ external_cidr }}
  routes: {{ external_host_routes }}
  members:
  - type: interface
    name: nic3
    primary: true
```

In addition, add the **External** Network to the `baremetal.yaml` file used by
metalsmith and run the `overcloud node provision` command passing the
`--network-config` option:


```
- name: CephStorage
  count: 3
  hostname_format: cephstorage-%index%
  instances:
  - hostname: cephstorage-0
  name: ceph-0
  - hostname: cephstorage-1
  name: ceph-1
  - hostname: cephstorage-2
  name: ceph-2
  defaults:
  profile: ceph-storage
  network_config:
      template: /home/stack/composable_roles/network/nic-configs/ceph-storage.j2
  networks:
  - network: ctlplane
      vif: true
  - network: storage
  - network: storage_mgmt
  - network: external
```


```
(undercloud) [stack@undercloud-0]$

openstack overcloud node provision
   -o overcloud-baremetal-deployed-0.yaml
   --stack overcloud
   --network-config -y
  $PWD/network/baremetal_deployment.yaml
```


Check the new network on the `CephStorage` nodes:

```
[root@cephstorage-0 ~]# ip -o -4 a

1: lo	inet 127.0.0.1/8 scope host lo\   	valid_lft forever preferred_lft forever
2: enp1s0	inet 192.168.24.54/24 brd 192.168.24.255 scope global enp1s0\   	valid_lft forever preferred_lft forever
11: vlan40	inet 172.17.4.43/24 brd 172.17.4.255 scope global vlan40\   	valid_lft forever preferred_lft forever
12: vlan30	inet 172.17.3.23/24 brd 172.17.3.255 scope global vlan30\   	valid_lft forever preferred_lft forever
14: br-ex	inet 10.0.0.133/24 brd 10.0.0.255 scope global br-ex\   	valid_lft forever preferred_lft forever
```

And now it’s time to start migrating the RGW backends and build the ingress on
top of them.


## Migrate the RGW backends

To match the cardinality diagram we use cephadm labels to refer to a group of
nodes where a given daemon type should be deployed.

Add the RGW label to the cephstorage nodes:


```
for i in 0 1 2; {
    ceph orch host label add cephstorage-$i rgw;
}
```


```
[ceph: root@controller-0 /]#

for i in 0 1 2; {
    ceph orch host label add cephstorage-$i rgw;
}

Added label rgw to host cephstorage-0
Added label rgw to host cephstorage-1
Added label rgw to host cephstorage-2

[ceph: root@controller-0 /]# ceph orch host ls

HOST       	ADDR       	LABELS      	STATUS
cephstorage-0  192.168.24.54  osd rgw
cephstorage-1  192.168.24.44  osd rgw
cephstorage-2  192.168.24.30  osd rgw
controller-0   192.168.24.45  _admin mon mgr
controller-1   192.168.24.11  _admin mon mgr
controller-2   192.168.24.38  _admin mon mgr

6 hosts in cluster
```


During the overcloud deployment, RGW is applied at step2
(external_deployment_steps), and a cephadm compatible spec is generated in
`/home/ceph-admin/specs/rgw` from the [ceph_mkspec][3] ansible module.
Find and patch the RGW spec, specifying the right placement using the labels
approach, and change the rgw backend port to **8090** to avoid conflicts
with the [Ceph Ingress Daemon][2] (*)


```
[root@controller-0 heat-admin]# cat rgw

networks:
- 172.17.3.0/24
placement:
  hosts:
  - controller-0
  - controller-1
  - controller-2
service_id: rgw
service_name: rgw.rgw
service_type: rgw
spec:
  rgw_frontend_port: 8080
  rgw_realm: default
  rgw_zone: default
```


Patch the spec replacing controller nodes with the label key

```
---
networks:
- 172.17.3.0/24
placement:
  label: rgw
service_id: rgw
service_name: rgw.rgw
service_type: rgw
spec:
  rgw_frontend_port: 8090
  rgw_realm: default
  rgw_zone: default
```

(*) [cephadm_check_port][4]

Apply the new RGW spec using the orchestrator CLI:

```
$ cephadm shell -m /home/ceph-admin/specs/rgw
$ cephadm shell -- ceph orch apply -i /mnt/rgw
```


Which triggers the redeploy:

```
...
osd.9                     	cephstorage-2
rgw.rgw.cephstorage-0.wsjlgx  cephstorage-0  172.17.3.23:8090   starting
rgw.rgw.cephstorage-1.qynkan  cephstorage-1  172.17.3.26:8090   starting
rgw.rgw.cephstorage-2.krycit  cephstorage-2  172.17.3.81:8090   starting
rgw.rgw.controller-1.eyvrzw   controller-1   172.17.3.146:8080  running (5h)
rgw.rgw.controller-2.navbxa   controller-2   172.17.3.66:8080   running (5h)

...
osd.9                     	cephstorage-2
rgw.rgw.cephstorage-0.wsjlgx  cephstorage-0  172.17.3.23:8090  running (19s)
rgw.rgw.cephstorage-1.qynkan  cephstorage-1  172.17.3.26:8090  running (16s)
rgw.rgw.cephstorage-2.krycit  cephstorage-2  172.17.3.81:8090  running (13s)
```


At this point, we need to make sure that the new RGW backends are reachable on
the new ports, but we’re going to enable an **IngressDaemon** on port **8080**
later in the process. For this reason, ssh on each RGW node (the _CephStorage_
nodes) and add the iptables rule to allow connections to both 8080 and 8090
ports in the CephStorage nodes.


```
iptables -I INPUT -p tcp -m tcp --dport 8080 -m conntrack --ctstate NEW -m comment --comment "ceph rgw ingress" -j ACCEPT

iptables -I INPUT -p tcp -m tcp --dport 8090 -m conntrack --ctstate NEW -m comment --comment "ceph rgw backends" -j ACCEPT

for port in 8080 8090; { 
    for i in 25 10 32; {
       ssh heat-admin@192.168.24.$i sudo iptables -I INPUT \
       -p tcp -m tcp --dport $port -m conntrack --ctstate NEW \
       -j ACCEPT;
   }
}
```

From a Controller node (e.g. controller-0) try to reach (curl) the rgw backends:


```
for i in 26 23 81; do {
    echo "----"
    curl 172.17.3.$i:8090;
    echo "----"
    echo
done
```



And you should observe the following:

```
----
Query 172.17.3.23
<?xml version="1.0" encoding="UTF-8"?><ListAllMyBucketsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Owner><ID>anonymous</ID><DisplayName></DisplayName></Owner><Buckets></Buckets></ListAllMyBucketsResult>
---

----
Query 172.17.3.26
<?xml version="1.0" encoding="UTF-8"?><ListAllMyBucketsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Owner><ID>anonymous</ID><DisplayName></DisplayName></Owner><Buckets></Buckets></ListAllMyBucketsResult>
---

----
Query 172.17.3.81
<?xml version="1.0" encoding="UTF-8"?><ListAllMyBucketsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Owner><ID>anonymous</ID><DisplayName></DisplayName></Owner><Buckets></Buckets></ListAllMyBucketsResult>
---
```


### NOTE

In case RGW backends are migrated in the CephStorage nodes, there’s no
“internalAPI” network(this is not true in the case of HCI). Reconfig the RGW
keystone endpoint, pointing to the external Network that has been propagated
(see the previous section)

```
[ceph: root@controller-0 /]# ceph config dump | grep keystone
global   basic rgw_keystone_url  http://172.16.1.111:5000

[ceph: root@controller-0 /]# ceph config set global rgw_keystone_url http://10.0.0.103:5000
```


## Deploy a Ceph IngressDaemon

`HaProxy` is managed by TripleO via `Pacemaker`: the three running instances at
this point will point to the old RGW backends, resulting in a wrong, not
working configuration.
Since we’re going to deploy the [Ceph Ingress Daemon][3], the first thing to do
is remove the existing `ceph_rgw` config, clean up the config created by TripleO
and restart the service to make sure other services are not affected by this
change.

ssh  on each Controller node and remove the following is the section from
`/var/lib/config-data/puppet-generated/haproxy/etc/haproxy/haproxy.cfg`:


```
listen ceph_rgw
  bind 10.0.0.103:8080 transparent
  mode http
  balance leastconn
  http-request set-header X-Forwarded-Proto https if { ssl_fc }
  http-request set-header X-Forwarded-Proto http if !{ ssl_fc }
  http-request set-header X-Forwarded-Port %[dst_port]
  option httpchk GET /swift/healthcheck
  option httplog
  option forwardfor
   server controller-0.storage.redhat.local 172.17.3.73:8080 check fall 5 inter 2000 rise 2
  server controller-1.storage.redhat.local 172.17.3.146:8080 check fall 5 inter 2000 rise 2
  server controller-2.storage.redhat.local 172.17.3.156:8080 check fall 5 inter 2000 rise 2
```


Restart `haproxy-bundle` and make sure it’s started:

```
[root@controller-0 ~]# sudo pcs resource restart haproxy-bundle
haproxy-bundle successfully restarted


[root@controller-0 ~]# sudo pcs status | grep haproxy

  * Container bundle set: haproxy-bundle [undercloud-0.ctlplane.redhat.local:8787/rh-osbs/rhosp17-openstack-haproxy:pcmklatest]:
    * haproxy-bundle-podman-0   (ocf:heartbeat:podman):  Started controller-0
    * haproxy-bundle-podman-1   (ocf:heartbeat:podman):  Started controller-1
    * haproxy-bundle-podman-2   (ocf:heartbeat:podman):  Started controller-2
```


Double check no process is bound to 8080 anymore”

```
[root@controller-0 ~]# ss -antop | grep 8080
[root@controller-0 ~]#
```

And the swift CLI should fail at this point:

```
(overcloud) [root@cephstorage-0 ~]# swift list

HTTPConnectionPool(host='10.0.0.103', port=8080): Max retries exceeded with url: /swift/v1/AUTH_852f24425bb54fa896476af48cbe35d3?format=json (Caused by NewConnectionError('<urllib3.connection.HTTPConnection object at 0x7fc41beb0430>: Failed to establish a new connection: [Errno 111] Connection refused'))
```

Now we can start deploying the Ceph IngressDaemon on the CephStorage nodes.

Set the required images for both HaProxy and Keepalived

```
[ceph: root@controller-0 /]# ceph config set mgr mgr/cephadm/container_image_haproxy quay.io/ceph/haproxy:2.3

[ceph: root@controller-0 /]# ceph config set mgr mgr/cephadm/container_image_keepalived quay.io/ceph/keepalived:2.1.5
```


Prepare the ingress spec and mount it to cephadm:

```
$ sudo vim /home/ceph-admin/specs/rgw_ingress
```

and paste the following content:

```
---
service_type: ingress
service_id: rgw.rgw
placement:
  label: rgw
spec:
  backend_service: rgw.rgw
  virtual_ip: 10.0.0.89/24
  frontend_port: 8080
  monitor_port: 8898
  virtual_interface_networks:
    - 10.0.0.0/24
```


Mount the generated spec and apply it using the orchestrator CLI:

```
$ cephadm shell -m /home/ceph-admin/specs/rgw_ingress
$ cephadm shell -- ceph orch apply -i /mnt/rgw_ingress
```


Wait until the ingress is deployed and query the resulting endpoint:

```
[ceph: root@controller-0 /]# ceph orch ls

NAME                 	PORTS            	RUNNING  REFRESHED  AGE  PLACEMENT
crash                                         	6/6  6m ago 	3d   *
ingress.rgw.rgw      	10.0.0.89:8080,8898  	6/6  37s ago	60s  label:rgw
mds.mds                   3/3  6m ago 	3d   controller-0;controller-1;controller-2
mgr                       3/3  6m ago 	3d   controller-0;controller-1;controller-2
mon                       3/3  6m ago 	3d   controller-0;controller-1;controller-2
osd.default_drive_group   15  37s ago	3d   cephstorage-0;cephstorage-1;cephstorage-2
rgw.rgw   ?:8090          3/3  37s ago	4m   label:rgw
```

```
[ceph: root@controller-0 /]# curl  10.0.0.89:8080

---
<?xml version="1.0" encoding="UTF-8"?><ListAllMyBucketsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Owner><ID>anonymous</ID><DisplayName></DisplayName></Owner><Buckets></Buckets></ListAllMyBucketsResult>[ceph: root@controller-0 /]#
—
```

The result above shows that we’re able to reach the backend from the
IngressDaemon, which means we’re almost ready to interact with it using the
swift CLI.


## Update the object-store endpoints

The endpoints still point to the old VIP owned by pacemaker, but given it’s
still used by other services and we reserved a new VIP on the same network,
before any other action we should update the object-store endpoint.

List the current endpoints:

```
(overcloud) [stack@undercloud-0 ~]$ openstack endpoint list | grep object

| 1326241fb6b6494282a86768311f48d1 | regionOne | swift    	| object-store   | True	| internal  | http://172.17.3.68:8080/swift/v1/AUTH_%(project_id)s |
| 8a34817a9d3443e2af55e108d63bb02b | regionOne | swift    	| object-store   | True	| public	| http://10.0.0.103:8080/swift/v1/AUTH_%(project_id)s  |
| fa72f8b8b24e448a8d4d1caaeaa7ac58 | regionOne | swift    	| object-store   | True	| admin 	| http://172.17.3.68:8080/swift/v1/AUTH_%(project_id)s |
```

Update the endpoints pointing to the Ingress VIP:


```
(overcloud) [stack@undercloud-0 ~]$ openstack endpoint set --url "http://10.0.0.89:8080/swift/v1/AUTH_%(project_id)s" 95596a2d92c74c15b83325a11a4f07a3

(overcloud) [stack@undercloud-0 ~]$ openstack endpoint list | grep object-store
| 6c7244cc8928448d88ebfad864fdd5ca | regionOne | swift    	| object-store   | True	| internal  | http://172.17.3.79:8080/swift/v1/AUTH_%(project_id)s |
| 95596a2d92c74c15b83325a11a4f07a3 | regionOne | swift    	| object-store   | True	| public	| http://10.0.0.89:8080/swift/v1/AUTH_%(project_id)s   |
| e6d0599c5bf24a0fb1ddf6ecac00de2d | regionOne | swift    	| object-store   | True	| admin 	| http://172.17.3.79:8080/swift/v1/AUTH_%(project_id)s |
```

And repeat the same action for both internal and admin.
Test the migrated service.

```
(overcloud) [stack@undercloud-0 ~]$ swift list --debug

DEBUG:swiftclient:Versionless auth_url - using http://10.0.0.115:5000/v3 as endpoint
DEBUG:keystoneclient.auth.identity.v3.base:Making authentication request to http://10.0.0.115:5000/v3/auth/tokens
DEBUG:urllib3.connectionpool:Starting new HTTP connection (1): 10.0.0.115:5000
DEBUG:urllib3.connectionpool:http://10.0.0.115:5000 "POST /v3/auth/tokens HTTP/1.1" 201 7795
DEBUG:keystoneclient.auth.identity.v3.base:{"token": {"methods": ["password"], "user": {"domain": {"id": "default", "name": "Default"}, "id": "6f87c7ffdddf463bbc633980cfd02bb3", "name": "admin", "password_expires_at": null}, 


...
...
...

DEBUG:swiftclient:REQ: curl -i http://10.0.0.89:8080/swift/v1/AUTH_852f24425bb54fa896476af48cbe35d3?format=json -X GET -H "X-Auth-Token: gAAAAABj7KHdjZ95syP4c8v5a2zfXckPwxFQZYg0pgWR42JnUs83CcKhYGY6PFNF5Cg5g2WuiYwMIXHm8xftyWf08zwTycJLLMeEwoxLkcByXPZr7kT92ApT-36wTfpi-zbYXd1tI5R00xtAzDjO3RH1kmeLXDgIQEVp0jMRAxoVH4zb-DVHUos" -H "Accept-Encoding: gzip"
DEBUG:swiftclient:RESP STATUS: 200 OK
DEBUG:swiftclient:RESP HEADERS: {'content-length': '2', 'x-timestamp': '1676452317.72866', 'x-account-container-count': '0', 'x-account-object-count': '0', 'x-account-bytes-used': '0', 'x-account-bytes-used-actual': '0', 'x-account-storage-policy-default-placement-container-count': '0', 'x-account-storage-policy-default-placement-object-count': '0', 'x-account-storage-policy-default-placement-bytes-used': '0', 'x-account-storage-policy-default-placement-bytes-used-actual': '0', 'x-trans-id': 'tx00000765c4b04f1130018-0063eca1dd-1dcba-default', 'x-openstack-request-id': 'tx00000765c4b04f1130018-0063eca1dd-1dcba-default', 'accept-ranges': 'bytes', 'content-type': 'application/json; charset=utf-8', 'date': 'Wed, 15 Feb 2023 09:11:57 GMT'}
DEBUG:swiftclient:RESP BODY: b'[]'
```

Run tempest tests against object-storage:

```
(overcloud) [stack@undercloud-0 tempest-dir]$  tempest run --regex tempest.api.object_storage
...
...
...
======
Totals
======
Ran: 141 tests in 606.5579 sec.
 - Passed: 128
 - Skipped: 13
 - Expected Fail: 0
 - Unexpected Success: 0
 - Failed: 0
Sum of execute time for each test: 657.5183 sec.

==============
Worker Balance
==============
 - Worker 0 (1 tests) => 0:10:03.400561
 - Worker 1 (2 tests) => 0:00:24.531916
 - Worker 2 (4 tests) => 0:00:10.249889
 - Worker 3 (30 tests) => 0:00:32.730095
 - Worker 4 (51 tests) => 0:00:26.246044
 - Worker 5 (6 tests) => 0:00:20.114803
 - Worker 6 (20 tests) => 0:00:16.290323
 - Worker 7 (27 tests) => 0:00:17.103827
```


## Additional Resources

A screen recording is available [here](https://asciinema.org/a/560091).
<script id="asciicast-560091" src="https://asciinema.org/a/560091.js" async data-autoplay="true" data-speed="2"></script>

[0]: https://access.redhat.com/articles/1548993
[1]: https://docs.ceph.com/en/latest/cephadm/services/rgw/#high-availability-service-for-rgw
[2]: https://github.com/openstack/tripleo-ansible/blob/master/tripleo_ansible/roles/tripleo_cephadm/tasks/rgw.yaml#L26-L30
[3]: https://github.com/openstack/tripleo-ansible/blob/master/tripleo_ansible/ansible_plugins/modules/ceph_mkspec.py
[4]: https://github.com/ceph/ceph/blob/main/src/cephadm/cephadm.py#L1423-L1446
