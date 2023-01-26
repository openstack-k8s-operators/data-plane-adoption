# Backend services deployment

The following instructions create OpenStackControlPlane CR with
MariaDB and RabbitMQ deployed, and other services disabled. This will
be the foundation of the podified control plane.

In subsequent steps we'll import the original databases and then add
podified OpenStack control plane services.

## Prerequisites

* The `openstack-operator` deployed, but `OpenStackControlPlane`
  **not** deployed.

  For developer/CI environments, the openstack operator can be deployed
  by running `make openstack` inside
  [install_yamls](https://github.com/openstack-k8s-operators/install_yamls)
  repo.

  For production environments, the deployment method will likely be
  different.

## Variables

(There are no shell variables necessary currently.)

## Pre-checks

## Procedure - backend services deployment

* Create OSP secret.

  ```
  # in install_yamls
  make input
  ```

* Deploy OpenStackControlPlane. **Make sure to only enable MariaDB and
  RabbitMQ services. All other services must be disabled.**

  ```
  oc apply -f - <<EOF
  apiVersion: core.openstack.org/v1beta1
  kind: OpenStackControlPlane
  metadata:
    name: openstack
  spec:
    secret: osp-secret
    storageClass: local-storage
    mariadb:
      template:
        containerImage: quay.io/tripleozedcentos9/openstack-mariadb:current-tripleo
        storageRequest: 500M
    rabbitmq:
      template:
        replicas: 1

    keystone:
      enabled: false
    cinder:
      enabled: false
    glance:
      enabled: false
    placement:
      enabled: false
    ovn:
      enabled: false
    ovs:
      enabled: false
    neutron:
      enabled: false
    nova:
      enabled: false
  EOF
  ```

## Post-checks
