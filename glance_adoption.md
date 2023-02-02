# Glance adoption

Adopting Glance means that an existing `OpenStackControlPlane` CR, where Glance
is supposed to be disabled, should be patched to start the service with the
configuration parameters provided by the source environment.

When the procedure is over, the expectation is to see the `GlanceAPI` service
up and running: the `Keystone endpoints` should be updated and the same backend
of the source Cloud will be available. If the conditions above are met, the
adoption is considered concluded.

This guide also assumes that:

1. A `TripleO` environment (the source Cloud) is running on one side;
2. A `SNO` / `CodeReadyContainers` is running on the other side;
3. (optional) an internal/external `Ceph` cluster is reacheable by both `crc` and
`TripleO`


## Prerequisites

* Previous Adoption steps completed. Notably, MariaDB and Keystone
  should be already adopted.


## Procedure - Glance adoption

As already done for [Keystone](https://github.com/openstack-k8s-operators/data-plane-adoption/blob/main/keystone_adoption.md), the Glance Adoption follows the same pattern.

Patch OpenStackControlPlane to deploy Glance:

```
oc patch openstackcontrolplane openstack --type=merge --patch '
spec:
  glance:
    enabled: true
    template:
      databaseInstance: openstack
      containerImage: quay.io/tripleozedcentos9/openstack-glance-api:current-tripleo
      storageClass: "local-storage"
      storageRequest: 10G
      glanceAPIInternal:
        containerImage: quay.io/tripleozedcentos9/openstack-glance-api:current-tripleo
      glanceAPIExternal:
        containerImage: quay.io/tripleozedcentos9/openstack-glance-api:current-tripleo
'
```

However, if a Ceph backend is used, the `customServiceConfig` parameter should
be used to inject the right configuration to the `GlanceAPI` instance.

Make sure the Ceph related secret exists in the `openstack` namespace:

```
$ oc get secrets | grep ceph
ceph-conf-files
```

If it doesn't exist, create a `Secret` which contains the `Cephx` key and Ceph
configuration file so that the Glance pod created by the operator can mount
those files in `/etc/ceph`.

```
---
apiVersion: v1
kind: Secret
metadata:
  name: ceph-client-conf
  namespace: openstack
stringData:
  ceph.client.openstack.keyring: |
    [client.openstack]
        key = <secret key>
        caps mgr = "allow *"
        caps mon = "profile rbd"
        caps osd = "profile rbd pool=images"
  ceph.conf: |
    [global]
    fsid = 7a1719e8-9c59-49e2-ae2b-d7eb08c695d4
    mon_host = 10.1.1.2,10.1.1.3,10.1.1.4
```

This secret will be used in the `extraVolumes` parameters to propagate the files
to the `GlanceAPI` pods (both internal and external).

Patch OpenStackControlPlane to deploy Glance:

```
oc patch openstackcontrolplane openstack --type=merge --patch '
spec:
  glance:
    enabled: true
    template:
      databaseInstance: openstack
      containerImage: quay.io/tripleozedcentos9/openstack-glance-api:current-tripleo
      customServiceConfig: |
        [DEFAULT]
        enabled_backends=default_backend:rbd
        [glance_store]
        default_backend=default_backend
        [default_backend]
        rbd_store_ceph_conf=/etc/ceph/ceph.conf
        rbd_store_user=openstack
        rbd_store_pool=images
        store_description=Ceph glance store backend.
      storageClass: "local-storage"
      storageRequest: 10G
      glanceAPIInternal:
        containerImage: quay.io/tripleozedcentos9/openstack-glance-api:current-tripleo
      glanceAPIExternal:
        containerImage: quay.io/tripleozedcentos9/openstack-glance-api:current-tripleo
  extraMounts:
    - extraVol:
      - propagation:
        - Glance
        extraVolType: Ceph
        volumes:
        - name: ceph
          projected:
            sources:
            - secret:
                name: ceph-conf-files
        mounts:
        - name: ceph
          mountPath: "/etc/ceph"
          readOnly: true
'
```

## Post-checks

### Test the glance service from the OpenStack cli

Inspect the resulting glance pods:

```
sh-5.1# cat /etc/glance/glance.conf.d/01-custom.conf

[DEFAULT]
enabled_backends=default_backend:rbd,ceph1:rbd
enabled_backends=default_backend:rbd
[glance_store]
default_backend=default_backend
[default_backend]
rbd_store_ceph_conf=/etc/ceph/ceph.conf
rbd_store_user=openstack
rbd_store_pool=images
store_description=Ceph glance store backend.

sh-5.1# ls /etc/ceph/ceph*
/etc/ceph/ceph.client.openstack.keyring  /etc/ceph/ceph.conf
```

Ceph secrets are properly mounted, at this point let's move to the openstack
cli and check the service is active and the endpoints are properly updated.


```
(openstack)$ endpoint list | grep image

| 569ed81064f84d4a91e0d2d807e4c1f1 | regionOne | glance       | image        | True    | internal  | http://glance-internal-openstack.apps-crc.testing   |
| 5843fae70cba4e73b29d4aff3e8b616c | regionOne | glance       | image        | True    | public    | http://glance-public-openstack.apps-crc.testing     |
| 709859219bc24ab9ac548eab74ad4dd5 | regionOne | glance       | image        | True    | admin     | http://glance-admin-openstack.apps-crc.testing      |
```

### Image upload

We can test that an image can be created on from the adopted service.

```
(openstack)$ export OS_CLIENT_CONFIG_FILE=clouds-adopted.yaml
(openstack)$ export OS_CLOUD=adopted
(openstack)$ curl -L -o /tmp/cirros-0.5.2-x86_64-disk.img http://download.cirros-cloud.net/0.5.2/cirros-0.5.2-x86_64-disk.img
    qemu-img convert -O raw /tmp/cirros-0.5.2-x86_64-disk.img /tmp/cirros-0.5.2-x86_64-disk.img.raw
    openstack image create --container-format bare --disk-format raw --file /tmp/cirros-0.5.2-x86_64-disk.img.raw cirros
    openstack image list
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100   273  100   273    0     0   1525      0 --:--:-- --:--:-- --:--:--  1533
  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
100 15.5M  100 15.5M    0     0  17.4M      0 --:--:-- --:--:-- --:--:-- 17.4M

+------------------+--------------------------------------------------------------------------------------------------------------------------------------------+
| Field            | Value                                                                                                                                      |
+------------------+--------------------------------------------------------------------------------------------------------------------------------------------+
| container_format | bare                                                                                                                                       |
| created_at       | 2023-01-31T21:12:56Z                                                                                                                       |
| disk_format      | raw                                                                                                                                        |
| file             | /v2/images/46a3eac1-7224-40bc-9083-f2f0cd122ba4/file                                                                                       |
| id               | 46a3eac1-7224-40bc-9083-f2f0cd122ba4                                                                                                       |
| min_disk         | 0                                                                                                                                          |
| min_ram          | 0                                                                                                                                          |
| name             | cirros                                                                                                                                     |
| owner            | 9f7e8fdc50f34b658cfaee9c48e5e12d                                                                                                           |
| properties       | os_hidden='False', owner_specified.openstack.md5='', owner_specified.openstack.object='images/cirros', owner_specified.openstack.sha256='' |
| protected        | False                                                                                                                                      |
| schema           | /v2/schemas/image                                                                                                                          |
| status           | queued                                                                                                                                     |
| tags             |                                                                                                                                            |
| updated_at       | 2023-01-31T21:12:56Z                                                                                                                       |
| visibility       | shared                                                                                                                                     |
+------------------+--------------------------------------------------------------------------------------------------------------------------------------------+

+--------------------------------------+--------+--------+
| ID                                   | Name   | Status |
+--------------------------------------+--------+--------+
| 46a3eac1-7224-40bc-9083-f2f0cd122ba4 | cirros | active |
+--------------------------------------+--------+--------+


(openstack)$ oc rsh ceph
sh-4.4$ ceph -s
r  cluster:
    id:     432d9a34-9cee-4109-b705-0c59e8973983
    health: HEALTH_OK

  services:
    mon: 1 daemons, quorum a (age 4h)
    mgr: a(active, since 4h)
    osd: 1 osds: 1 up (since 4h), 1 in (since 4h)

  data:
    pools:   5 pools, 160 pgs
    objects: 46 objects, 224 MiB
    usage:   247 MiB used, 6.8 GiB / 7.0 GiB avail
    pgs:     160 active+clean

sh-4.4$ rbd -p images ls
46a3eac1-7224-40bc-9083-f2f0cd122ba4
```
