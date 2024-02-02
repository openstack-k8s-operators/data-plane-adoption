#!/bin/bash
{{ shell_header }}
{{ oc_header }}
{{ mariadb_copy_shell_vars_src }}
{{ mariadb_copy_shell_vars_dst }}

# Test connection to podified DBs (show databases)
oc run mariadb-client --image $MARIADB_IMAGE -i --rm --restart=Never -- \
    mysql -rsh "$PODIFIED_MARIADB_IP" -uroot "-p$PODIFIED_DB_ROOT_PASSWORD" -e 'SHOW databases;'
oc run mariadb-client --image $MARIADB_IMAGE -i --rm --restart=Never -- \
    mysql -rsh "$PODIFIED_CELL1_MARIADB_IP" -uroot "-p$PODIFIED_DB_ROOT_PASSWORD" -e 'SHOW databases;'