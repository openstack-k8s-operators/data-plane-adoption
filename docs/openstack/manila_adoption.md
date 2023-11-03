# Manila adoption

WIP

## Prerequisites

WIP

## Procedure - Neutron adoption

As already done for [Keystone](https://github.com/openstack-k8s-operators/data-plane-adoption/blob/main/keystone_adoption.md), the Neutron Adoption follows the same pattern.

Patch OpenStackControlPlane to deploy Manila:

```
cat << __EOF__ > ~/manila.patch
spec:
  manila:
    enabled: true
    apiOverride:
      route: {}
    template:
      databaseInstance: openstack
      secret: osp-secret
      manilaAPI:
        override:
          service:
            internal:
              metadata:
                annotations:
                  metallb.universe.tf/address-pool: internalapi
                  metallb.universe.tf/allow-shared-ip: internalapi
                  metallb.universe.tf/loadBalancerIPs: 172.17.0.80
              spec:
                type: LoadBalancer
    template:
      manilaAPI:
        replicas: 1
        customServiceConfig: |
          [DEFAULT]
          enabled_share_protocols = cephfs
      manilaScheduler:
        replicas: 1
      manilaShares:
        share1:
          replicas: 1
          customServiceConfig: |
            [DEFAULT]
            enabled_share_backends = cephfs
            [cephfs]
            driver_handles_share_servers=False
            share_backend_name=cephfs
            share_driver=manila.share.drivers.cephfs.driver.CephFSDriver
            cephfs_conf_path=/etc/ceph/ceph.conf
            cephfs_auth_id=openstack
            cephfs_cluster_name=ceph
            cephfs_volume_mode=0755
            cephfs_protocol_helper_type=CEPHFS
__EOF__


oc patch openstackcontrolplane openstack --type=merge --patch-file=~/manila.patch
```

## Post-checks

### Inspect the resulting manila service pods

```bash
oc get pods -l service=manila 
```

### Check that Manila API service is registered in Keystone

```bash
openstack service list | grep manila
```

```bash
openstack endpoint list | grep manila

| 1164c70045d34b959e889846f9959c0e | regionOne | manila       | share        | True    | internal  | http://manila-internal.openstack.svc:8786/v1/%(project_id)s        |
| 63e89296522d4b28a9af56586641590c | regionOne | manilav2     | sharev2      | True    | public    | https://manila-public-openstack.apps-crc.testing/v2                |
| af36c57adcdf4d50b10f484b616764cc | regionOne | manila       | share        | True    | public    | https://manila-public-openstack.apps-crc.testing/v1/%(project_id)s |
| d655b4390d7544a29ce4ea356cc2b547 | regionOne | manilav2     | sharev2      | True    | internal  | http://manila-internal.openstack.svc:8786/v2                       |
```

### Verify resources

We can now test the health of the service

```bash
openstack share service list
openstack share pool list --detail
```

We can check on existing workloads

```bash
openstack share list
openstack share snapshot list
```

We can create further resources
```bash
openstack share create cephfs 10 --snapshot mysharesnap --name myshareclone
```



