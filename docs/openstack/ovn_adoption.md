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

- Make sure the previous Adoption steps have been performed successfully.
  - The OpenStackControlPlane resource must be already created at this point.
  - NetworkAttachmentDefinition CRDs for the original cluster are already
    defined. Specifically, _openstack/internalapi_ network is defined.
  - Podified MariaDB and RabbitMQ may already run. Neutron and OVN are not
    running yet.
  - Original OVN is older or equal to the podified version.
  - There must be network routability between:
    - The adoption host and the original OVN.
    - The adoption host and the podified OVN.

## Variables

Define the shell variables used in the steps below. The values are
just illustrative, use values that are correct for your environment:

```bash
STORAGE_CLASS_NAME=crc-csi-hostpath-provisioner
OVSDB_IMAGE=quay.io/podified-antelope-centos9/openstack-ovn-base:current-podified
SOURCE_OVSDB_IP=172.17.1.49

# ssh commands to reach the original controller machines
CONTROLLER_SSH="ssh -F ~/director_standalone/vagrant_ssh_config vagrant@standalone"

# ssh commands to reach the original compute machines
COMPUTE_SSH="ssh -F ~/director_standalone/vagrant_ssh_config vagrant@standalone"
```

The real value of the `SOURCE_OVSDB_IP` can be get from the puppet generated configs:

```bash
grep -rI 'ovn_[ns]b_conn' /var/lib/config-data/puppet-generated/
```

## Procedure

- Stop OVN northd on all original cluster controllers.

```bash
${CONTROLLER_SSH} sudo systemctl stop tripleo_ovn_cluster_northd.service
```
- Prepare the OVN DBs copy dir and the adoption helper pod (pick the storage requests to fit the OVN databases sizes)

```yaml
oc apply -f - <<EOF
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ovn-data
spec:
  storageClassName: $STORAGE_CLASS_NAME
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: ovn-copy-data
  annotations:
    openshift.io/scc: anyuid
  labels:
    app: adoption
spec:
  containers:
  - image: $OVSDB_IMAGE
    command: [ "sh", "-c", "sleep infinity"]
    name: adoption
    volumeMounts:
    - mountPath: /backup
      name: ovn-data
  securityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop: ALL
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  volumes:
  - name: ovn-data
    persistentVolumeClaim:
      claimName: ovn-data
EOF
```

- Wait for the pod to come up

```bash
oc wait --for=condition=Ready pod/ovn-copy-data --timeout=30s
```

- Backup OVN databases.

```bash
oc exec ovn-copy-data -- bash -c "ovsdb-client backup tcp:$SOURCE_OVSDB_IP:6641 > /backup/ovs-nb.db"
oc exec ovn-copy-data -- bash -c "ovsdb-client backup tcp:$SOURCE_OVSDB_IP:6642 > /backup/ovs-sb.db"
```

- Start podified OVN database services prior to import.

```yaml
oc patch openstackcontrolplane openstack --type=merge --patch '
spec:
  ovn:
    enabled: true
    template:
      ovnDBCluster:
        ovndbcluster-nb:
          dbType: NB
          storageRequest: 10G
          networkAttachment: internalapi
        ovndbcluster-sb:
          dbType: SB
          storageRequest: 10G
          networkAttachment: internalapi
'
```
- Wait for the OVN DB pods reaching the running phase.

```bash
oc wait --for=jsonpath='{.status.phase}'=Running pod --selector=service=ovsdbserver-nb
oc wait --for=jsonpath='{.status.phase}'=Running pod --selector=service=ovsdbserver-sb
```

- Fetch podified OVN IP addresses on the clusterIP service network.

```bash
PODIFIED_OVSDB_NB_IP=$(oc get svc --selector "statefulset.kubernetes.io/pod-name=ovsdbserver-nb-0" -ojsonpath='{.items[0].spec.clusterIP}')
PODIFIED_OVSDB_SB_IP=$(oc get svc --selector "statefulset.kubernetes.io/pod-name=ovsdbserver-sb-0" -ojsonpath='{.items[0].spec.clusterIP}')
```

- Upgrade database schema for the backup files.

```bash
oc exec ovn-copy-data -- bash -c "ovsdb-client get-schema tcp:$PODIFIED_OVSDB_NB_IP:6641 > /backup/ovs-nb.ovsschema && ovsdb-tool convert /backup/ovs-nb.db /backup/ovs-nb.ovsschema"
oc exec ovn-copy-data -- bash -c "ovsdb-client get-schema tcp:$PODIFIED_OVSDB_SB_IP:6642 > /backup/ovs-sb.ovsschema && ovsdb-tool convert /backup/ovs-sb.db /backup/ovs-sb.ovsschema"
```

- Restore database backup to podified OVN database servers.

```bash
oc exec ovn-copy-data -- bash -c "ovsdb-client restore tcp:$PODIFIED_OVSDB_NB_IP:6641 < /backup/ovs-nb.db"
oc exec ovn-copy-data -- bash -c "ovsdb-client restore tcp:$PODIFIED_OVSDB_SB_IP:6642 < /backup/ovs-sb.db"
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

- Finally, you can start `ovn-northd` service that will keep OVN northbound and southbound databases in sync.

```yaml
oc patch openstackcontrolplane openstack --type=merge --patch '
spec:
  ovn:
    enabled: true
    template:
      ovnNorthd:
        networkAttachment: internalapi
'
```

- Delete the ovn-data pod and persistent volume claim with OVN databases backup (consider making a snapshot of it, before deleting)

```bash
oc delete pod ovn-copy-data
oc delete pvc ovn-data
```