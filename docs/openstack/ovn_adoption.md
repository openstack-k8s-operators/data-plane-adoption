# OVN data migration

This document describes how to move OVN northbound and southbound databases
from the original OpenStack deployment to ovsdb-server instances running in the
OpenShift cluster.

## Rationale

While it may be argued that the podified Neutron ML2/OVN driver and OVN northd
service will reconstruct the databases on startup, the reconstruction may be
time consuming on large existing clusters. The procedure below allows to speed
up data migration and avoid unnecessary data plane disruptions due to
incomplete OpenFlow table contents.

## Prerequisites

* Make sure the previous Adoption steps have been performed successfully.
  * The OpenStackControlPlane resource must be already created at this point.
  * NetworkAttachmentDefinition CRDs for the original cluster are already
    defined. Specifically, *openstack/internalapi* network is defined.
  * Podified MariaDB and RabbitMQ may already run. Neutron and OVN are not
    running yet.
  * Original OVN is older or equal to the podified version.
  * There must be network routability between:
    * The adoption host and the original OVN.
    * The adoption host and the podified OVN.

## Variables

Define the shell variables used in the steps below. The values are
just illustrative, use values that are correct for your environment:

```bash
OVSDB_IMAGE=quay.io/tripleozedcentos9/openstack-ovn-base:current-tripleo
EXTERNAL_OVSDB_IP=172.17.1.49

# ssh commands to reach the original controller machines
CONTROLLER_SSH="ssh -F ~/director_standalone/vagrant_ssh_config vagrant@standalone"

# ssh commands to reach the original compute machines
COMPUTE_SSH="ssh -F ~/director_standalone/vagrant_ssh_config vagrant@standalone"
```

## Procedure

- Stop OVN northd on all original cluster controllers.

```bash
${CONTROLLER_SSH} sudo systemctl stop tripleo_ovn_cluster_northd.service
```

- Backup OVN databases.

```bash
client="podman run -i --rm --userns=keep-id -u $UID -v $PWD:$PWD:z,rw -w $PWD $OVSDB_IMAGE ovsdb-client"
${client} backup tcp:$EXTERNAL_OVSDB_IP:6641 > ovs-nb.db
${client} backup tcp:$EXTERNAL_OVSDB_IP:6642 > ovs-sb.db
```

- Start podified OVN services prior to database import.

```yaml
oc patch openstackcontrolplane openstack --type=merge --patch '
spec:
  ovn:
    enabled: true
    template:
      ovnDBCluster:
        ovndbcluster-nb:
          containerImage: quay.io/tripleozedcentos9/openstack-ovn-nb-db-server:current-tripleo
          dbType: NB
          storageRequest: 10G
          networkAttachment: internalapi
        ovndbcluster-sb:
          containerImage: quay.io/tripleozedcentos9/openstack-ovn-sb-db-server:current-tripleo
          dbType: SB
          storageRequest: 10G
          networkAttachment: internalapi
      ovnNorthd:
        containerImage: quay.io/tripleozedcentos9/openstack-ovn-northd:current-tripleo
        networkAttachment: internalapi
'
```

- Fetch podified OVN IP addresses.

```bash
PODIFIED_OVSDB_NB_IP=$(kubectl get po ovsdbserver-nb-0 -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/networks-status}' | jq 'map(. | select(.name=="openstack/internalapi"))[0].ips[0]' | tr -d '"')
PODIFIED_OVSDB_SB_IP=$(kubectl get po ovsdbserver-sb-0 -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/networks-status}' | jq 'map(. | select(.name=="openstack/internalapi"))[0].ips[0]' | tr -d '"')
```

- Restore database backup to podified OVN database servers.

```bash
podman run -it --rm --userns=keep-id -u $UID -v $PWD:$PWD:z,rw -w $PWD $OVSDB_IMAGE bash -c "ovsdb-client restore tcp:$PODIFIED_OVSDB_NB_IP:6641 < ovs-nb.db"
podman run -it --rm --userns=keep-id -u $UID -v $PWD:$PWD:z,rw -w $PWD $OVSDB_IMAGE bash -c "ovsdb-client restore tcp:$PODIFIED_OVSDB_SB_IP:6642 < ovs-sb.db"
```

- Check that podified OVN databases contain objects from backup, e.g.:

```bash
oc exec -it ovsdbserver-nb-0 -- ovn-nbctl show
oc exec -it ovsdbserver-sb-0 -- ovn-sbctl list Chassis
```

- Switch ovn-remote on compute nodes to point to the new podified database.

```bash
${COMPUTE_SSH} sudo podman exec -it ovn_controller ovs-vsctl set open . external_ids:ovn-remote=tcp:$PODIFIED_OVSDB_SB_IP:6642
```

You should now see the following warning in the `ovn_controller` container logs:

```
2023-03-16T21:40:35Z|03095|ovsdb_cs|WARN|tcp:172.17.1.50:6642: clustered database server has stale data; trying another server
```

- Reset RAFT state for all compute ovn-controller instances.

```bash
${COMPUTE_SSH} sudo podman exec -it ovn_controller ovn-appctl -t ovn-controller sb-cluster-state-reset
```

This should complete connection of the controller process to the new remote. See in logs:

```
2023-03-16T21:42:31Z|03134|main|INFO|Resetting southbound database cluster state
2023-03-16T21:42:33Z|03135|reconnect|INFO|tcp:172.17.1.50:6642: connected
```

- Alternatively, just restart ovn-controller on original compute nodes.

```bash
$ ${COMPUTE_SSH} sudo systemctl restart tripleo_ovn_controller.service
```
