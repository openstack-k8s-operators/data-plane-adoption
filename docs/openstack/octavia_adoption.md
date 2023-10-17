# Octavia adoption

Migrating from a Director based to an OpenShift Octavia deployment
presents some special challenges. These require that some
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

## About Director Deployed Octavia Services

Octavia API service, the Worker, Health Manager and
Housekeeping Octavia components should have been shutdown gracefully as part of
the common *Stop OpenStack services* step.

> TODO: Verify whether OVN provider loadbalancers really require
> *tripleo_octavia_driver_agent.service* to be still running during adoption.
> Possible reasons why it might need to keep running:
> . the report status to the Octavia API from the ovn-provider
> . to still receive any update from OVN NB/SB as event where we need
>   to do some actions

> Amphora RSyslog logs from the old data plane will not get copied to the new
> control plane as part of the adoption process and remain on the old
> environment.

> Note that running loadbalancers are active elements and at this time, the
  amphorae load balancers are effectively *wild* and may be in an unexpected
  state at the end of the adoption process and extra steps may be necessary to
  reconcile the state of a given loadbalancer resource.

## Start Octavia in OpenShift

Starting the Octavia services is the next step in the adoption process. While
adoption isn't completed, we need the API process running, so we can update the
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

 Depending on timeout settings and the duration of the data plane adoption 
 process it can happen that masses of failovers get triggered when the new
 control plane gets activated. In order to prevent this the following 
 tactics may be possible:

 1. Temporarily set very high timeouts for heartbeat intervals
 2. Use the failover circuit breaker feature in order to stop mass failovers 
    when they occur.
 3. Shut down the health managers until data plane adoption is finished. 
    After the was started again the Amphorae have 
    `CONF.health_manager.heartbeat_timeout` s to send a first heartbeat to the
    new health manager in order to prevent accidental failovers from getting 
    triggered.

Option 3 is probably the best approach.

### Get the IPs for the load balancer management network

*TODO: We will need the details of how the OpenShift OpenStack control
plane makes the  IPs available. e.g. oc describe octavia
octaviaHealthManagerS  -o json | jq -r '.status.healthManager.managementEndpoints'*

### Modify the running load balancer's management network information.

```
alias ocopenstack="oc exec -t openstackclient -- openstack"
for ampid in $(ocopenstack loadbalancer amphora list -c id -f value); do
    ocopenstack loadbalancer amphora configure ${ampid}
done
```
