#!/bin/bash
set -x
mkdir -p /tmp/mariadb
cd /tmp/mariadb
mysql -h $1 -u root "-p${2}" -N -e 'show databases' | grep -E -v 'schema|mysql'| while read dbname; do echo "Dumping ${dbname}"
sudo mysqldump -h $1 -uroot "-p${2}" \
        --single-transaction --complete-insert --skip-lock-tables --lock-tables=0 \
        "${dbname}" > "/tmp/mariadb/${dbname}".sql

done
ls /tmp/mariadb|grep nova