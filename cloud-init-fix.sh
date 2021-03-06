#!/bin/bash
# Dirty fix for CoreOS cloud-init on Openstack with multiple interfaces.
# by Sergi Barroso <hiroru@lionclan.org>
#
# Official CoreOS docs: https://coreos.com/os/docs/latest/cloud-config.html
#

# Defining variables
coreos_cluster_nodes="3"
workdir=$(mktemp --directory)
env="/etc/environment"
trap "rm --force --recursive ${workdir}" SIGINT SIGTERM EXIT

# Function list
function get_ipv4() {
    interface="${1}"
    local ip
    while [ -z "${ip}" ]; do
        ip=$(ip -4 -o addr show dev "${interface}" scope global | gawk '{split ($4, out, "/"); print out[1]}')
        sleep .1
    done
    echo "${ip}"
}

function get_token(){
   numnodes="${1}"
   local token
   while [ -z "${token}" ]; do
      token=$(curl https://discovery.etcd.io/new?size=$numnodes)
      sleep .1
   done
   echo "${token}"
}

# Creating environment file
until ! [[ -z $COREOS_PRIVATE_IPV4 ]]; do
   sudo touch $env
   if [ $? -ne 0 ]; then
      echo "Error: could not write file $env."
   fi
   export COREOS_PUBLIC_IPV4="$(get_ipv4 eth0)"
   export COREOS_PRIVATE_IPV4="$(get_ipv4 eth1)"
   export ETCD_DISCOVERY="https://discovery.etcd.io/368950d08cc1cbf41e788cc425f33d4d" #$(get_token $coreos_cluster_nodes)
   sudo echo "COREOS_PUBLIC_IPV4=$COREOS_PUBLIC_IPV4" > /etc/environment
   sudo echo "COREOS_PRIVATE_IPV4=$COREOS_PRIVATE_IPV4" >> /etc/environment
   sudo echo "ETCD_DISCOVERY=$ETCD_DISCOVERY" >> /etc/environment
   source /etc/environment
done

# Creating custom cloud-config.yml file
if [ -z "$(mount | awk '/oem/ && /rw/ {print}')" ]; then
   sudo mount -o remount,rw /usr/share/oem/
fi
cat > "/usr/share/oem/custom-cloud-config.yml" <<EOF
#cloud-config

coreos:
  etcd2:
    discovery: $ETCD_DISCOVERY
    advertise-client-urls: http://$COREOS_PRIVATE_IPV4:2379,http://$COREOS_PRIVATE_IPV4:4001
    initial-advertise-peer-urls: http://$COREOS_PRIVATE_IPV4:2380
    listen-client-urls: http://0.0.0.0:2379,http://0.0.0.0:4001
    listen-peer-urls: http://$COREOS_PRIVATE_IPV4:2380
  fleet:
    public-ip: $COREOS_PUBLIC_IPV4
  update:
    reboot-strategy: "etcd-lock"
  units:
    - name: etcd2.service
      command: start
    - name: fleet.service
      command: start
ssh_authorized_keys:
  - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCh5/Evt1CGZ1gi9AFYC5VrWx5/ppnXRflOiVoKizYCuLs7WPaRSLurOaOsXh/UoqyaEsjTw5UXuQhoLueF2krCIWeIfD1QAPOXgnbAkp1GWfS6sxlvxhHh2mi1mMrVYEt+Jg/MFW8aU8hV2iW3oAEr9UqtSLoSlQTdKjkMaRtCN4JnEp8t2xvL/xUYM+1SepdJhebSsTKLL+ogfP8j3sYvpDMmGkXdHXXFNeQ37oBZMjbEg71aP0NmCXIbzTIaiIhG6WlerlNkcDUDe4GsJFtKMXkJQaGvqIb8pXXVIpc8s7YamVzd/2ZtnctFrr4x00rFSehqvplSeGG2+FVww6mL
EOF
sudo sed -i 's/--oem=ec2-compat/--from-file=\/usr\/share\/oem\/custom-cloud-config.yml/g' /usr/share/oem/cloud-config.yml

# Exec custom file, reboot and enjoy :)
sudo coreos-cloudinit --from-file='/usr/share/oem/custom-cloud-config.yml'
sudo reboot
