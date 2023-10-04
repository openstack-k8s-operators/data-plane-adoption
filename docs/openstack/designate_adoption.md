# Designate adoption

Migrating from a Director based to an OpenShift Designate deployment
presents some special challenges. These require that some of the
original components continue to run until all processes that reference
them are no longer running or have been altered to reference the new
Designate services running in OpenShift.


## Prerequisites

Previous Adoption steps have been completed, including:
 * MariaDB
 * Keystone
 * Neutron

> The Designate database should have been included in the database transfer fo the MariaDB adoption process.


## Start a Redis Pod

Designate uses Redis to coordinate tasks amongst Designate Central and Producer pods. To start Redis, patch the OpenStackControlPlane:

```
oc patch openstackcontrolplane openstack --type=merge --patch '
spec:
  redis:
    enabled: true
	templates:
    - something-designate-specific-tbd
'
```

## Shutdown Director Deployed Designate Services

In addition to the Designate API service, the Central and Producer
Designate components should also be shutdown gracefully. A modified form
of the general OpenStack service shutdown script can be used

```bash

# Update the services list to be stopped
ServicesToStop=("tripleo_designate_api.service"
                "tripleo_designate_producer.service"
                "tripleo_designate_central.service"
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

Once completed, the Designate managed data should remain static until
adoption is complete. The Unbound and bind9 instances should still be running
and able to respond to DNS requests.


## Start the non-API Designate Services in OpenShift

At this stage, the goal is to start services that respond to DNS queries
and are used to maintain DNS records but prevent the API from being
started to avoid changes to Designate records and introduce inconsistencies.

```
oc patch openstackcontrolplane openstack --type=merge --patch '
spec:
  designate:
    enabled: true
	template:
	  designateAPI:
	    replicas: 0
'
```

## Modify Designate miniDNS Haproxy Entries in Directory Controller

Configured zones will need to access the miniDNS pods running in the
podified control plane. However, where the bind9 servers are running on
the TripleO public API network, they will not be able to access the
miniDNS servers running on the internal API network. There are haproxy
entries that redirect calls to miniDNS servers through a
*port-per-backend* mapping. The backend configuration needs to be
changed to reference the miniDNS pods.

### Get the IPs for the Designate miniDNS pods

*TODO: We will need the details of how the OpenShift OpenStack control
plane makes the miniDNS IPs available. e.g. oc describe designate
destignate-mDNS  -o json | jq -r '.status.miniDNS.endpoints'*

**This won't work - you don't need the internal endpoints, you need the
kubeproxy->miniDNS mappings. So what does this look like **

### Modify the HAProxy Configuration on the Controllers.

*TODO: thisshould have an ansible playbook*


## Update Designate bind9 Configuration to Allow Access from New Control Plane

The Designate name server backend has access control lists that restrict
access to known IPs. These need to be reconfigured to allow access to
allow requests from the egress network for the miniDNS and designate
worker services. Considering the dynamic nature of apparent source
address, these will need to be described as network CIDRs instead of
specific addresses. Both the allow-notify named and control ACL for rndc
need to be modified.

## Perform a bind pool update with the new information

*todo: one approach to this is to take the bind pool yaml file off of a controller and perform sed type replacements no the old minidns and feed that to the designate operator


## Check Operation

At this point, the Designate bind backend9 should be using the OpenShift
OpenStack control plane. Confirming that the operation requires
inspecting the logs and looking for errors in

## Update

Dns namserver configuration and how it plays with adopting unbounds.
