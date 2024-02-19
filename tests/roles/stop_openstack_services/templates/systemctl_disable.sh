#!/bin/bash
# Try to stop a service , fail only when the service is present and doesn't stop correctly.
service=$1

cat << EOF > ~/disable_service.yaml
- hosts: Compute
  tasks:
  - name: Disable & mask service
    become: true
    systemd:
      name: "$service"
      masked: yes
      enabled: no  # Optional, ensures service is not enabled
EOF
ansible-playbook -i ~/ctlplane-ansible-inventory ~/disable_service.yaml
