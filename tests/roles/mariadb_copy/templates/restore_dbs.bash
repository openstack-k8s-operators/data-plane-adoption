#!/bin/bash
{{ mariadb_copy_shell_vars_src }}
{{ mariadb_copy_shell_vars_dst }}

# Restore the databases from .sql files into the control plane MariaDB

for CELL in $(echo $CELLS); do
  RCELL=$CELL
  [ "$CELL" = "default" ] && RCELL=$DEFAULT_CELL_NAME
  oc rsh mariadb-copy-data << EOF
    # db schemas to rename on import
    declare -A db_name_map
    db_name_map['nova']="nova_$RCELL"
    db_name_map['ovs_neutron']='neutron'
    db_name_map['ironic-inspector']='ironic_inspector'

    # cells' db schemas to import for cells
    declare -A db_cell_map
    db_cell_map['nova']="nova_$DEFAULT_CELL_NAME"
    db_cell_map["nova_$RCELL"]="nova_$RCELL"
    # Omit importing cells' cell0 DBs as we cannot consolidate them
    # db_cell_map["nova_cell0"]="nova_$RCELL"

    # db servers to import into
    declare -A db_server_map
    db_server_map['default']=${PODIFIED_MARIADB_IP['super']}
    db_server_map["nova"]=${PODIFIED_MARIADB_IP[$DEFAULT_CELL_NAME]}
    db_server_map["nova_$RCELL"]=${PODIFIED_MARIADB_IP[$RCELL]}

    # db server root password map
    declare -A db_server_password_map
    db_server_password_map['default']=${PODIFIED_DB_ROOT_PASSWORD['super']}
    db_server_password_map["nova"]=${PODIFIED_DB_ROOT_PASSWORD[$DEFAULT_CELL_NAME]}
    db_server_password_map["nova_$RCELL"]=${PODIFIED_DB_ROOT_PASSWORD[$RCELL]}

    cd /backup
    for db_file in \$(ls ${CELL}.*.sql); do
      db_name=\$(echo \${db_file} | awk -F'.' '{ print \$2; }')
      # Only import cells' DBs and omit everything else
      [[ "$CELL" != "default" && ! -v "db_cell_map[\${db_name}]" ]] && continue
      # Route databases for importing, when extracting cell's / non-cell's DBs from 'default' cell
      if [[ "$CELL" == "default" && -v "db_cell_map[\${db_name}]" ]] ; then
        target=$DEFAULT_CELL_NAME
      elif [[ "$CELL" == "default" && ! -v "db_cell_map[\${db_name}]" ]] ; then
        target=super # 'upcall'
      else
        target=$RCELL
      fi
      renamed_db_file="\${target}_new.\${db_name}.sql"
      mv -f \${db_file} \${renamed_db_file}
      if [[ -v "db_name_map[\${db_name}]" ]]; then
        echo "renaming $CELL cell \${db_name} to \$target \${db_name_map[\${db_name}]}"
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
      echo "creating $CELL cell \${db_name} in \$target \${db_server}"
      mysql -h"\${db_server}" -uroot "-p\${db_password}" -e \
        "CREATE DATABASE IF NOT EXISTS \${db_name} DEFAULT \
        CHARACTER SET ${CHARACTER_SET} DEFAULT COLLATE ${COLLATION};"
      echo "importing $CELL cell \${db_name} into \$target \${db_server} from \${renamed_db_file}"
      mysql -h "\${db_server}" -uroot "-p\${db_password}" "\${db_name}" < "\${renamed_db_file}"
    done

    if [ "$CELL" = "default" ] ; then
      mysql -h "\${db_server_map['default']}" -uroot -p"\${db_server_password_map['default']}" -e \
        "update nova_api.cell_mappings set name='$DEFAULT_CELL_NAME' where name='default';"
    fi
    mysql -h "\${db_server_map["nova_$RCELL"]}" -uroot -p"\${db_server_password_map["nova_$RCELL"]}" -e \
      "delete from nova_${RCELL}.services where host not like '%nova_${RCELL}-%' and services.binary != 'nova-compute';"
EOF
done
