# Horizon adoption

## Prerequisites

* Previous Adoption steps completed. Notably, Memcached and 
  keystone should be already adopted.

## Variables

(There are no shell variables necessary currently.)

## Procedure - Horizon adoption

* Patch OpenStackControlPlane to deploy Horizon:

  ```
  oc patch openstackcontrolplane openstack --type=merge --patch '
  spec:
    horizon:
      enabled: true
      template:
        memcachedInstance: memcached
        secret: osp-secret
  '
  ```

## Post-checks

* See that Horizon instance is successfully deployed and ready

```
oc get horizon
```

* Check that dashboard is reachable and returns status code `200`

```
PUBLIC_URL=$(oc get horizon horizon -o jsonpath='{.status.endpoint}')
curl --silent --output /dev/stderr --head --write-out "%{http_code}" "$PUBLIC_URL/dashboard/auth/login/?next=/dashboard/" | grep 200
```