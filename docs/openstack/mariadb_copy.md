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
      future, e.g. we may require routability from the original MariaDB to
      podified MariaDB*.

* Podman package is installed

## Variables

Define the shell variables used in the steps below. The values are
just illustrative, use values that are correct for your environment:

```
PODIFIED_MARIADB_IP=$(oc get -o yaml pod mariadb-openstack | grep podIP: | awk '{ print $2; }')
MARIADB_IMAGE=quay.io/podified-antelope-centos9/openstack-mariadb:current-podified

SOURCE_DB_ROOT_PASSWORD=$(cat ~/tripleo-standalone-passwords.yaml | grep ' MysqlRootPassword:' | awk -F ': ' '{ print $2; }')
PODIFIED_DB_ROOT_PASSWORD=$(oc get -o json secret/osp-secret | jq -r .data.DbRootPassword | base64 -d)

# Replace with your environment's MariaDB IP and SSH commands to reach controller machines:
SOURCE_MARIADB_IP=192.168.122.100
CONTROLLER1_SSH="ssh -i ~/install_yamls/out/edpm/ansibleee-ssh-key-id_rsa root@192.168.122.100"
CONTROLLER2_SSH=""
CONTROLLER3_SSH=""
```

## Pre-checks

* Test connection to the original DB (show databases):

  ```
  podman run -i --rm --userns=keep-id -u $UID -v $PWD:$PWD:z,rw -w $PWD $MARIADB_IMAGE \
      mysql -h "$SOURCE_MARIADB_IP" -uroot "-p$SOURCE_DB_ROOT_PASSWORD" -e 'SHOW databases;'
  ```

* Run mysqlcheck on the original DB to look for things that are not OK:

  ```
  podman run -i --rm --userns=keep-id -u $UID -v $PWD:$PWD:z,rw -w $PWD $MARIADB_IMAGE \
      mysqlcheck --all-databases -h $SOURCE_MARIADB_IP -u root "-p$SOURCE_DB_ROOT_PASSWORD" | grep -v OK
  ```

* Test connection to podified DB (show databases):

  ```
  oc run mariadb-client --image $MARIADB_IMAGE -i --rm --restart=Never -- \
      mysql -h "$PODIFIED_MARIADB_IP" -uroot "-p$PODIFIED_DB_ROOT_PASSWORD" -e 'SHOW databases;'
  ```

## Procedure - stopping control plane services

From each controller node, it is necessary to stop the
control-plane services to avoid inconsistencies in the
data migrated for the data-plane adoption procedure.

1- Connect to all the controller nodes and stop the control
plane services.

2- Stop the services.

3- Make sure all the services are stopped

These steps can be automated with a simple script that relies on the previously
defined `CONTROLLER#_SSH` environmental variables:

```bash

# Update the services list to be stopped

ServicesToStop=("tripleo_horizon.service"
                "tripleo_keystone.service"
                "tripleo_cinder_api.service"
                "tripleo_cinder_api_cron.service"
                "tripleo_cinder_scheduler.service"
                "tripleo_glance_api.service"
                "tripleo_neutron_api.service"
                "tripleo_nova_api.service"
                "tripleo_placement_api.service")

echo "Stopping systemd OpenStack services"
for service in ${ServicesToStop[*]}; do
    for i in {1..3}; do
        SSH_CMD=CONTROLLER${i}_SSH
        if [ ! -z "${!SSH_CMD}" ]; then
            echo "Stopping the $service in controller $i"
            ${!SSH_CMD} sudo systemctl stop $service
        fi
    done
done

echo "Checking systemd OpenStack services"
for service in ${ServicesToStop[*]}; do
    for i in {1..3}; do
        SSH_CMD=CONTROLLER${i}_SSH
        if [ ! -z "${!SSH_CMD}" ]; then
            echo "Checking status of $service in controller $i"
            if ! ${!SSH_CMD} systemctl show $service | grep ActiveState=inactive >/dev/null; then
               echo "ERROR: Service $service still running on controller $i"
            fi
        fi
    done
done
```


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

  mysql -h $SOURCE_MARIADB_IP -u root "-p$SOURCE_DB_ROOT_PASSWORD" -N -e 'show databases' | while read dbname; do
      echo "Exporting \$dbname"
      mysqldump -h $SOURCE_MARIADB_IP -uroot "-p$SOURCE_DB_ROOT_PASSWORD" \
          --single-transaction --complete-insert --skip-lock-tables --lock-tables=0 \
          --databases "\$dbname" \
          > "\$dbname".sql
  done

  EOF
  ```

* Restore the databases from .sql files into the podified MariaDB:

  ```
  for dbname in cinder glance keystone nova_api nova_cell0 nova ovs_neutron placement; do
      echo "Importing $dbname"
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
