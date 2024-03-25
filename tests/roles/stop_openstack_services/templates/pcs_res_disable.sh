#!/bin/bash
# script: if pc sresource config test fails , next ,
#         if resource exists desable it.

if ! sudo pcs resource config ${1:-"openstack-cinder-volume"} ;then
  echo "no such resource"
else
  sudo pcs resource disable ${1:-"openstack-cinder-volume"}
fi
