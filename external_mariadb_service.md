External MariaDB service creation
=================================

Here we create a Service resource inside OpenShift that will direct
MariaDB connections to the external MariaDB running on controllers.

Prerequisites
-------------

Define shell variables:

```
# The IP of MariaDB running on controller machines. Must be reachable
# and connectable on port 3306 from OpenShift pods.
EXTERNAL_MARIADB_IP=192.168.24.3

# MariaDB root password on the original deployment.
DB_ROOT_PASSWORD=SomePassword
```

Pre-checks
----------

Adoption
--------

Create Service and Endpoints resources for external MariaDB:

```
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: openstack
  labels:
    app: mariadb
  name: openstack
spec:
  clusterIP: None
  type: ClusterIP

---

apiVersion: v1
kind: Endpoints
metadata:
 name: openstack
subsets:
 - addresses:
     - ip: $EXTERNAL_MARIADB_IP
EOF
```

Set DB root password:

```
oc set data secret/osp-secret "DbRootPassword=$DB_ROOT_PASSWORD"
```

Post-checks
-----------
