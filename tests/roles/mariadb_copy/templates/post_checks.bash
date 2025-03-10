{{ mariadb_copy_shell_vars_dst }}
# Check that the databases were imported correctly
# use 'oc exec' and 'mysql -rs' to maintain formatting

set +u
. ~/.source_cloud_exported_variables_default
set -u
dbs=$(oc exec openstack-galera-0 -n $NAMESPACE -c galera -- mysql -rs -uroot -p"${PODIFIED_DB_ROOT_PASSWORD['super']}" -e 'SHOW databases;')
echo $dbs | grep -Eq '\bkeystone\b' && echo "OK" || echo "CHECK FAILED"
echo $dbs | grep -Eq '\bneutron\b' && echo "OK" || echo "CHECK FAILED"
echo "${PULL_OPENSTACK_CONFIGURATION_DATABASES[@]}" | grep -Eq '\bovs_neutron\b' && echo "OK" || echo "CHECK FAILED" # <1>
novadb_mapped_cells=$(oc exec openstack-galera-0 -n $NAMESPACE -c galera -- mysql -rs -uroot -p"${PODIFIED_DB_ROOT_PASSWORD['super']}" \
  nova_api -e 'select uuid,name,transport_url,database_connection,disabled from cell_mappings;') # <2>
uuidf='\S{8,}-\S{4,}-\S{4,}-\S{4,}-\S{12,}'
default=$(printf "%s\n" "$PULL_OPENSTACK_CONFIGURATION_NOVADB_MAPPED_CELLS" | sed -rn "s/^($uuidf)\s+default\b.*$/\1/p")
difference=$(diff -ZNua \
  <(printf "%s\n" "$PULL_OPENSTACK_CONFIGURATION_NOVADB_MAPPED_CELLS") \
  <(printf "%s\n" "$novadb_mapped_cells")) || true
if [ "$DEFAULT_CELL_NAME" != "default" ]; then
  printf "%s\n" "$difference" | grep -qE "^\-$default\s+default\b" && echo "OK" || echo "CHECK FAILED"
  printf "%s\n" "$difference" | grep -qE "^\+$default\s+$DEFAULT_CELL_NAME\b" && echo "OK" || echo "CHECK FAILED"
  [ $(grep -E "^[-\+]$uuidf" <<<"$difference" | wc -l) -eq 2 ] && echo "OK" || echo "CHECK FAILED"
else
  [ "x$difference" = "x" ] && echo "OK" || echo "CHECK FAILED"
fi
for CELL in $(echo $RENAMED_CELLS); do # <3>
  RCELL=$CELL
  [ "$CELL" = "$DEFAULT_CELL_NAME" ] && RCELL=default
  set +u
  . ~/.source_cloud_exported_variables_$RCELL
  set -u
  c1dbs=$(oc exec openstack-$CELL-galera-0 -n $NAMESPACE -c galera -- mysql -rs -uroot -p${PODIFIED_DB_ROOT_PASSWORD[$CELL]} -e 'SHOW databases;') # <4>
  echo $c1dbs | grep -Eq "\bnova_${CELL}\b" && echo "OK" || echo "CHECK FAILED"
  novadb_svc_records=$(oc exec openstack-$CELL-galera-0 -n $NAMESPACE -c galera -- mysql -rs -uroot -p${PODIFIED_DB_ROOT_PASSWORD[$CELL]} \
    nova_$CELL -e "select host from services where services.binary='nova-compute' and deleted=0 order by host asc;")
  diff -Z <(echo "x$novadb_svc_records") <(echo "x${PULL_OPENSTACK_CONFIGURATION_NOVA_COMPUTE_HOSTNAMES[@]}") && echo "OK" || echo "CHECK FAILED" # <5>
done

# <1> Ensures that the {networking_first_ref} database is renamed from `ovs_neutron`.
# <2> Ensures that the `default` cell is renamed to `$DEFAULT_CELL_NAME`, and the cell UUIDs are retained.
# <3> Ensures that the registered Compute services names have not changed.
# <4> Ensures {compute_service} cells databases are extracted to separate database servers, and renamed from `nova` to `nova_cell<X>`.
# <5> Ensures that the registered {compute_service} name has not changed.
