{{ shell_header }}
{{ oc_header }}
{{ mariadb_copy_shell_vars_src }}
{{ mariadb_copy_shell_vars_dst }}
oc run mariadb-client --image $MARIADB_IMAGE -i --rm --restart=Never -- \
mysql -h "${PODIFIED_MARIADB_IP}" -uroot "-p${PODIFIED_DB_ROOT_PASSWORD}" -e 'SHOW databases;' \
  | grep -q keystone

# ensure neutron db is renamed from ovs_neutron
oc run mariadb-client --image $MARIADB_IMAGE -i --rm --restart=Never -- \
mysql -h "${PODIFIED_MARIADB_IP}" -uroot "-p${PODIFIED_DB_ROOT_PASSWORD}" -e 'SHOW databases;' \
  | grep -q neutron
echo $PULL_OPENSTACK_CONFIGURATION_DATABASES | grep ' ovs_neutron '

# ensure nova cell1 db is extracted to a separate db server and renamed from nova to nova_cell1
oc run mariadb-client --image $MARIADB_IMAGE -i --rm --restart=Never -- \
mysql -h "${PODIFIED_CELL1_MARIADB_IP}" -uroot "-p${PODIFIED_DB_ROOT_PASSWORD}" -e 'SHOW databases;' \
  | grep -q nova_cell1

# ensure default cell renamed to cell1, and the cell UUIDs retained intact
NOVADB_MAPPED_CELLS=$(oc rsh mariadb-openstack mysql -uroot "-p$PODIFIED_DB_ROOT_PASSWORD" \
  nova_api -e 'select uuid,name,transport_url,database_connection,disabled from cell_mappings;')
uuidf='\S{8,}-\S{4,}-\S{4,}-\S{4,}-\S{12,}'
left_behind=$(comm -23 \
  <(echo $PULL_OPENSTACK_CONFIGURATION_NOVADB_MAPPED_CELLS | grep -oE " $uuidf \S+") \
  <(echo $NOVADB_MAPPED_CELLS | tr -s "| " " " | grep -oE " $uuidf \S+"))
changed=$(comm -13 \
  <(echo $PULL_OPENSTACK_CONFIGURATION_NOVADB_MAPPED_CELLS | grep -oE " $uuidf \S+") \
  <(echo $NOVADB_MAPPED_CELLS | tr -s "| " " " | grep -oE " $uuidf \S+"))
test $(grep -Ec ' \S+$' <<<$left_behind) -eq 1
default=$(grep -E ' default$' <<<$left_behind)
test $(grep -Ec ' \S+$' <<<$changed) -eq 1
grep -qE " $(awk '{print $1}' <<<$default) cell1$" <<<$changed

# ensure the registered Nova compute service name has not changed
oc rsh mariadb-openstack-cell1 mysql -uroot "-p$PODIFIED_DB_ROOT_PASSWORD" nova_cell1 \
  -e "select host from services where services.binary='nova-compute';" \
  | grep -qF '| standalone.localdomain |'
echo $PULL_OPENSTACK_CONFIGURATION_NOVA_COMPUTE_HOSTNAMES | grep -qF ' standalone.localdomain'

# ensure the VM instance cell ID has not changed
oc rsh mariadb-openstack mysql -uroot "-p$PODIFIED_DB_ROOT_PASSWORD" nova_api -e \
  "select cell_id from instance_mappings;" | grep -qF -m1 ' 2 |'
echo $PULL_OPENSTACK_CONFIGURATION_NOVADB_INSTANCES_CELL_IDS | grep -q -m1 ' 2$'