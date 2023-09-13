# EDPM adoption

## Prerequisites

* Previous Adoption steps completed.

## Variables

(There are no shell variables necessary currently.)

## Pre-checks

* Make sure the IPAM is configured

```bash
oc apply -f - <<EOF
apiVersion: network.openstack.org/v1beta1
kind: NetConfig
metadata:
  name: netconfig
spec:
  networks:
  - name: CtlPlane
    dnsDomain: ctlplane.example.com
    subnets:
    - name: subnet1
      allocationRanges:
      - end: 192.168.122.120
        start: 192.168.122.100
      - end: 192.168.122.200
        start: 192.168.122.150
      cidr: 192.168.122.0/24
      gateway: 192.168.122.1
  - name: InternalApi
    dnsDomain: internalapi.example.com
    subnets:
    - name: subnet1
      allocationRanges:
      - end: 172.17.0.250
        start: 172.17.0.100
      cidr: 172.17.0.0/24
      vlan: 20
  - name: External
    dnsDomain: external.example.com
    subnets:
    - name: subnet1
      allocationRanges:
      - end: 10.0.0.250
        start: 10.0.0.100
      cidr: 10.0.0.0/24
      gateway: 10.0.0.1
  - name: Storage
    dnsDomain: storage.example.com
    subnets:
    - name: subnet1
      allocationRanges:
      - end: 172.18.0.250
        start: 172.18.0.100
      cidr: 172.18.0.0/24
      vlan: 21
  - name: StorageMgmt
    dnsDomain: storagemgmt.example.com
    subnets:
    - name: subnet1
      allocationRanges:
      - end: 172.20.0.250
        start: 172.20.0.100
      cidr: 172.20.0.0/24
      vlan: 23
  - name: Tenant
    dnsDomain: tenant.example.com
    subnets:
    - name: subnet1
      allocationRanges:
      - end: 172.19.0.250
        start: 172.19.0.100
      cidr: 172.19.0.0/24
      vlan: 22
EOF
```

## Procedure - EDPM adoption

