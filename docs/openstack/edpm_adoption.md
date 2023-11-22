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

* Generate an ssh key-pair `nova-migration-ssh-key` secret

  ```bash
  cd "$(mktemp -d)"
  ssh-keygen -f ./id -t ed25519 -N ''
  oc get secret nova-migration-ssh-key || oc create secret generic nova-migration-ssh-key \
    -n openstack \
    --from-file=ssh-privatekey=id \
    --from-file=ssh-publickey=id.pub \
    --type kubernetes.io/ssh-auth
  rm -f id*
  cd -
  ```

* Create a Nova Compute Extra Config service
    ```yaml
    oc apply -f - <<EOF
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: nova-compute-extraconfig
      namespace: openstack
    data:
      19-nova-compute-cell1-workarounds.conf: |
        [workarounds]
        disable_compute_service_check_for_ffu=true
    ---
    apiVersion: dataplane.openstack.org/v1beta1
    kind: OpenStackDataPlaneService
    metadata:
      name: nova-compute-extraconfig
      namespace: openstack
    spec:
      label: nova.compute.extraconfig
      configMaps:
        - nova-compute-extraconfig
      secrets:
        - nova-cell1-compute-config
        - nova-migration-ssh-key
      playbook: osp.edpm.nova
    EOF
    ```

  The secret ``nova-cell<X>-compute-config`` is auto-generated for each
  ``cell<X>``. That secret, alongside ``nova-migration-ssh-key``, should
  always be specified for each custom `OpenStackDataPlaneService` related to Nova.

* Deploy OpenStackDataPlaneNodeSet:

  ```yaml
  oc apply -f - <<EOF
  apiVersion: dataplane.openstack.org/v1beta1
  kind: OpenStackDataPlaneNodeSet
  metadata:
    name: openstack
  spec:
    networkAttachments:
        - ctlplane
    preProvisioned: true
    services:
      - download-cache
      - configure-network
      - validate-network
      - install-os
      - configure-os
      - run-os
      - libvirt
      - nova-compute-extraconfig
      - ovn
    env:
      - name: ANSIBLE_CALLBACKS_ENABLED
        value: "profile_tasks"
      - name: ANSIBLE_FORCE_COLOR
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
          edpm_network_config_override: ""
          edpm_network_config_template: |
             ---
             {% set mtu_list = [ctlplane_mtu] %}
             {% for network in role_networks %}
             {{ mtu_list.append(lookup('vars', networks_lower[network] ~ '_mtu')) }}
             {%- endfor %}
             {% set min_viable_mtu = mtu_list | max %}
             network_config:
             - type: ovs_bridge
               name: {{ neutron_physical_bridge_name }}
               mtu: {{ min_viable_mtu }}
               use_dhcp: false
               dns_servers: {{ ctlplane_dns_nameservers }}
               domain: {{ dns_search_domains }}
               addresses:
               - ip_netmask: {{ ctlplane_ip }}/{{ ctlplane_subnet_cidr }}
               routes: {{ ctlplane_host_routes }}
               members:
               - type: interface
                 name: nic1
                 mtu: {{ min_viable_mtu }}
                 # force the MAC address of the bridge to this interface
                 primary: true
             {% for network in role_networks %}
               - type: vlan
                 mtu: {{ lookup('vars', networks_lower[network] ~ '_mtu') }}
                 vlan_id: {{ lookup('vars', networks_lower[network] ~ '_vlan_id') }}
                 addresses:
                 - ip_netmask:
                     {{ lookup('vars', networks_lower[network] ~ '_ip') }}/{{ lookup('vars', networks_lower[network] ~ '_cidr') }}
                 routes: {{ lookup('vars', networks_lower[network] ~ '_host_routes') }}
             {% endfor %}

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

          edpm_chrony_ntp_servers:
          - clock.redhat.com
          - clock2.redhat.com

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

* Deploy OpenStackDataPlaneDeployment:

  ```yaml
  oc apply -f - <<EOF
  apiVersion: dataplane.openstack.org/v1beta1
  kind: OpenStackDataPlaneDeployment
  metadata:
    name: openstack
  spec:
    nodeSets:
    - openstack
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
