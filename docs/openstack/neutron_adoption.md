# Neutron adoption

Adopting Neutron means that an existing `OpenStackControlPlane` CR, where Neutron
is supposed to be disabled, should be patched to start the service with the
configuration parameters provided by the source environment.

When the procedure is over, the expectation is to see the `NeutronAPI` service
up and running: the `Keystone endpoints` should be updated and the same backend
of the source Cloud will be available. If the conditions above are met, the
adoption is considered concluded.

This guide also assumes that:

1. A `TripleO` environment (the source Cloud) is running on one side;
2. A `SNO` / `CodeReadyContainers` is running on the other side.

## Prerequisites

* Previous Adoption steps completed. Notably, MariaDB and Keystone
  should be already adopted.

## Procedure - Neutron adoption

As already done for [Keystone](https://github.com/openstack-k8s-operators/data-plane-adoption/blob/main/keystone_adoption.md), the Neutron Adoption follows the same pattern.

Patch OpenStackControlPlane to deploy Neutron:

```
oc patch openstackcontrolplane openstack --type=merge --patch '
spec:
  neutron:
    enabled: true
    template:
      databaseInstance: openstack
      secret: osp-secret
      externalEndpoints:
      - endpoint: internal
        ipAddressPool: internalapi
        loadBalancerIPs:
        - 172.17.0.80
      networkAttachments:
      - internalapi
'
```

## Post-checks

### Inspect the resulting neutron pods

```bash
NEUTRON_API_POD=`oc get pods -l service=neutron | tail -n 1 | cut -f 1 -d' '`
oc exec -t $NEUTRON_API_POD -c neutron-api -- cat /etc/neutron/neutron.conf
```

### Check that Neutron API service is registered in Keystone

```bash
openstack service list | grep network
```

```bash
openstack endpoint list | grep network

| 6a805bd6c9f54658ad2f24e5a0ae0ab6 | regionOne | neutron      | network      | True    | public    | http://neutron-public-openstack.apps-crc.testing  |
| b943243e596847a9a317c8ce1800fa98 | regionOne | neutron      | network      | True    | internal  | http://neutron-internal.openstack.svc:9696        |
| f97f2b8f7559476bb7a5eafe3d33cee7 | regionOne | neutron      | network      | True    | admin     | http://192.168.122.99:9696                        |
```

### Create sample resources

We can now test that user can create networks, subnets, ports, routers etc.

```bash
openstack network create net
openstack subnet create --network net --subnet-range 10.0.0.0/24 subnet
openstack router create router
```

NOTE: this page should be expanded to include information on SR-IOV adoption.
