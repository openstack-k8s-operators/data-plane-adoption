#!/bin/bash
# script is executed in a controller, it executes a mysql querry on a galera container and returns a query by requested query case.
# example usage :
# [cloud-admin@controller-1 ~]$ ./exec_mysql_ospdo.sh show_db

galera_con=$(sudo podman ps --format="{{.Names}}"|grep galera)

function mysql_q(){
sudo podman exec -it $galera_con bash -c "mysql -rs $1"
}

function show_db() {
  query="nova_api -e \"select host from nova.services where services.binary='nova-compute';\""
  mysql_q "$query"
}

function mysqlcheck() {
  query="mysqlcheck --all-databases | grep -v OK"
  sudo podman exec -it $galera_con bash -c "$query"
}

function show_db() {
  query="nova_api -e \"select host from nova.services where services.binary='nova-compute';\""
  mysql_q "$query"
}

function show_db() {
  query="nova_api -e \"select host from nova.services where services.binary='nova-compute';\""
  mysql_q "$query"
}

# Case statement per query
case $1 in
  "show_db")
    show_db
    ;;
  "mysqlcheck")
    mysqlcheck
    ;;
  "show_db")
    show_db
    ;;
  "show_db")
    show_db
    ;;
esac
