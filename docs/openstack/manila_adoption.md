# Manila adoption

OpenStack Manila is the Shared File Systems service. It provides OpenStack 
users with a self-service API to create and manage file shares. File 
shares (or simply, "shares"), are built for concurrent read/write access by 
any number of clients. This, coupled with the inherent elasticity of the 
underlying storage makes the Shared File Systems service essential in
cloud environments with require RWX ("read write many") persistent storage.

## Networking

File shares in OpenStack are accessed directly over a network. Hence, it is
essential to plan the networking of the cloud to create a successful and 
sustainable orchestration layer for shared file systems.

Manila supports two levels of storage networking abstractions - one where 
users can directly control the networking for their respective file shares; 
and another where the storage networking is configured by the OpenStack 
administrator. It is important to ensure that the networking in the Red Hat 
OpenStack Platform 17.1 matches the network plans for your new cloud after 
adoption. This ensures that tenant workloads remain connected to 
storage through the adoption process, even as the control plane suffers a 
minor interruption. Manila's control plane services are not in the data 
path; and shutting down the API, scheduler and share manager services will 
not impact access to existing shared file systems.

Typically, storage and storage device management networks are separate. 
Manila services only need access to the storage device management network. 
For example, if a Ceph cluster was used in the deployment, the "storage" 
network refers to the Ceph cluster's public network, and Manila's share 
manager service needs to be able to reach it.

## Prerequisites

