#!/bin/bash
set -x
galera_con=$(sudo podman ps --format="{{.Names}}"|grep galera)
mariadb_templates='/home/cloud-admin/data-plane-adoption_pkomarov/tests/roles/mariadb_copy/templates/'

sudo podman cp ${mariadb_templates}/dump_dbs_ospdo.sh $galera_con:/
sudo podman exec -it $galera_con bash -c "/mysql_db_dump.sh $1 $2"