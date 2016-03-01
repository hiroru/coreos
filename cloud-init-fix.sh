#!/bin/bash
# Dirty fix for CoreOS cloud-init on Openstack with multiple interfaces.
# by Sergi Barroso <hiroru@lionclan.org>

# Defining variables
#workdir=$(mktemp --directory)
env="/etc/environment"
trap "rm --force --recursive ${workdir}" SIGINT SIGTERM EXIT

get_ipv4() {
    IFACE="${1}"
    local ip
    while [ -z "${ip}" ]; do
        ip=$(ip -4 -o addr show dev "${IFACE}" scope global | gawk '{split ($4, out, "/"); print out[1]}')
        sleep .1
    done
    echo "${ip}"
}

until ! [[ -z $COREOS_PRIVATE_IPV4 ]]; do
   sudo touch $env
   if [ $? -ne 0 ]; then
      echo "Error: could not write file $env."
   fi
   export COREOS_PUBLIC_IPV4=$(get_ipv4 eth0)
   export COREOS_PRIVATE_IPV4=$(get_ipv4 eth1)
   sudo echo "COREOS_PUBLIC_IPV4=$COREOS_PUBLIC_IPV4" > /etc/environment
   sudo echo "COREOS_PRIVATE_IPV4=$COREOS_PRIVATE_IPV4" >> /etc/environment
   source /etc/environment
done

if [ -z "$(mount | awk '/oem/ && /rw/ {print}')" ]; then
   sudo mount -o remount,rw /usr/share/oem/
fi

cat > "/usr/share/oem/custom-cloud-config.yml" <<EOF
#cloud-config

coreos:
  etcd2:
    # generate a new token for each unique cluster from https://discovery.etcd.io/new?size=3
    # specify the initial size of your cluster with ?size=X
    discovery: https://discovery.etcd.io/667174019038b48d0c7437f1c500a425
    # multi-region and multi-cloud deployments need to use $public_ipv4
    advertise-client-urls: http://$COREOS_PRIVATE_IPV4:2379,http://$COREOS_PRIVATE_IPV4:4001
    initial-advertise-peer-urls: http://$COREOS_PRIVATE_IPV4:2380
    # listen on both the official ports and the legacy ports
    # legacy ports can be omitted if your application doesn't depend on them
    listen-client-urls: http://0.0.0.0:2379,http://0.0.0.0:4001
    listen-peer-urls: http://$COREOS_PRIVATE_IPV4:2380
  fleet:
    public-ip: $COREOS_PUBLIC_IPV4
  units:
    - name: etcd2.service
      command: start
    - name: fleet.service
      command: start
ssh_authorized_keys:
  - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCh5/Evt1CGZ1gi9AFYC5VrWx5/ppnXRflOiVoKizYCuLs7WPaRSLurOaOsXh/UoqyaEsjTw5UXuQhoLueF2krCIWeIfD1QAPOXgnbAkp1GWfS6sxlvxhHh2mi1mMrVYEt+Jg/MFW8aU8hV2iW3oAEr9UqtSLoSlQTdKjkMaRtCN4JnEp8t2xvL/xUYM+1SepdJhebSsTKLL+ogfP8j3sYvpDMmGkXdHXXFNeQ37oBZMjbEg71aP0NmCXIbzTIaiIhG6WlerlNkcDUDe4GsJFtKMXkJQaGvqIb8pXXVIpc8s7YamVzd/2ZtnctFrr4x00rFSehqvplSeGG2+FVww6mL
EOF

sudo sed -i 's/--oem=ec2-compat/--from-file=\/usr\/share\/oem\/custom-cloud-config.yml/g' /usr/share/oem/cloud-config.yml
sudo coreos-cloudinit --from-file='/usr/share/oem/custom-cloud-config.yml'
sudo reboot
