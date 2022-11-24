# MariaDB adoption procedure

This document will describe how to move the databases from a currently deployed TripleO
cluster (tested on a Standalone TripleO scenario) to the MariaDB instances in the OpenShift cluster
(tested also with OKD).

## Pre-checks

Make sure the environment is configured correctly,
we assume that the user followed the steps from one of the
[development scenarios](https://gitlab.cee.redhat.com/rhos-upgrades/data-plane-adoption-dev)
in particular this document used the
[Libvirt](https://gitlab.cee.redhat.com/rhos-upgrades/data-plane-adoption-dev/-/blob/main/libvirt_podified_standalone.md)
approach.

Also, make sure the 
[podified controlplane services](https://gitlab.cee.redhat.com/rhos-upgrades/data-plane-adoption/-/blob/main/openstack_control_plane_deployment.md)
are deployed correctly in the OpenShift cluster once these steps are working there should be one or more instances of
MariaDB running where we will import the databases from the TripleO deployment.

## Adoption

Let's start by creating the backup of the MariaDB server in the Standalone TripleO instance.

### Database backup

Connect to the TripleO deployment

```
# Connect to the Standalone TripleO deployment
ssh -i ~/.ssh/okdcluster_id_rsa root@10.0.0.4 # CentOS Stream
```

Install the dependencies required to be able to connect to the database server

```
yum install -y mysql
```

Connect as the stack user, fetch the database server root password and
check the server is working properly

```
# Login as the stack user
su - stack

# Get the MySQL passwrod string
cat ~/tripleo-standalone-passwords.yaml

# Store the password in a variable
mysql_pass=$(cat ~/tripleo-standalone-passwords.yaml | grep 'MysqlRootPassword' | tr -d ' ' | cut -d ':' -f 2)

# Make sure we can connect to the database
mysql -u root -p$mysql_pass -e "show databases"

# You should get something like
# mysql: [Warning] Using a password on the command line interface can be insecure.
# +--------------------+
# | Database           |
# +--------------------+
# | cinder             |
# | glance             |
# | information_schema |
# | keystone           |
# | mysql              |
# | nova               |
# | nova_api           |
# | nova_cell0         |
# | ovs_neutron        |
# | performance_schema |
# | placement          |
# +--------------------+
```

Once checked that we can connect to the database server, create a temporary folder
to store the DB dumps, and do a backup of each database individually (so we can restore each DB in a separate instance)
and a single file backup of all the databases (to import everything in the same instance).

All these databases will be restored in the OpenShift cluster, once the MariaDB operator is running correctly.

```
# So far is not important to export each database individually but we will bash it.
# Create a folder to store the databases
mkdir -p ~/dbdumps
cd ~/dbdumps

# Get the pass again
mysql_pass=$(cat ~/tripleo-standalone-passwords.yaml | grep 'MysqlRootPassword' | tr -d ' ' | cut -d ':' -f 2)

mysqlcheck --all-databases -u root -p$mysql_pass

# Get all the databases individually
mysql -u root -p$mysql_pass -N -e 'show databases' | while read dbname; do mysqldump -uroot -p$mysql_pass --single-transaction --complete-insert --column-statistics=0 --skip-lock-tables --lock-tables=0 "$dbname" > "$dbname".sql; done

# Get also all the databases in a single file
mysqldump -u root -p$mysql_pass --all-databases --single-transaction --complete-insert --column-statistics=0 --skip-lock-tables --lock-tables=0 --ignore-table=mysql.slow_log --ignore-table=mysql.general_log > tripleo_all_databases_backup.sql

# Go to the home folder
cd ~/

# Compress the DB backups folder
tar -czvf tripleo_databases.tar.gz -C ~/dbdumps .
```

Now we need to fetch this file from the Hypervisor and push it to the service guest (a VM with access to the OpenShift cluster API 'kubectl').

```
# Get the compressed file, so we can move it to a place with physical access to the MySQL instances in the OpenShiftcluster
## Go to root
exit
## Exit the Standalone TripleO guest
exit

# From the hypervisor
## Get the file
scp -i ~/.ssh/okdcluster_id_rsa root@10.0.0.4:/home/stack/tripleo_databases.tar.gz .

# Copy the file to the service guest VM (machine with access to the OpenShift cluster)
scp -i ~/.ssh/okdcluster_id_rsa ~/tripleo_databases.tar.gz root@10.0.0.253:/root/ 
```

Now we connect to the service machine and uncompress the file with the database backups.

```
# Connect to the machine with access to the OpenShift cluster resources
ssh -i ~/.ssh/okdcluster_id_rsa root@10.0.0.253

# Unzip all the backup files
mkdir -p ~/dbdumps
tar xvf ~/tripleo_databases.tar.gz -C ~/dbdumps
```

In the previous step if needed we can copy the backup directly between the
TripleO instance and the service node skipping the Hypervisor.

### Deploying the OpenStack controlplane services

For the MariaDB adoption there are two different ways
of testing the data migration between the OpenStack
deployment and the service hosting the MariaDB instance
in the OpenSHift data plane, choose one of the following options exclusively.

#### - Deploying only MariaDB (optional, required iff we will like to test the MariaDB adoption)

> **_NOTE:_**  Make sure the deployment steps for the podified controlplane ended successfully from the 
[Pre-checks section](https://gitlab.cee.redhat.com/rhos-upgrades/data-plane-adoption/-/blob/main/mariadb.md#pre-checks),
the following steps are not mandatory and are only needed if we would like to test only the
MariaDB adoption (exporting and importing the databases).
The next code snippet involves deploying the OpenStack MariaDB operator to have
a database instance where we can restore this backup.

```
# Install the MariaDB operator
# From the service node

# from install_yamls
# git clone https://github.com/openstack-k8s-operators/install_yamls.git
cd install_yamls
make crc_storage
make mariadb MARIADB_IMG=quay.io/openstack-k8s-operators/mariadb-operator-index:latest
make mariadb_deploy

# Make sure the pods are running correctly
# [root@service ~]# kubectl get pods -n openstack
# NAME        READY                                                  STATUS         RESTARTS   AGE
# openstack   mariadb-openstack                                      1/1  Running   0          71s
# openstack   mariadb-operator-controller-manager-79c65cf79c-gjmm9   2/2  Running   0          9h
# openstack   mariadb-operator-index-q7t74                           1/1  Running   0          9h
# openstack   mysql-client                                           1/1  Running   0          49m

# No restarts or problems should be reported so far
```

#### - Deploying all the OpenStack services using the openstack-operator

```
# Install all the services using the openstack-operator
# From the service node

# from install_yamls
# git clone https://github.com/openstack-k8s-operators/install_yamls.git
cd install_yamls
make crc_storage
make openstack

# Make sure the pods are running correctly
# [root@service ~]# oc get pods
# NAME                                                              READY   STATUS      RESTARTS        AGE
# a5d66980a2e4f0433baebf9e75676bc94fa31e8c12bee4c0155b0a24d7wq77p   0/1     Completed   0               22h
# cinder-operator-controller-manager-b478b7b88-bqhhm                2/2     Running     10 (120m ago)   22h
# controller-manager-5f67cc94d7-vbg8w                               1/1     Running     10 (120m ago)   22h
# glance-operator-controller-manager-b4d46c578-jgr6g                2/2     Running     10 (120m ago)   22h
# keystone-operator-controller-manager-85f4d8df7b-tw4zl             2/2     Running     10 (120m ago)   22h
# mariadb-openstack                                                 1/1     Running     0               22h
# mariadb-operator-controller-manager-85d4d9f9d8-97nq7              2/2     Running     10 (120m ago)   22h
# openstack-operator-controller-manager-8584fd4d74-zrtnv            2/2     Running     10 (120m ago)   22h
# openstack-operator-index-vq4wl                                    1/1     Running     0               22h
# placement-operator-controller-manager-77f8647454-n7b89            2/2     Running     10 (120m ago)   22h
# rabbitmq-server-0                                                 1/1     Running     0               21h
```

> **_NOTE:_**  The OpenStack operator deploys a set of services required for the
correct functioning of the next-gen cluster, there are cases where the deployed containers
pull the images from private containers registries that can potentially return
authentication errors like:
`Failed to pull image "registry.redhat.io/rhosp-rhel9/openstack-rabbitmq:17.0": rpc error: code = Unknown desc = unable to retrieve auth token: invalid username/password: unauthorized: Please login to the Red Hat Registry using your Customer Portal credentials.`

An example of a failed pod:

```
  Normal   Scheduled       3m40s                  default-scheduler  Successfully assigned openstack/rabbitmq-server-0 to worker0
  Normal   AddedInterface  3m38s                  multus             Add eth0 [10.101.0.41/23] from ovn-kubernetes
  Warning  Failed          2m16s (x6 over 3m38s)  kubelet            Error: ImagePullBackOff
  Normal   Pulling         2m5s (x4 over 3m38s)   kubelet            Pulling image "registry.redhat.io/rhosp-rhel9/openstack-rabbitmq:17.0"
  Warning  Failed          2m5s (x4 over 3m38s)   kubelet            Failed to pull image "registry.redhat.io/rhosp-rhel9/openstack-rabbitmq:17.0": rpc error: code  ... can be found here: https://access.redhat.com/RegistryAuthentication
  Warning  Failed          2m5s (x4 over 3m38s)   kubelet            Error: ErrImagePull
  Normal   BackOff         110s (x7 over 3m38s)   kubelet            Back-off pulling image "registry.redhat.io/rhosp-rhel9/openstack-rabbitmq:17.0"

```

In order to solve this issue we need to get a valid pull-secret from the official [Red Hat console site](https://console.redhat.com/openshift/install/pull-secret),
store this pull secret locally in a machine with access to the Kubernetes API (service node), and then run:

```
oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=<pull_secret_location.json>
```

The previous commmand will make available the authentication information in all the cluster's compute nodes,
then trigger a new pod deployment to pull the container image with:

```
kubectl delete pod rabbitmq-server-0 -n openstack
```

And the pod should be able to pull the image successfully.
For more inforation about what container registries requires what
type of authentication, check the [official docs](https://access.redhat.com/RegistryAuthentication).

### Restore the databases

The service machine has access to the Kubernetes cluster resources but there is no direct access
to the pods, so to be able to restore the databases we need to deploy a pod with the backups and
from there execute the restore tasks.

```
# Fetch the secrets from the current OpenSHift cluster, to get the MariaDB root password
kubectl get secrets
kubectl describe secret osp-secret
mysql_pass=$(kubectl get secret osp-secret -o jsonpath="{.data.DbRootPassword}" | base64 --decode)

# Type the pass
echo $mysql_pass

```

In this case, the password is `12345678` but this is likely to change in the near future.

See that the pods do not have any external IP exposed, if there is one, then you could potentially
restore the backups directly.

```
# The is no external IP to the MySQL server
kubectl get service

# [root@service ~]# kubectl get service
# NAME                                                  TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)     AGE
# mariadb-operator-controller-manager-metrics-service   ClusterIP   172.30.202.57    <none>        8443/TCP    17m
# mariadb-operator-index                                ClusterIP   172.30.142.140   <none>        50051/TCP   18m
# openstack                                             ClusterIP   172.30.214.192   <none>        3306/TCP    17m

# MySQL by default listens in the 3306 port so lets try to connect there

```

If there are no services published lets get the MariaDB pod information:

```
[root@service ~]# kubectl describe pod mariadb-openstack
Name:         mariadb-openstack
Namespace:    openstack
Priority:     0
Node:         worker0/10.0.0.2
Start Time:   Wed, 23 Nov 2022 14:18:13 +0000
Labels:       app=mariadb
              cr=mariadb-openstack
              owner=mariadb-operator
Annotations:  k8s.ovn.org/pod-networks:
                {"default":{"ip_addresses":["10.101.0.42/23"],"mac_address":"0a:58:0a:65:00:2a","gateway_ips":["10.101.0.1"],"ip_address":"10.101.0.42/23"...
              k8s.v1.cni.cncf.io/network-status:
                [{
                    "name": "ovn-kubernetes",
                    "interface": "eth0",
```

Create a pod using the same MariaDB version as the one in the TripleO deployment.

```
# Let's run a MariaDB container so we can connect to the database and make the import we need
kubectl run mariadb-client --image mariadb:10.5 -it --rm --restart=Never -- /bin/bash
```

Now we need to copy the backups to this running pod, open a new terminal in the service guest VM and run:

```
# In another terminal push the DB backup to our MySQL client pod
kubectl cp ~/tripleo_databases.tar.gz openstack/mariadb-client:/
```

Now the final steps must be executed from the MariaDB container.

Unzip the compressed file

```
# From the MariaDB container run
rm -rf /dbdumps
mkdir /dbdumps
tar xvf /tripleo_databases.tar.gz -C /dbdumps
```

Test the connection to the MariaDB instance using the password fetched from the secrets.

```
# Test the connection and see the databases
# You can use service IP (172.30.214.192) or the pod IP if there is no service advertised (10.101.0.42)
mysql -h 172.30.214.192 -uroot -p12345678 -e 'SHOW databases;'
```

Restore all the databases of each individually.

```
# Do the restore, and check things are where they are supposed to be
mysql -h 172.30.214.192 -uroot -p12345678 < /dbdumps/tripleo_all_databases_backup.sql
```

Depending on the MySQL client version and the version of the mysqldump you might encounter
the following error.

```
# Depending on the mysqldump version you might hit
ERROR 1556 (HY000) at line 780: You can't use locks with log tables
```

If so, remove the UNLOCKs from the log tables and retry.

```
# Try
cat /dbdumps/tripleo_all_databases_backup.sql | grep -v LOCK | grep -v UNLOCK > /dbdumps/tripleo_all_databases_backup_NoLock.sql
mysql -h 172.30.214.192 -uroot -p12345678 < /dbdumps/tripleo_all_databases_backup_NoLock.sql
```

## Post-checks

From the MariaDB client container check that the databases are restored correctly.

```
# Check the databases again from the mariadb container
mysql -h 172.30.214.192 -uroot -p12345678 -e 'SHOW databases;'
root@mariadb-client:/# mysql -h 172.30.170.247 -uroot -p12345678 -e 'SHOW databases;'

# +--------------------+
# | Database           |
# +--------------------+
# | cinder             |
# | glance             |
# | information_schema |
# | keystone           |
# | mysql              |
# | nova               |
# | nova_api           |
# | nova_cell0         |
# | ovs_neutron        |
# | performance_schema |
# | placement          |
# +--------------------+

# Databases should be moved :)
```

Some additional debug commands.

```
# Some debug commands
kubectl get customresourcedefinitions
kubectl describe crd mariadbdatabases.mariadb.openstack.org
kubectl describe crd mariadbs.mariadb.openstack.org
```
