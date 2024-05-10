#!/bin/bash
{{ oc_header }}
{{ mariadb_copy_shell_vars_src }}

# Create a dump of the original databases

oc rsh mariadb-copy-data << EOF
  for CELL in $(echo $CELLS); do
    mysql -h"${SOURCE_MARIADB_IP[\$CELL]}" -uroot -p"${SOURCE_DB_ROOT_PASSWORD[\$CELL]}" \
    -N -e "show databases" | grep -E -v "schema|mysql|gnocchi" | \
    while read dbname; do
      echo "Dumping \$CELL cell \${dbname}";
      mysqldump -h"${SOURCE_MARIADB_IP[\$CELL]}" -uroot -p"${SOURCE_DB_ROOT_PASSWORD[\$CELL]}" \
        --single-transaction --complete-insert --skip-lock-tables --lock-tables=0 \
        "\${dbname}" > /backup/"\${CELL}.\${dbname}".sql;
    done
  done
EOF
