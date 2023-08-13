# MariaDB data copy

This document describes how to move the databases from the original
OpenStack deployment to the MariaDB instances in the OpenShift
cluster.

## Prerequisites

* Make sure the previous Adoption steps have been performed successfully.

  * The OpenStackControlPlane resource must be already created at this point.

  * Podified MariaDB and RabbitMQ are running. No other podified
    control plane services are running.

  * OpenStack services have been stopped

  * There must be network routability between:

    * The adoption host and the original MariaDB.

    * The adoption host and the podified MariaDB.

    * *Note that this routability requirement may change in the
      future, e.g. we may require routability from the original MariaDB to
      podified MariaDB*.

* Podman package is installed

* `CONTROLLER1_SSH`, `CONTROLLER2_SSH`, and `CONTROLLER3_SSH` are configured.

## Variables

Define the shell variables used in the steps below. The values are
just illustrative, use values that are correct for your environment:

```
PODIFIED_MARIADB_IP=$(oc get -o yaml pod mariadb-openstack | grep podIP: | awk '{ print $2; }')
MARIADB_IMAGE=quay.io/podified-antelope-centos9/openstack-mariadb:current-podified

SOURCE_DB_ROOT_PASSWORD=$(cat ~/tripleo-standalone-passwords.yaml | grep ' MysqlRootPassword:' | awk -F ': ' '{ print $2; }')
PODIFIED_DB_ROOT_PASSWORD=$(oc get -o json secret/osp-secret | jq -r .data.DbRootPassword | base64 -d)
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
