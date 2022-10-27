# MariaDB adoption procedure

## Pre-checks

Make sure the environment is set up correctly, we assumed the steps from https://gitlab.cee.redhat.com/rhos-upgrades/data-plane-adoption-dev/-/blob/main/libvirt_podified_standalone.md are followed.

## Adoption

### Database backup

```
# Connect to the Standalone TripleO deployment
ssh -i ~/.ssh/okdcluster_id_rsa root@10.0.0.4 # CentOS Stream

# Log in as the stack user
su - stack

# Get the MySQL passwrod string
cat ~/tripleo-standalone-passwords.yaml

# Store the password in a variable
mysql_pass=$(cat ~/tripleo-standalone-passwords.yaml | grep 'MysqlRootPassword' | tr -d ' ' | cut -d ':' -f 2)

# Make sure we can connect to the database
mysql -u root -p$mysql_pass -e "show databases"

# You should get something like
# mysql: [Warning] Using a password on the command line interface can be insecure.
# +--------------------+
# | Database           |
# +--------------------+
# | cinder             |
# | glance             |
# | information_schema |
# | keystone           |
# | mysql              |
# | nova               |
# | nova_api           |
# | nova_cell0         |
# | ovs_neutron        |
# | performance_schema |
# | placement          |
# +--------------------+

# So far is not important to export each database individually but we will bash it.
# Create a folder to store the databases
mkdir -p ~/dbdumps
cd ~/dbdumps

# Get all the databases individually
mysql -uroot -p$mysql_pass -N -e 'show databases' | while read dbname; do mysqldump -uroot -p$mysql_pass --complete-insert --column-statistics=0 --skip-lock-tables "$dbname" > "$dbname".sql; done

# Get also all the databases in a single file
mysqldump -u root -p$mysql_pass --all-databases --column-statistics=0 --skip-lock-tables > tripleo_all_databases_backup.sql


# Go to the home folder
cd ~/

# Compress the DB backups folder
tar -czvf tripleo_databases.tar.gz -C ~/dbdumps .

# Get the compressed file, so we can move it to a place with physical access to the MySQL instances in the OpenShiftcluster
## Go to root
exit
## Exit the Standalone TripleO guest
exit
## Get the file
scp -i ~/.ssh/okdcluster_id_rsa root@10.0.0.4:/home/stack/tripleo_databases.tar.gz .

# Copy the file to the service guest VM (machine with access to the OpenShift cluster)
scp -i ~/.ssh/okdcluster_id_rsa ~/tripleo_databases.tar.gz root@10.0.0.253:/root/ 

# Connect to the machine with access to the OpenShift cluster resources
ssh -i ~/.ssh/okdcluster_id_rsa root@10.0.0.253

# Unzip all the backup fikes
mkdir -p ~/dbdumps
tar xvf ~/tripleo_databases.tar.gz -C ~/dbdumps
```

### Deploy MariaDB

### Restore the data bases


## Post-checks