* Create a [ssh authentication secret](https://kubernetes.io/docs/concepts/configuration/secret/#ssh-authentication-secrets) for the EDPM nodes:

  ```bash
  oc apply -f - <<EOF
  apiVersion: v1
  kind: Secret
  metadata:
      name: dataplane-adoption-secret
      namespace: openstack
  data:
      ssh-privatekey: |
  $(cat ~/install_yamls/out/edpm/ansibleee-ssh-key-id_rsa | base64 | sed 's/^/        /')
  EOF
  ```

* Stop the nova services.

```bash

# Update the services list to be stopped

ServicesToStop=("tripleo_nova_api_cron.service"
                "tripleo_nova_api.service"
                "tripleo_nova_compute.service"
                "tripleo_nova_conductor.service"
                "tripleo_nova_libvirt.target"
                "tripleo_nova_metadata.service"
                "tripleo_nova_migration_target.service"
                "tripleo_nova_scheduler.service"
                "tripleo_nova_virtlogd_wrapper.service"
                "tripleo_nova_virtnodedevd.service"
                "tripleo_nova_virtproxyd.service"
                "tripleo_nova_virtqemud.service"
                "tripleo_nova_virtsecretd.service"
                "tripleo_nova_virtstoraged.service"
                "tripleo_nova_vnc_proxy.service")

echo "Stopping nova services"

for service in ${ServicesToStop[*]}; do
    echo "Stopping the $service in each controller node"
    $CONTROLLER1_SSH sudo systemctl stop $service
    $CONTROLLER2_SSH sudo systemctl stop $service
    $CONTROLLER3_SSH sudo systemctl stop $service
done
```

* Deploy OpenStackDataPlaneNodeSet:

  ```
  oc apply -f - <<EOF
  apiVersion: dataplane.openstack.org/v1beta1
  kind: OpenStackDataPlaneNodeSet
  metadata:
    name: openstack
  spec:
    deployStrategy:
      deploy: true
    networkAttachments:
        - ctlplane
    preProvisioned: true
    services:
      - configure-network
      - validate-network
      - install-os
      - configure-os
      - run-os
      - ovn
    env:
      - name: ANSIBLE_CALLBACKS_ENABLED
        value: "profile_tasks"
      - name: ANSIBLE_FORCE_COLOR
        value: "True"
      - name: ANSIBLE_ENABLE_TASK_DEBUGGER
        value: "True"
    nodes:
      standalone:
        hostName: standalone
        ansible:
          ansibleHost: 192.168.122.100
        networks:
        - defaultRoute: true
          fixedIP: 192.168.122.100
          name: CtlPlane
          subnetName: subnet1
        - name: InternalApi
          subnetName: subnet1
        - name: Storage
          subnetName: subnet1
        - name: Tenant
          subnetName: subnet1
    nodeTemplate:
      ansibleSSHPrivateKeySecret: dataplane-adoption-secret
      managementNetwork: ctlplane
      ansible:
        ansibleUser: root
        ansiblePort: 22
        ansibleVars:
          service_net_map:
            nova_api_network: internal_api
            nova_libvirt_network: internal_api

          # edpm_network_config
          # Default nic config template for a EDPM compute node
          # These vars are edpm_network_config role vars
          edpm_network_config_template: templates/single_nic_vlans/single_nic_vlans.j2
          edpm_network_config_hide_sensitive_logs: false
          #
          # These vars are for the network config templates themselves and are
          # considered EDPM network defaults.
          neutron_physical_bridge_name: br-ctlplane
          neutron_public_interface_name: eth0
          role_networks:
          - InternalApi
          - Storage
          - Tenant
          networks_lower:
            External: external
            InternalApi: internal_api
            Storage: storage
            Tenant: tenant

          # edpm_nodes_validation
          edpm_nodes_validation_validate_controllers_icmp: false
          edpm_nodes_validation_validate_gateway_icmp: false

          edpm_ovn_metadata_agent_DEFAULT_transport_url: $(oc get secret rabbitmq-transport-url-neutron-neutron-transport -o json | jq -r .data.transport_url | base64 -d)
          edpm_ovn_metadata_agent_metadata_agent_ovn_ovn_sb_connection: $(oc get ovndbcluster ovndbcluster-sb -o json | jq -r .status.dbAddress)
          edpm_ovn_metadata_agent_metadata_agent_DEFAULT_nova_metadata_host: $(oc get svc nova-metadata-internal -o json |jq -r '.status.loadBalancer.ingress[0].ip')
          edpm_ovn_metadata_agent_metadata_agent_DEFAULT_metadata_proxy_shared_secret: $(oc get secret osp-secret -o json | jq -r .data.MetadataSecret  | base64 -d)
          edpm_ovn_metadata_agent_DEFAULT_bind_host: 127.0.0.1
          edpm_chrony_ntp_servers:
          - clock.redhat.com
          - clock2.redhat.com

          edpm_ovn_dbs: $(oc get ovndbcluster ovndbcluster-sb -o json | jq -r '.status.networkAttachments."openstack/internalapi"')

          edpm_ovn_controller_agent_image: quay.io/podified-antelope-centos9/openstack-ovn-controller:current-podified
          edpm_iscsid_image: quay.io/podified-antelope-centos9/openstack-iscsid:current-podified
          edpm_logrotate_crond_image: quay.io/podified-antelope-centos9/openstack-cron:current-podified
          edpm_nova_compute_container_image: quay.io/podified-antelope-centos9/openstack-nova-compute:current-podified
          edpm_nova_libvirt_container_image: quay.io/podified-antelope-centos9/openstack-nova-libvirt:current-podified
          edpm_ovn_metadata_agent_image: quay.io/podified-antelope-centos9/openstack-neutron-metadata-agent-ovn:current-podified

          gather_facts: false
          enable_debug: false
          # edpm firewall, change the allowed CIDR if needed
          edpm_sshd_configure_firewall: true
          edpm_sshd_allowed_ranges: ['192.168.122.0/24']
          # SELinux module
          edpm_selinux_mode: enforcing
          plan: overcloud
  EOF
  ```

## Post-checks

* Check if all the Ansible EE pods reaches `Completed` status:

    ```bash
    # watching the pods
    watch oc get pod -l app=openstackansibleee
    ```
    ```bash
    # following the ansible logs with:
    oc logs -l app=openstackansibleee -f --max-log-requests 10
    ```

* Wait for the dataplane node set to reach the Ready status:
    ```
    oc wait --for condition=Ready osdpns/openstack --timeout=30m
    ```
