# Octavia adoption

Migrating from a Director based to an OpenShift Octavia deployment
presents some special challenges. These require that some of the
original components continue to run until all processes that reference
them are no longer running or have been altered to reference the new
Octavia services running in OpenShift.


## Prerequisites

Previous Adoption steps have been completed, including:
 * MariaDB
 * Keystone
 * OVN
 * Neutron
 * Nova
 * Glance
 * Barbican (optionally)

> The Octavia database should have been included in the database transfer for the MariaDB adoption process. The OVN db should also have been migrated during the OVN migration process.

## Start the Redis Pod (optional)

If Octavia is configured to use Taskflow for task coordination, then Redis should be enabled prior to migration. To start Redis, patch the OpenStackControlPlane:

```
oc patch openstackcontrolplane openstack --type=merge --patch '
spec:
  redis:
    enabled: true
	templates:
    - something-octavia-specific-tbd
'
```

## Shutdown Director Deployed Octavia Services

In addition to the Octavia API service, the Worker, Health Manager and
Housekeeping Octavia components should also be shutdown gracefully. A modified
form of the general OpenStack service shutdown script can be used

```bash

# Update the services list to be stopped
ServicesToStop=("tripleo_octavia_api.service"
                "tripleo_octavia_worker.service"
                "tripleo_octavia_healthmanager.service"
                "tripleo_octavia_housekeeping.service"
 )

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

echo "Stopping Redis"
for i in {1..3}; do
    SSH_CMD=CONTROLLER${i}_SSH
    if [ ! -z "${!SSH_CMD}" ]; then
        echo "Using controller $i to run pacemaker commands"
		if ${!SSH_CMD} sudo pcs resource config redis; then
           ${!SSH_CMD} sudo pcs resource disable redis
        fi
		break
    fi
done
```

> Note that running loadbalancers are active elements and at this time, the
  amphorae load balancers are effectively *wild* and may be in an unexpected
  state at the end of the adoption process and extra steps may be necessary to
  reconcile the state of a given loadblancer resource.

## Start Octavia in OpenShift

Starting the Octavia services is the next step in the adoption process. While
adoption isn't completed, we need the API process running so we can update the
load balancers with the new IPs for the health manager service.


```
oc patch openstackcontrolplane openstack --type=merge --patch '
spec:
  octavia:
    enabled: true
	template: {}
'
```

## Update the Load Balancers with the new Health Manager IPs

### Get the IPs for the load balancer management network

*TODO: We will need the details of how the OpenShift OpenStack control
plane makes the  IPs available. e.g. oc describe octavia
octaviaHealthManagerS  -o json | jq -r '.status.healthManager.managementEndpoints'*

### Modify the running load balancer's management network information.

 *TODO: Allegedly there's an API for that *
