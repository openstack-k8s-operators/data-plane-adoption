{{ mariadb_copy_shell_vars_dst }}
# Check that the databases were imported correctly
# use 'oc exec' and 'mysql -rs' to maintain formatting

set +u
. ~/.source_cloud_exported_variables_default
set -u

dbs=$(oc exec openstack-galera-0 -c galera -- mysql -rs -uroot -p"${PODIFIED_DB_ROOT_PASSWORD['super']}" -e 'SHOW databases;')
echo $dbs | grep -Eq '\bkeystone\b' && echo "OK" || echo "CHECK FAILED"

# ensure neutron db is renamed from ovs_neutron
echo $dbs | grep -Eq '\bneutron\b'
echo "${PULL_OPENSTACK_CONFIGURATION_DATABASES[@]}" | grep -Eq '\bovs_neutron\b' && echo "OK" || echo "CHECK FAILED"

# ensure default cell is renamed to $DEFAULT_CELL_NAME, and the cell UUIDs retained intact
novadb_mapped_cells=$(oc exec openstack-galera-0 -c galera -- mysql -rs -uroot -p"${PODIFIED_DB_ROOT_PASSWORD['super']}" \
  nova_api -e 'select uuid,name,transport_url,database_connection,disabled from cell_mappings;')
uuidf='\S{8,}-\S{4,}-\S{4,}-\S{4,}-\S{12,}'
left_behind=$(comm -23 \
  <(echo $PULL_OPENSTACK_CONFIGURATION_NOVADB_MAPPED_CELLS | grep -oE " $uuidf \S+") \
  <(echo $novadb_mapped_cells | tr -s "| " " " | grep -oE " $uuidf \S+"))
changed=$(comm -13 \
  <(echo $PULL_OPENSTACK_CONFIGURATION_NOVADB_MAPPED_CELLS | grep -oE " $uuidf \S+") \
  <(echo $novadb_mapped_cells | tr -s "| " " " | grep -oE " $uuidf \S+"))
test $(grep -Ec ' \S+$' <<<$left_behind) -eq 1 && echo "OK" || echo "CHECK FAILED"
default=$(grep -E ' default$' <<<$left_behind)
test $(grep -Ec ' \S+$' <<<$changed) -eq 1 && echo "OK" || echo "CHECK FAILED"
grep -qE " $(awk '{print $1}' <<<$default) ${DEFAULT_CELL_NAME}$" <<<$changed && echo "OK" || echo "CHECK FAILED"

for CELL in $(echo $CELLS | grep -v default); do
  set +u
  . ~/.source_cloud_exported_variables_$CELL
  set -u
  RCELL=$CELL
  [ "$CELL" = "default" ] && RCELL=$DEFAULT_CELL_NAME
  # ensure nova cells' db are extracted to separate db servers and renamed from nova to nova_cell<X>
  c1dbs=$(oc exec openstack-$CELL-galera-0 -c galera -- mysql -rs -uroot -p${PODIFIED_DB_ROOT_PASSWORD[$RCELL]} -e 'SHOW databases;')
  echo $c1dbs | grep -Eq "\bnova_${CELL}\b" && echo "OK" || echo "CHECK FAILED"

  # ensure the registered Compute service name has not changed
  novadb_svc_records=$(oc exec openstack-$CELL-galera-0 -c galera -- mysql -rs -uroot -p${PODIFIED_DB_ROOT_PASSWORD[$RCELL]} \
    nova_$CELL -e "select host from services where services.binary='nova-compute' order by host asc;")
  diff -Z <(echo $novadb_svc_records) <(echo ${PULL_OPENSTACK_CONFIGURATION_NOVA_COMPUTE_HOSTNAMES[$CELL]}) && echo "OK" || echo "CHECK FAILED"
done
