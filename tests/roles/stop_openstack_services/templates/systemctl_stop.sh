#!/bin/bash
# Try to stop a service , fail only when the service is present and doesn't stop correctly.
service=$1

cat << EOF > ~/stop_service.yaml
- hosts: Controller
  tasks:
  - name: Stop service "$service"
    become: true
    service:
        name: "$service"
        state: stopped
    register: service_stop
    failed_when:
        - '"Could not find the requested service" not in service_stop.msg'
        - service_stop.rc != 0
EOF
ansible-playbook -i ~/ctlplane-ansible-inventory ~/stop_service.yaml