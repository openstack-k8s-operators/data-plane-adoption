#!/bin/bash
{{ shell_header }}
{{ oc_header }}
{{ mariadb_copy_shell_vars_src }}

mkdir -p {{ mariadb_copy_tmp_dir }}
cd {{ mariadb_copy_tmp_dir }}

podman run -i --rm --userns=keep-id -u $UID -v $PWD:$PWD:z,rw -w $PWD $MARIADB_IMAGE bash <<EOF

# Note we do not want to dump the information and performance schema tables so we filter them
mysql -h ${SOURCE_MARIADB_IP} -u root "-p${SOURCE_DB_ROOT_PASSWORD}" -N -e 'show databases' | grep -E -v 'schema|mysql' | while read dbname; do
    echo "Dumping \${dbname}"
    mysqldump -h $SOURCE_MARIADB_IP -uroot "-p$SOURCE_DB_ROOT_PASSWORD" \
        --single-transaction --complete-insert --skip-lock-tables --lock-tables=0 \
        "\${dbname}" > "\${dbname}".sql
done

EOF