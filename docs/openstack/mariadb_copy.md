# MariaDB data copy

This document describes how to move the databases from the original
OpenStack deployment to the MariaDB instances in the OpenShift
cluster.

## Prerequisites

* Make sure the previous Adoption steps have been performed successfully.

  * The OpenStackControlPlane resource must be already created at this point.

  * Podified MariaDB and RabbitMQ are running. No other podified
    control plane services are running.

  * There must be network routability between:

    * The adoption host and the original MariaDB.

    * The adoption host and the podified MariaDB.

    * *Note that this routability requirement may change in the
      future, e.g. we may require routability from original MariaDB to
      podified MariaDB*.

## Variables

Define the shell variables used in the steps below. The values are
just illustrative, use values which are correct for your environment:

```
PODIFIED_MARIADB_IP=$(oc get -o yaml pod mariadb-openstack | grep podIP: | awk '{ print $2; }')
MARIADB_IMAGE=quay.io/tripleozedcentos9/openstack-mariadb:current-tripleo

# Use your environment's values for these:
EXTERNAL_MARIADB_IP=192.168.24.3
EXTERNAL_DB_ROOT_PASSWORD=$(cat ~/tripleo-standalone-passwords.yaml | grep ' MysqlRootPassword:' | awk -F ': ' '{ print $2; }')
PODIFIED_DB_ROOT_PASSWORD=12345678
```

## Pre-checks

* Test connection to the original DB (show databases):

  ```
  podman run -i --rm --userns=keep-id -u $UID -v $PWD:$PWD:z,rw -w $PWD $MARIADB_IMAGE \
      mysql -h "$EXTERNAL_MARIADB_IP" -uroot "-p$EXTERNAL_DB_ROOT_PASSWORD" -e 'SHOW databases;'
  ```

* Run mysqlcheck on the original DB:

  ```
  podman run -i --rm --userns=keep-id -u $UID -v $PWD:$PWD:z,rw -w $PWD $MARIADB_IMAGE \
      mysqlcheck --all-databases -h $EXTERNAL_MARIADB_IP -u root "-p$EXTERNAL_DB_ROOT_PASSWORD"
  ```

* Test connection to podified DB (show databases):

  ```
  oc run mariadb-client --image $MARIADB_IMAGE -i --rm --restart=Never -- \
      mysql -h "$PODIFIED_MARIADB_IP" -uroot "-p$PODIFIED_DB_ROOT_PASSWORD" -e 'SHOW databases;'
  ```

## Procedure - stopping control plane services

From each controller node it is necessary to stop the
control-plane services to avoid inconsistencies in the
data migrated for the data-plane adoption procedure.

1- Connect to all the controller nodes and stop the control
plane services.

2- Stop the services.

```bash

# Configure SSH variables to stop the services
# in each controller node. For example:

CONTROLLER1_SSH="ssh -F $ENV_DIR/director_standalone/vagrant_ssh_config vagrant@standalone"
CONTROLLER2_SSH=":"
CONTROLLER3_SSH=":"

# Update the services list to be stoped

ServicesToStop=("tripleo_horizon.service"
                "tripleo_keystone.service"
                "tripleo_cinder_api.service"
                "tripleo_glance_api.service"
                "tripleo_neutron_api.service"
                "tripleo_nova_api.service"
                "tripleo_placement_api.service")

echo "Stopping the OpenStack services"

for service in ${ServicesToStop[*]}; do
    echo "Stopping the service: $service in each controller node"
    $CONTROLLER1_SSH sudo systemctl stop $service
    $CONTROLLER2_SSH sudo systemctl stop $service
    $CONTROLLER3_SSH sudo systemctl stop $service
done
```

3- Make sure all the services are stopped

## Procedure - data copy

* Create a temporary folder to store DB dumps and make sure it's the
  working directory for the following steps:

  ```
  mkdir ~/adoption-db
  cd ~/adoption-db
  ```

* Create a dump of the original databases:

  ```
  podman run -i --rm --userns=keep-id -u $UID -v $PWD:$PWD:z,rw -w $PWD $MARIADB_IMAGE bash <<EOF

  mysql -h $EXTERNAL_MARIADB_IP -u root "-p$EXTERNAL_DB_ROOT_PASSWORD" -N -e 'show databases' | while read dbname; do
      echo "Dumping \$dbname"
      mysqldump -h $EXTERNAL_MARIADB_IP -uroot "-p$EXTERNAL_DB_ROOT_PASSWORD" \
          --single-transaction --complete-insert --skip-lock-tables --lock-tables=0 \
          --databases "\$dbname" \
          > "\$dbname".sql
  done

  EOF
  ```

* Restore the databases from .sql files into the podified MariaDB:

  ```
  for dbname in cinder glance keystone nova_api nova_cell0 nova ovs_neutron placement; do
      echo "Restoring $dbname"
      oc run mariadb-client --image $MARIADB_IMAGE -i --rm --restart=Never -- \
         mysql -h "$PODIFIED_MARIADB_IP" -uroot "-p$PODIFIED_DB_ROOT_PASSWORD" < "$dbname.sql"
  done
  ```

## Post-checks

* Check that the databases were imported correctly:

  ```
  oc run mariadb-client --image $MARIADB_IMAGE -i --rm --restart=Never -- \
     mysql -h "$PODIFIED_MARIADB_IP" -uroot "-p$PODIFIED_DB_ROOT_PASSWORD" -e 'SHOW databases;'
  ```
