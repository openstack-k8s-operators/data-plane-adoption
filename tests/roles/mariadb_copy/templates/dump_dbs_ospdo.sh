#!/bin/bash
set -x
mkdir -p /tmp/mariadb
cd /tmp/mariadb
mysql -N -e 'show databases' | grep -E -v 'schema|mysql'| while read dbname; do echo "Dumping ${dbname}"
mysqldump --single-transaction --complete-insert --skip-lock-tables --lock-tables=0 \
        "${dbname}" > "/tmp/mariadb/${dbname}".sql

done
ls /tmp/mariadb|grep -q nova
