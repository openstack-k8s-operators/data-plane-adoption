# pcp_cleanup role

This role cleans up the podified control plane and podifed data
plane from the target OpenShift environment, removing any artifacts
of a previous test suite run (even a failed one).

This role also include the option of reverting standalone VM to
pre adoption state .


## Variables

See
[defaults file](https://github.com/openstack-k8s-operators/data-plane-adoption/blob/main/tests/roles/pcp_cleanup/defaults/main.yaml).
