# #!/bin/bash
# {{ shell_header }}
# {{ oc_header }}
# {{ mariadb_copy_shell_vars }}
# {{ ssh_to_ospdo_openstackclient }}
# {{ ssh_to_ospdo_osp_controller }}
# "
# mkdir -p {{ mariadb_copy_tmp_dir }}
# cd {{ mariadb_copy_tmp_dir }}
# mysql -h ${SOURCE_MARIADB_IP} -u root "-p${SOURCE_DB_ROOT_PASSWORD}" -N -e 'show databases' | grep -E -v 'schema|mysql' | while read dbname; do
#     echo "Dumping \${dbname}"
#     mysqldump -h $SOURCE_MARIADB_IP -uroot "-p$SOURCE_DB_ROOT_PASSWORD" \
#         --single-transaction --complete-insert --skip-lock-tables --lock-tables=0 \
#         "\${dbname}" > "{{ mariadb_copy_tmp_dir }}/\${dbname}".sql
# done
# " # ctrl0 cli
# '" # ssh_openstackclient & controller