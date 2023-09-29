# Pull Openstack configuration

Before starting to adoption workflow, we can start by pulling the configuration
from the Openstack services and TripleO on our file system in order to backup
the configuration files and then use it for later, during the configuration of
the adopted services and for the record to compare and make sure nothing has been
missed or misconfigured.

Make sure you have pull the os-diff repository and configure according to your
environment:
[Configure os-diff](planning.md#configuration-tooling)

## Pull configuration from a TripleO deployment

Once you make sure the ssh connnection is confugred correctly and os-diff has been
built, you can start to pull configuration from your Openstack services.

All the services are describes in an Ansible role:

[collect_config vars](https://github.com/openstack-k8s-operators/os-diff/blob/main/roles/collect_config/vars/main.yml)

Once you enabled the services you need (you can enable everything even if a services is not deployed)
you can start to pull the Openstack services configuration files:

```bash
pushd os-diff
./os-diff pull --cloud_engine=podman
```

The configuration will be pulled and stored in:
```bash
/tmp/collect_tripleo_configs
```

And you provided another path with:

```bash
./os-diff pull --cloud_engine=podman -e local_working_dir=$HOME
```

Once the ansible playbook has been run, you should have into your local directory a directory per services

```
  ▾ tmp/
    ▾ collect_tripleo_configs/
      ▾ glance/
```

## Get services topology specific configuration

Define the shell variables used in the steps below. The values are
just illustrative, use values that are correct for your environment:

```bash
MARIADB_IMAGE=quay.io/podified-antelope-centos9/openstack-mariadb:current-podified
SOURCE_MARIADB_IP=192.168.122.100
SOURCE_DB_ROOT_PASSWORD=$(cat ~/tripleo-standalone-passwords.yaml | grep ' MysqlRootPassword:' | awk -F ': ' '{ print $2; }')
```

Note the following outputs to compare it with post-adoption values later on:

* Test connection to the original DB:

  ```bash
  PULL_OPENSTACK_CONFIGURATION_DATABASES=$(podman run -i --rm --userns=keep-id -u $UID $MARIADB_IMAGE \
      mysql -h "$SOURCE_MARIADB_IP" -uroot "-p$SOURCE_DB_ROOT_PASSWORD" -e 'SHOW databases;')
  ```
  Note the `nova`, `nova_api`, `nova_cell0` databases residing in the same DB host.

* Run mysqlcheck on the original DB to look for things that are not OK:

  ```bash
  PULL_OPENSTACK_CONFIGURATION_MYSQLCHECK_NOK=$(podman run -i --rm --userns=keep-id -u $UID $MARIADB_IMAGE \
      mysqlcheck --all-databases -h $SOURCE_MARIADB_IP -u root "-p$SOURCE_DB_ROOT_PASSWORD" | grep -v OK)
  ```

* Get Nova cells mappings from database:

  ```bash
  PULL_OPENSTACK_CONFIGURATION_NOVADB_MAPPED_CELLS=$(podman run -i --rm --userns=keep-id -u $UID $MARIADB_IMAGE mysql \
      -h "$SOURCE_MARIADB_IP" -uroot "-p$SOURCE_DB_ROOT_PASSWORD" nova_api -e \
      'select uuid,name,transport_url,database_connection,disabled from cell_mappings;')
  ```

* Get Nova instances cell_ids from database:

  ```bash
  PULL_OPENSTACK_CONFIGURATION_NOVADB_INSTANCES_CELL_IDS=$(podman run -i --rm --userns=keep-id -u $UID $MARIADB_IMAGE mysql \
      -h "$SOURCE_MARIADB_IP" -uroot "-p$SOURCE_DB_ROOT_PASSWORD" nova_api -e \
      "select cell_id from nova_api.instance_mappings;")
  ```

* Get the host names of the registered Nova compute services:

  ```bash
  PULL_OPENSTACK_CONFIGURATION_NOVA_COMPUTE_HOSTNAMES=$(podman run -i --rm --userns=keep-id -u $UID $MARIADB_IMAGE mysql \
      -h "$SOURCE_MARIADB_IP" -uroot "-p$SOURCE_DB_ROOT_PASSWORD" nova_api -e \
      "select host from nova.services where services.binary='nova-compute';")
  ```

* Get the list of mapped Nova cells:

  ```bash
  PULL_OPENSTACK_CONFIGURATION_NOVAMANAGE_CELL_MAPPINGS=$($CONTROLLER_SSH sudo podman exec -it nova_api nova-manage cell_v2 list_cells)
  ```