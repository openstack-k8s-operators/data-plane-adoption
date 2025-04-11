#!/bin/bash
{{ oc_header }}
{{ mariadb_copy_shell_vars_src }}

# Create a dump of the original databases
# Note Filter the information and performance schema tables
# Gnocchi is no longer used as a metric store, skip dumping gnocchi database as well
# Migrating Aodh alarms from previous release is not supported, hence skip aodh database
for CELL in $(echo $CELLS); do
  oc rsh mariadb-copy-data << EOF
    mysql -h"${SOURCE_MARIADB_IP[$CELL]}" -uroot -p"${SOURCE_DB_ROOT_PASSWORD[$CELL]}" \
    -N -e "show databases" | grep -E -v "schema|mysql|gnocchi|aodh" | \
    while read dbname; do
      echo "Dumping $CELL cell \${dbname}";
      mysqldump -h"${SOURCE_MARIADB_IP[$CELL]}" -uroot -p"${SOURCE_DB_ROOT_PASSWORD[$CELL]}" \
        --single-transaction --complete-insert --skip-lock-tables --lock-tables=0 \
        "\${dbname}" > /backup/"${CELL}.\${dbname}".sql;
    done
EOF
done
