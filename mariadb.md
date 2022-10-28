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

### Deploy MariaDB

The next step involves deploying the OpenStack MariaDB operator to have
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
