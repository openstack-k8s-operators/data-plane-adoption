 {{ shell_header }}
{{ oc_header }}
{{ mariadb_copy_shell_vars }}
oc run mariadb-client --image $MARIADB_IMAGE -i --rm --restart=Never -- \
mysql -h "${PODIFIED_MARIADB_IP}" -uroot "-p${PODIFIED_DB_ROOT_PASSWORD}" -e 'SHOW databases;' \
    | grep keystone
# ensure neutron db is renamed from ovs_neutron
oc run mariadb-client --image $MARIADB_IMAGE -i --rm --restart=Never -- \
mysql -h "${PODIFIED_MARIADB_IP}" -uroot "-p${PODIFIED_DB_ROOT_PASSWORD}" -e 'SHOW databases;' \
    | grep neutron
# ensure nova cell1 db is extracted to a separate db server and renamed from nova to nova_cell1
oc run mariadb-client --image $MARIADB_IMAGE -i --rm --restart=Never -- \
mysql -h "${PODIFIED_CELL1_MARIADB_IP}" -uroot "-p${PODIFIED_DB_ROOT_PASSWORD}" -e 'SHOW databases;' \
    | grep nova_cell1