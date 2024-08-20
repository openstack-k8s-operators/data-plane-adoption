#!/bin/bash
{{ shell_header }}
if [[ "$ospdo_src" != "true" ]]; then
    {{ oc_header }}
fi
{{ mariadb_copy_shell_vars_src }}

# Note Filter the information and performance schema tables
# Gnocchi is no longer used as a metric store, skip dumping gnocchi database as well
oc rsh {{ mariadb_clnt_pod_name }} << EOF
  mysql -h"${SOURCE_MARIADB_IP}" -uroot -p"${SOURCE_DB_ROOT_PASSWORD}" \
  -N -e "show databases" | grep -E -v "schema|mysql|gnocchi|aodh" | \
  while read dbname; do
    echo "Dumping \${dbname}";
    mysqldump -h"${SOURCE_MARIADB_IP}" -uroot -p"${SOURCE_DB_ROOT_PASSWORD}" \
      --single-transaction --complete-insert --skip-lock-tables --lock-tables=0 \
      "\${dbname}" > /backup/"\${dbname}".sql;
   done
EOF
