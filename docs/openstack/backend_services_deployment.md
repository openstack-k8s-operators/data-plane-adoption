# Backend services deployment

The following instructions create OpenStackControlPlane CR with
MariaDB and RabbitMQ deployed, and all the other services disabled. This will
be the foundation of the podified control plane.

In subsequent steps, we'll import the original databases and then add
podified OpenStack control plane services.

## Prerequisites

* The cloud which we want to adopt is up and running. It's on
  OpenStack Wallaby release.

* The `openstack-operator` is deployed, but `OpenStackControlPlane` is
  **not** deployed.

  For developer/CI environments, the openstack operator can be deployed
  by running `make openstack` inside
  [install_yamls](https://github.com/openstack-k8s-operators/install_yamls)
  repo.

  For production environments, the deployment method will likely be
  different.

* There are free PVs available to be claimed (for MariaDB and RabbitMQ).

  For developer/CI environments driven by install_yamls, make sure
  you've run `make crc_storage`.


## Variables

* Set the desired admin password for the podified deployment. This can
  be the original deployment's admin password or something else.

  ```
  ADMIN_PASSWORD=SomePassword
  ```

* Set service password variables to match the original deployment.
  Database passwords can differ in podified environment, but
  synchronizing the service account passwords is a required step.

  E.g. in developer environments with TripleO Standalone, the
  passwords can be extracted like this:

  ```
  CINDER_PASSWORD=$(cat ~/tripleo-standalone-passwords.yaml | grep ' CinderPassword:' | awk -F ': ' '{ print $2; }')
  GLANCE_PASSWORD=$(cat ~/tripleo-standalone-passwords.yaml | grep ' GlancePassword:' | awk -F ': ' '{ print $2; }')
  IRONIC_PASSWORD=$(cat ~/tripleo-standalone-passwords.yaml | grep ' IronicPassword:' | awk -F ': ' '{ print $2; }')
  NEUTRON_PASSWORD=$(cat ~/tripleo-standalone-passwords.yaml | grep ' NeutronPassword:' | awk -F ': ' '{ print $2; }')
  NOVA_PASSWORD=$(cat ~/tripleo-standalone-passwords.yaml | grep ' NovaPassword:' | awk -F ': ' '{ print $2; }')
  OCTAVIA_PASSWORD=$(cat ~/tripleo-standalone-passwords.yaml | grep ' OctaviaPassword:' | awk -F ': ' '{ print $2; }')
  PLACEMENT_PASSWORD=$(cat ~/tripleo-standalone-passwords.yaml | grep ' PlacementPassword:' | awk -F ': ' '{ print $2; }')
  ```

## Pre-checks

## Procedure - backend services deployment

* Create OSP secret.

  The procedure for this will vary, but in developer/CI environments
  we use install_yamls:

  ```
  # in install_yamls
  make input
  ```

* If the `$ADMIN_PASSWORD` is different than the already set password
  in `osp-secret`, amend the `AdminPassword` key in the `osp-secret`
  correspondingly:

  ```
  oc set data secret/osp-secret "AdminPassword=$ADMIN_PASSWORD"
  ```

* Set service account passwords in `osp-secret` to match the service
  account passwords from the original deployment:

  ```
  oc set data secret/osp-secret "CinderPassword=$CINDER_PASSWORD"
  oc set data secret/osp-secret "GlancePassword=$GLANCE_PASSWORD"
  oc set data secret/osp-secret "IronicPassword=$IRONIC_PASSWORD"
  oc set data secret/osp-secret "NeutronPassword=$NEUTRON_PASSWORD"
  oc set data secret/osp-secret "NovaPassword=$NOVA_PASSWORD"
  oc set data secret/osp-secret "OctaviaPassword=$OCTAVIA_PASSWORD"
  oc set data secret/osp-secret "PlacementPassword=$PLACEMENT_PASSWORD"
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
    keystone:
      enabled: false
    mariadb:
      templates:
        openstack:
          containerImage: quay.io/tripleozedcentos9/openstack-mariadb:current-tripleo
          storageRequest: 500M
    rabbitmq:
      templates:
        rabbitmq:
          replicas: 1
    placement:
      enabled: false
    glance:
      enabled: false
    cinder:
      enabled: false
      template:
        cinderAPI:
          replicas: 1
          containerImage: quay.io/tripleozedcentos9/openstack-cinder-api:current-tripleo
        cinderScheduler:
          replicas: 1
          containerImage: quay.io/tripleozedcentos9/openstack-cinder-scheduler:current-tripleo
        cinderBackup:
          replicas: 1
          containerImage: quay.io/tripleozedcentos9/openstack-cinder-backup:current-tripleo
        cinderVolumes:
          volume1:
            containerImage: quay.io/tripleozedcentos9/openstack-cinder-volume:current-tripleo
            replicas: 1
    ovn:
      enabled: false
    ovs:
      enabled: false
    neutron:
      enabled: false
    nova:
      enabled: false
    ironic:
      enabled: false
      template:
        databaseInstance: openstack
        ironicAPI:
          replicas: 1
          containerImage: quay.io/tripleozedcentos9/openstack-ironic-api:current-tripleo
        ironicConductors:
        - replicas: 1
          containerImage: quay.io/tripleozedcentos9/openstack-ironic-conductor:current-tripleo
          pxeContainerImage: quay.io/tripleozedcentos9/openstack-ironic-pxe:current-tripleo
          storageRequest: 10G
        ironicInspector:
          replicas: 1
          containerImage: quay.io/tripleozedcentos9/openstack-ironic-inspector:current-tripleo
          pxeContainerImage: quay.io/tripleozedcentos9/openstack-ironic-pxe:current-tripleo
  EOF
  ```

## Post-checks

* Check that MariaDB is running.

  ```
  oc get pod mariadb-openstack -o jsonpath='{.status.phase}{"\n"}'
  ```
