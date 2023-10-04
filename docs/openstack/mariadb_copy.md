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
MARIADB_IMAGE=quay.io/podified-antelope-centos9/openstack-mariadb:current-podified

PODIFIED_MARIADB_IP=$(oc get svc --selector "cr=mariadb-openstack" -ojsonpath='{.items[0].spec.clusterIP}')
PODIFIED_CELL1_MARIADB_IP=$(oc get svc --selector "cr=mariadb-openstack-cell1" -ojsonpath='{.items[0].spec.clusterIP}')
PODIFIED_DB_ROOT_PASSWORD=$(oc get -o json secret/osp-secret | jq -r .data.DbRootPassword | base64 -d)

# Replace with your environment's MariaDB IP:
SOURCE_MARIADB_IP=192.168.122.100
SOURCE_DB_ROOT_PASSWORD=$(cat ~/tripleo-standalone-passwords.yaml | grep ' MysqlRootPassword:' | awk -F ': ' '{ print $2; }')

# The CHARACTER_SET and collation should match the source DB
# if the do not then it will break foreign key relationships
# for any tables that are created in the future as part of db sync
CHARACTER_SET=utf8
COLLATION=utf8_general_ci

```

## Pre-checks

* Test connection to the original DB (show databases):

  ```
  podman run -i --rm --userns=keep-id -u $UID $MARIADB_IMAGE \
      mysql -h "$SOURCE_MARIADB_IP" -uroot "-p$SOURCE_DB_ROOT_PASSWORD" -e 'SHOW databases;'
  ```

* Run mysqlcheck on the original DB to look for things that are not OK:

  ```
  podman run -i --rm --userns=keep-id -u $UID $MARIADB_IMAGE \
      mysqlcheck --all-databases -h $SOURCE_MARIADB_IP -u root "-p$SOURCE_DB_ROOT_PASSWORD" | grep -v OK
  ```

* Test connection to podified DBs (show databases):

  ```
  oc run mariadb-client --image $MARIADB_IMAGE -i --rm --restart=Never -- \
      mysql -h "$PODIFIED_MARIADB_IP" -uroot "-p$PODIFIED_DB_ROOT_PASSWORD" -e 'SHOW databases;'
  oc run mariadb-client --image $MARIADB_IMAGE -i --rm --restart=Never -- \
      mysql -h "$PODIFIED_CELL1_MARIADB_IP" -uroot "-p$PODIFIED_DB_ROOT_PASSWORD" -e 'SHOW databases;'
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

  # Note we do not want to dump the information and performance schema tables so we filter them
  mysql -h ${SOURCE_MARIADB_IP} -u root "-p${SOURCE_DB_ROOT_PASSWORD}" -N -e 'show databases' | grep -E -v 'schema|mysql' | while read dbname; do
      echo "Dumping \${dbname}"
      mysqldump -h $SOURCE_MARIADB_IP -uroot "-p$SOURCE_DB_ROOT_PASSWORD" \
          --single-transaction --complete-insert --skip-lock-tables --lock-tables=0 \
          "\${dbname}" > "\${dbname}".sql
  done

  EOF
  ```

* Restore the databases from .sql files into the podified MariaDB:

  ```
  # db schemas to rename on import
  declare -A db_name_map
  db_name_map["nova"]="nova_cell1"
  db_name_map["ovs_neutron"]="neutron"

  # db servers to import into
  declare -A db_server_map
  db_server_map["default"]=${PODIFIED_MARIADB_IP}
  db_server_map["nova_cell1"]=${PODIFIED_CELL1_MARIADB_IP}

  # db server root password map
  declare -A db_server_password_map
  db_server_password_map["default"]=${PODIFIED_DB_ROOT_PASSWORD}
  db_server_password_map["nova_cell1"]=${PODIFIED_DB_ROOT_PASSWORD}

  all_db_files=$(ls *.sql)
  for db_file in ${all_db_files}; do
      db_name=$(echo ${db_file} | awk -F'.' '{ print $1; }')
      if [[ -v "db_name_map[${db_name}]" ]]; then
          echo "renaming ${db_name} to ${db_name_map[${db_name}]}"
          db_name=${db_name_map[${db_name}]}
      fi
      db_server=${db_server_map["default"]}
      if [[ -v "db_server_map[${db_name}]" ]]; then
          db_server=${db_server_map[${db_name}]}
      fi
      db_password=${db_server_password_map["default"]}
      if [[ -v "db_server_password_map[${db_name}]" ]]; then
          db_password=${db_server_password_map[${db_name}]}
      fi
      echo "creating ${db_name} in ${db_server}"
      container_name=$(echo "mariadb-client-${db_name}-create" | sed 's/_/-/g')
      oc run ${container_name} --image ${MARIADB_IMAGE} -i --rm --restart=Never -- \
          mysql -h "${db_server}" -uroot "-p${db_password}" << EOF
  CREATE DATABASE IF NOT EXISTS ${db_name} DEFAULT CHARACTER SET ${CHARACTER_SET} DEFAULT COLLATE ${COLLATION};
  EOF
      echo "importing ${db_name} into ${db_server}"
      container_name=$(echo "mariadb-client-${db_name}-restore" | sed 's/_/-/g')
      oc run ${container_name} --image ${MARIADB_IMAGE} -i --rm --restart=Never -- \
          mysql -h "${db_server}" -uroot "-p${db_password}" "${db_name}" < "${db_file}"
  done
  ```

## Post-checks

* Check that the databases were imported correctly:

  ```
  oc run mariadb-client --image $MARIADB_IMAGE -i --rm --restart=Never -- \
  mysql -h "${PODIFIED_MARIADB_IP}" -uroot "-p${PODIFIED_DB_ROOT_PASSWORD}" -e 'SHOW databases;' \
      | grep keystone
  # ensure neutron db is renamed from ovs_neutron
  oc run mariadb-client --image $MARIADB_IMAGE -i --rm --restart=Never -- \
  mysql -h "${PODIFIED_MARIADB_IP}" -uroot "-p${PODIFIED_DB_ROOT_PASSWORD}" -e 'SHOW databases;' \
      | grep neutron
  # ensure nova cell1 db is extracted to a separate db server and renamed from nova to nova_cell1
  oc run mariadb-client --image $MARIADB_IMAGE -i --rm --restart=Never -- \
  mysql -h "${PODIFIED_CELL1_MARIADB_IP}" -uroot "-p${PODIFIED_DB_ROOT_PASSWORD}" -e 'SHOW databases;' \
      | grep nova_cell1
  ```

* During the pre/post checks the pod `mariadb-client` might have returned a pod security warning
  related to the `restricted:latest` security context constraint. This is due to default security
  context constraints and will not prevent pod creation by the admission controller. You'll see a
  warning for the short-lived pod but it will not interfere with functionality.
  For more info [visit here](https://learn.redhat.com/t5/DO280-Red-Hat-OpenShift/About-pod-security-standards-and-warnings/m-p/32502)
