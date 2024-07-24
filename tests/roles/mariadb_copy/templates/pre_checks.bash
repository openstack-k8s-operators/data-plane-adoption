#!/bin/bash
{{ mariadb_copy_shell_vars_dst }}

# Test connection to control plane "upcall" and cells DBs (show databases)
for CELL in $(echo $RENAMED_CELLS); do
  oc run mariadb-client --image $MARIADB_IMAGE -i --rm --restart=Never -- \
     mysql -rsh "$PODIFIED_MARIADB_IP[$CELL]" -uroot -p"$PODIFIED_DB_ROOT_PASSWORD[$CELL]" -e 'SHOW databases;'
done
