#!/bin/bash
{{ shell_header }}
{{ oc_header }}
{{ mariadb_copy_shell_vars_src }}
{{ mariadb_copy_shell_vars_dst }}
cd {{ mariadb_copy_tmp_dir }}

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
oc exec -it mariadb-openstack -- mysql --user=root --password=${db_server_password_map["default"]} -e \
    "update nova_api.cell_mappings set name='cell1' where name='default';"
oc exec -it mariadb-openstack-cell1 -- mysql --user=root --password=${db_server_password_map["default"]} -e \
    "delete from nova_cell1.services where host not like '%nova-cell1-%' and services.binary != 'nova-compute';"
