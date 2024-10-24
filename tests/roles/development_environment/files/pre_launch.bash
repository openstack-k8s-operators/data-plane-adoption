set -e

alias openstack="$OPENSTACK_COMMAND"

function wait_for_status() {
    local time=0
    local msg="Waiting for $2"
    local status="${3:-available}"
    local result
    while [ $time -le 30 ] ; do
        result=$(${BASH_ALIASES[openstack]} $1 -f json)
        echo $result | jq -r ".status" | grep -q $status && break
        echo "result=$result"
        echo "$msg"
        time=$(( time + 5 ))
        sleep 5
    done
}

# Create Image
IMG=cirros-0.5.2-x86_64-disk.img
URL=http://download.cirros-cloud.net/0.5.2/$IMG
DISK_FORMAT=qcow2
RAW=$IMG
curl -L -# $URL > /tmp/$IMG
if type qemu-img >/dev/null 2>&1; then
    RAW=$(echo $IMG | sed s/img/raw/g)
    qemu-img convert -f qcow2 -O raw /tmp/$IMG /tmp/$RAW
    DISK_FORMAT=raw
fi
${BASH_ALIASES[openstack]} image show cirros || \
    ${BASH_ALIASES[openstack]} image create --container-format bare --disk-format $DISK_FORMAT cirros < /tmp/$RAW

# Create flavor
HPARGS=" "
if [ "${EDPM_CONFIGURE_HUGEPAGES:-false}" = "true" ] ; then
    HPARGS="set huge_pages --property hw:mem_page_size=2MB"
fi
${BASH_ALIASES[openstack]} flavor show m1.small || \
    ${BASH_ALIASES[openstack]} flavor create $HPARGS --ram 512 --vcpus 1 --disk 1 --ephemeral 1 m1.small

# Create networks
${BASH_ALIASES[openstack]} network show private || ${BASH_ALIASES[openstack]} network create private --share
${BASH_ALIASES[openstack]} subnet show priv_sub || ${BASH_ALIASES[openstack]} subnet create priv_sub --subnet-range 192.168.0.0/24 --network private
${BASH_ALIASES[openstack]} network show public || ${BASH_ALIASES[openstack]} network create public --external --provider-network-type flat --provider-physical-network datacentre
${BASH_ALIASES[openstack]} subnet show public_subnet || \
    ${BASH_ALIASES[openstack]} subnet create public_subnet --subnet-range 192.168.122.0/24 --allocation-pool start=192.168.122.171,end=192.168.122.250 --gateway 192.168.122.1 --dhcp --network public
${BASH_ALIASES[openstack]} router show priv_router || {
    ${BASH_ALIASES[openstack]} router create priv_router
    ${BASH_ALIASES[openstack]} router add subnet priv_router priv_sub
    ${BASH_ALIASES[openstack]} router set priv_router --external-gateway public
}

# Create a floating IP
${BASH_ALIASES[openstack]} floating ip show 192.168.122.20 || \
    ${BASH_ALIASES[openstack]} floating ip create public --floating-ip-address 192.168.122.20

# Create a test instance
${BASH_ALIASES[openstack]} server show test || {
    ${BASH_ALIASES[openstack]} server create --flavor m1.small --image cirros --nic net-id=private test --wait
    ${BASH_ALIASES[openstack]} server add floating ip test 192.168.122.20
}

# Create security groups
${BASH_ALIASES[openstack]} security group rule list --protocol icmp --ingress -f json | grep -q '"IP Range": "0.0.0.0/0"' || \
    ${BASH_ALIASES[openstack]} security group rule create --protocol icmp --ingress --icmp-type -1 $(${BASH_ALIASES[openstack]} security group list --project admin -f value -c ID)
${BASH_ALIASES[openstack]} security group rule list --protocol tcp --ingress -f json | grep '"Port Range": "22:22"' || \
    ${BASH_ALIASES[openstack]} security group rule create --protocol tcp --ingress --dst-port 22 $(${BASH_ALIASES[openstack]} security group list --project admin -f value -c ID)

export FIP=192.168.122.20
# check connectivity via FIP
ping -c4 ${FIP}

# create bootable volume
if ! ${BASH_ALIASES[openstack]} volume show disk ; then
    ${BASH_ALIASES[openstack]} volume create --image cirros --size 1 disk
    wait_for_status "volume show disk" "test volume 'disk' creation"
fi

# create volume backup
if ! ${BASH_ALIASES[openstack]} volume backup show backup; then
    ${BASH_ALIASES[openstack]} volume backup create --name backup disk
    wait_for_status "volume backup show backup" "test volume 'disk' backup completion"
fi

# create volume snapshot
if ! ${BASH_ALIASES[openstack]} volume snapshot show snapshot ; then
    ${BASH_ALIASES[openstack]} volume snapshot create --volume disk snapshot
    wait_for_status "volume snapshot show snapshot" "test volume 'disk' snapshot availability"
fi

# Add volume to the test VM
if ${BASH_ALIASES[openstack]} volume show disk -f json | jq -r '.status' | grep -q available ; then
    ${BASH_ALIASES[openstack]} server add volume test disk
fi

# create another bootable volume
if ! ${BASH_ALIASES[openstack]} volume show boot-volume ; then
    ${BASH_ALIASES[openstack]} volume create --image cirros --size 1 boot-volume
    wait_for_status "volume show boot-volume" "test volume 'boot-volume' creation"
fi

# Launch an instance from boot-volume (BFV)
if ${BASH_ALIASES[openstack]} volume show boot-volume -f json | jq -r '.status' | grep -q available ; then
    ${BASH_ALIASES[openstack]} server create --flavor m1.small --volume boot-volume --nic net-id=private bfv-server --wait
fi
