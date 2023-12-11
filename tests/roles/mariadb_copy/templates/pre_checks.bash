#!/bin/bash
{{ shell_header }}
{{ oc_header }}
{{ mariadb_copy_shell_vars }}
{{ ssh_to_ospdo_openstackclient }}
{{ ssh_to_ospdo_osp_controller }}
# Test connection to the original DB (show databases)
podman run -i --rm --userns=keep-id -u $UID -v $PWD:$PWD:z,rw -w $PWD $MARIADB_IMAGE \
    mysql -h "$SOURCE_MARIADB_IP" -uroot "-p$SOURCE_DB_ROOT_PASSWORD" -e 'SHOW databases;'
# Run mysqlcheck on the original DB to look for things that are not OK
podman run -i --rm --userns=keep-id -u $UID -v $PWD:$PWD:z,rw -w $PWD $MARIADB_IMAGE \
    mysqlcheck --all-databases -h $SOURCE_MARIADB_IP -u root "-p$SOURCE_DB_ROOT_PASSWORD"
# Test connection to podified DBs (show databases)
oc run mariadb-client --image $MARIADB_IMAGE -i --rm --restart=Never -- \
    mysql -h "$PODIFIED_MARIADB_IP" -uroot "-p$PODIFIED_DB_ROOT_PASSWORD" -e 'SHOW databases;'
oc run mariadb-client --image $MARIADB_IMAGE -i --rm --restart=Never -- \
    mysql -h "$PODIFIED_CELL1_MARIADB_IP" -uroot "-p$PODIFIED_DB_ROOT_PASSWORD" -e 'SHOW databases;'
'"