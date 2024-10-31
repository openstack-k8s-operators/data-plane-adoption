#!/bin/bash
{{ shell_header }}
{{ oc_header }}
{{ mariadb_copy_shell_vars_src }}
{{ mariadb_copy_shell_vars_dst }}

oc rsh -n "{{ org_namespace }}" mariadb-copy-data << EOF
  # db schemas to rename on import
  declare -A db_name_map
  db_name_map['nova']='nova_cell1'
  db_name_map['ovs_neutron']='neutron'
  db_name_map['ironic-inspector']='ironic_inspector'

  # db servers to import into
  declare -A db_server_map
  db_server_map['default']=${PODIFIED_MARIADB_IP}
  db_server_map['nova_cell1']=${PODIFIED_CELL1_MARIADB_IP}

  # db server root password map
  declare -A db_server_password_map
  db_server_password_map['default']=${PODIFIED_DB_ROOT_PASSWORD}
  db_server_password_map['nova_cell1']=${PODIFIED_DB_ROOT_PASSWORD}

  cd /backup
  for db_file in \$(ls *.sql); do
    db_name=\$(echo \${db_file} | awk -F'.' '{ print \$1; }')
    if [[ -v "db_name_map[\${db_name}]" ]]; then
      echo "renaming \${db_name} to \${db_name_map[\${db_name}]}"
      db_name=\${db_name_map[\${db_name}]}
    fi
    db_server=\${db_server_map["default"]}
    if [[ -v "db_server_map[\${db_name}]" ]]; then
      db_server=\${db_server_map[\${db_name}]}
    fi
    db_password=\${db_server_password_map['default']}
    if [[ -v "db_server_password_map[\${db_name}]" ]]; then
      db_password=\${db_server_password_map[\${db_name}]}
    fi
    echo "creating \${db_name} in \${db_server}"
    mysql -h"\${db_server}" -uroot -p"\${db_password}" -e \
      "CREATE DATABASE IF NOT EXISTS \${db_name} DEFAULT \
      CHARACTER SET ${CHARACTER_SET} DEFAULT COLLATE ${COLLATION};"
    echo "importing \${db_name} into \${db_server}"
    mysql -h "\${db_server}" -uroot -p"\${db_password}" "\${db_name}" < "\${db_file}"
  done

  mysql -h "\${db_server_map['default']}" -uroot -p"\${db_server_password_map['default']}" -e \
    "update nova_api.cell_mappings set name='cell1' where name='default';"
  mysql -h "\${db_server_map['nova_cell1']}" -uroot -p"\${db_server_password_map['nova_cell1']}" -e \
    "delete from nova_cell1.services where host not like '%nova-cell1-%' and services.binary != 'nova-compute';"
EOF