* Ensure that manila systemd services (api, cron, scheduler) are 
  [stopped](stop_openstack_services.md#stopping-control-plane-services).
* Ensure that manila pacemaker services ("openstack-manila-share") are 
  [stopped](stop_openstack_services.md#stopping-control-plane-services).
* Ensure that the [database migration](mariadb_copy.md) has completed.
* Ensure that OpenShift nodes where `manila-share` service will be deployed 
  can reach the management network that the storage system is in.
* Ensure that services such as [keystone](keystone_adoption.md) 
  and [memcached](backend_services_deployment.md) are available prior to 
  adopting manila services.
* If tenant-driven networking was enabled (`driver_handles_share_servers=True`),
  ensure that [neutron](neutron_adoption.md) has been deployed prior to 
  adopting manila services.

## Procedure - Manila adoption

### Copying configuration from the RHOSP 17.1 deployment

Define the `CONTROLLER1_SSH` environment variable, if it [hasn't been 
defined](stop_openstack_services.md#variables) already. Then copy the 
configuration file from RHOSP 17.1 for reference.

```
$CONTROLLER1_SSH cat /var/lib/config-data/puppet-generated/manila/etc/manila/manila.conf | awk '!/^ *#/ && NF' > ~/manila.conf
```

Review this configuration, alongside any configuration changes that were noted
since RHOSP 17.1. Not all of it makes sense to bring into the new cloud 
environment:

<!--- TODO link config diff tables for RHOSP 17.1 (Wallaby) to RHOSP 18 (Antelope) --->

- The manila operator is capable of setting up database related configuration
  (`[database]`), service authentication (`auth_strategy`,
  `[keystone_authtoken]`), message bus configuration 
  (`transport_url`, `control_exchange`), the default paste config
  (`api_paste_config`) and inter-service communication configuration (`
  [neutron]`, `[nova]`, `[cinder]`, `[glance]` `[oslo_messaging_*]`). So 
  all of these can be ignored.
- Ignore the `osapi_share_listen` configuration. In RHOSP 18, we rely on 
  OpenShift's routes and ingress.
- Pay attention to policy overrides. In RHOSP 18, manila ships with a secure 
  default RBAC, and overrides may not be necessary. Please review RBAC 
  defaults by using the [Oslo policy generator](https://docs.openstack.org/oslo.policy/latest/cli/oslopolicy-policy-generator.html)
  tool. If a custom policy is necessary, you must provide it as a 
  `ConfigMap`. The following sample spec illustrates how a 
  `ConfigMap` called `manila-policy` can be set up with the contents of a 
  file called `policy.yaml`.

```yaml
  spec:
    manila:
      enabled: true
      template:
        manilaAPI:
          customServiceConfig: |
             [oslo_policy]
             policy_file=/etc/manila/policy.yaml
        extraMounts:
        - extraVol:
          - extraVolType: Undefined
            mounts:
            - mountPath: /etc/manila/
              name: policy
              readOnly: true
            propagation:
            - ManilaAPI
            volumes:
            - name: policy
              projected:
                sources:
                - configMap:
                    name: manila-policy
                    items:
                      - key: policy
                        path: policy.yaml

```
- The Manila API service needs the `enabled_share_protocols` option to be 
  added in the `customServiceConfig` section in `manila: template: manilaAPI`.
- If you had scheduler overrides, add them to the `customServiceConfig` 
  section in `manila: template: manilaScheduler`.
- If you had multiple storage backend drivers configured with RHOSP 17.1, 
  you will need to split them up when deploying RHOSP 18. Each storage 
  backend driver needs to use its own instance of the `manila-share` 
  service.
- If a storage backend driver needs a custom container image, find it on the 
  [RHOSP Ecosystem Catalog](https://catalog.redhat.com/software/containers/search?gs&q=manila)
  and set `manila: template: manilaShares: <custom name> : containerImage` 
  value. The following example illustrates multiple storage backend drivers, 
  using custom container images.

```yaml
  spec:
    manila:
      enabled: true
      template:
        manilaAPI:
          customServiceConfig: |
            [DEFAULT]
            enabled_share_protocols = nfs
          replicas: 3
        manilaScheduler:
          replicas: 3
        manilaShares:
         netapp:
           customServiceConfig: |
             [DEFAULT]
             debug = true
             enabled_share_backends = netapp
             [netapp]
             driver_handles_share_servers = False
             share_backend_name = netapp
             share_driver = manila.share.drivers.netapp.common.NetAppDriver
             netapp_storage_family = ontap_cluster
             netapp_transport_type = http
           replicas: 1
         pure:
            customServiceConfig: |
             [DEFAULT]
             debug = true
             enabled_share_backends=pure-1
             [pure-1]
             driver_handles_share_servers = False
             share_backend_name = pure-1
             share_driver = manila.share.drivers.purestorage.flashblade.FlashBladeShareDriver
             flashblade_mgmt_vip = 203.0.113.15
             flashblade_data_vip = 203.0.10.14
            containerImage: registry.connect.redhat.com/purestorage/openstack-manila-share-pure-rhosp-18-0
            replicas: 1
```

- If providing sensitive information, such as passwords, hostnames and 
  usernames, it is recommended to use OpenShift secrets, and the
  `customServiceConfigSecrets` key. An example:

```bash

cat << __EOF__ > ~/netapp_secrets.conf

[netapp]
netapp_server_hostname = 203.0.113.10
netapp_login = fancy_netapp_user
netapp_password = secret_netapp_password
netapp_vserver = mydatavserver
__EOF__

oc create secret generic osp-secret-manila-netapp --from-file=~/netapp_secrets.conf -n openstack
```

- `customConfigSecrets` can be used in any service, the following is a 
  config example using the secret we created as above. 

```yaml
  spec:
    manila:
      enabled: true
      template:
        < . . . >
        manilaShares:
         netapp:
           customServiceConfig: |
             [DEFAULT]
             debug = true
             enabled_share_backends = netapp
             [netapp]
             driver_handles_share_servers = False
             share_backend_name = netapp
             share_driver = manila.share.drivers.netapp.common.NetAppDriver
             netapp_storage_family = ontap_cluster
             netapp_transport_type = http
           customServiceConfigSecrets:
             - osp-secret-manila-netapp
           replicas: 1
    < . . . >
```

- If you need to present extra files to any of the services, you can use 
  `extraMounts`. For example, when using ceph, you'd need Manila's ceph 
  user's keyring file as well as the `ceph.conf` configuration file 
  available. These are mounted via `extraMounts` as done with the example 
  below.
- Ensure that the names of the backends (`share_backend_name`) remain as they 
  did on RHOSP 17.1.
- It is recommended to set the replica count of the `manilaAPI` service and 
  the `manilaScheduler` service to 3. You should ensure to set the replica 
  count of the `manilaShares` service/s to 1.   
- Ensure that the appropriate storage management network is specified in the 
  `manilaShares` section. The example below connects the `manilaShares` 
  instance with the CephFS backend driver to the `storage` network. 

### Deploying the manila control plane 

Patch OpenStackControlPlane to deploy Manila; here's an example that uses 
Native CephFS:

```yaml
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
        replicas: 3
        customServiceConfig: |
          [DEFAULT]
          enabled_share_protocols = cephfs
      manilaScheduler:
        replicas: 3
      manilaShares:
        cephfs:
          replicas: 1
          customServiceConfig: |
            [DEFAULT]
            enabled_share_backends = tripleo_ceph
            [tripleo_ceph]
            driver_handles_share_servers=False
            share_backend_name=tripleo_ceph
            share_driver=manila.share.drivers.cephfs.driver.CephFSDriver
            cephfs_conf_path=/etc/ceph/ceph.conf
            cephfs_auth_id=openstack
            cephfs_cluster_name=ceph
            cephfs_volume_mode=0755
            cephfs_protocol_helper_type=CEPHFS
          networkAttachments:
              - storage
__EOF__
```

```bash
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
