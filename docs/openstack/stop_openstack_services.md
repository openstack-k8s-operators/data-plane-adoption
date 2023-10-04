# Stop OpenStack services

Before we can start with the adoption we need to make sure that the OpenStack
services have been stopped.

This is an important step to avoid inconsistencies in the data migrated for the
data-plane adoption procedure caused by resource changes after the DB has been
copied to the new deployment.

Some services are easy to stop because they only perform short asynchronous
operations, but other services are a bit more complex to gracefully stop
because they perform synchronous or long running operations that we may want to
complete instead of aborting them.

Since gracefully stopping all services is non-trivial and beyond the scope of
this guide we'll proceed with the force method but present a couple of
recommendations on how to check some things in the services.

## Variables

Define the shell variables used in the steps below. The values are
just illustrative and refer to a single node standalone director deployment,
use values that are correct for your environment:

```
CONTROLLER1_SSH="ssh -i ~/install_yamls/out/edpm/ansibleee-ssh-key-id_rsa root@192.168.122.100"
CONTROLLER2_SSH=""
CONTROLLER3_SSH=""
```

We chose to use these ssh variables with the ssh commands instead of using
ansible to try to create instructions that are independent on where they are
running, but ansible commands could be used to achieve the same result if we
are in the right host, for example to stop a service:

```
. stackrc ansible -i $(which tripleo-ansible-inventory) Controller -m shell -a "sudo systemctl stop tripleo_horizon.service" -b
```

## Pre-checks

We can stop OpenStack services at any moment, but we may leave things in an
undesired state, so at the very least we should have a look to confirm that
there are no long running operations that require other services.

Ensure that there are no ongoing instance live migrations, volume migrations
(online or offline), volume creation, backup restore, attaching, detaching,
etc.

```
openstack server list --all-projects -c ID -c Status |grep -E '\| .+ing \|'
openstack volume list --all-projects -c ID -c Status |grep -E '\| .+ing \|'| grep -vi error
openstack volume backup list --all-projects -c ID -c Status |grep -E '\| .+ing \|' | grep -vi error
openstack image list -c ID -c Status |grep -E '\| .+ing \|'
```


## Stopping control plane services

We can stop OpenStack services at any moment, but we may leave things in an
undesired state, so at the very least we should have a look to confirm that
there are no ongoing  operations.

1- Connect to all the controller nodes.
2- Stop the services.
3- Make sure all the services are stopped.

The cinder-backup service on OSP 17.1 could be running as Active-Passive under
pacemaker or as Active-Active, so we'll have to check how it's running and
stop it.

These steps can be automated with a simple script that relies on the previously
defined environmental variables and function:

```bash

# Update the services list to be stopped
ServicesToStop=("tripleo_horizon.service"
                "tripleo_keystone.service"
                "tripleo_cinder_api.service"
                "tripleo_cinder_api_cron.service"
                "tripleo_cinder_scheduler.service"
                "tripleo_cinder_backup.service"
                "tripleo_glance_api.service"
                "tripleo_neutron_api.service"
                "tripleo_nova_api.service"
                "tripleo_octavia_api.service"
                "tripleo_octavia_driver_agent.service"
                "tripleo_octavia_health_manager.service"
                "tripleo_octavia_housekeeping.service"
                "tripleo_octavia_rsyslog.service"
                "tripleo_octavia_worker.service"
                "tripleo_placement_api.service")

PacemakerResourcesToStop=("openstack-cinder-volume"
                          "openstack-cinder-backup")

echo "Stopping systemd OpenStack services"
for service in ${ServicesToStop[*]}; do
    for i in {1..3}; do
        SSH_CMD=CONTROLLER${i}_SSH
        if [ ! -z "${!SSH_CMD}" ]; then
            echo "Stopping the $service in controller $i"
            if ${!SSH_CMD} sudo systemctl is-active $service; then
                ${!SSH_CMD} sudo systemctl stop $service
            fi
        fi
    done
done

echo "Checking systemd OpenStack services"
for service in ${ServicesToStop[*]}; do
    for i in {1..3}; do
        SSH_CMD=CONTROLLER${i}_SSH
        if [ ! -z "${!SSH_CMD}" ]; then
            echo "Checking status of $service in controller $i"
            if ! ${!SSH_CMD} systemctl show $service | grep ActiveState=inactive >/dev/null; then
               echo "ERROR: Service $service still running on controller $i"
            fi
        fi
    done
done

echo "Stopping pacemaker OpenStack services"
for i in {1..3}; do
    SSH_CMD=CONTROLLER${i}_SSH
    if [ ! -z "${!SSH_CMD}" ]; then
        echo "Using controller $i to run pacemaker commands"
        for resource in ${PacemakerResourcesToStop[*]}; do
            if ${!SSH_CMD} sudo pcs resource config $resource; then
                ${!SSH_CMD} sudo pcs resource disable $resource
            fi
        done
        break
    fi
done
```
