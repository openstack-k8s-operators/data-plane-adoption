#!/bin/bash
# Disable and mask the service on the Computes.
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
