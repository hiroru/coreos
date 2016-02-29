#!/bin/bash
# Dirty fix for CoreOS cloud-init on Openstack with multiple interfaces.
# by Sergi Barroso <hiroru@lionclan.org>

until ! [[ -z $COREOS_PRIVATE_IPV4 ]]; do
   ENV="/etc/environment"
   if [ -z "$ENV" ]; then
      echo usage: $0 /etc/environment
      exit 1
   fi

   sudo touch $ENV
   if [ $? -ne 0 ]; then
      echo "Error: could not write file $ENV."
   fi
   sudo echo "COREOS_PUBLIC_IPV4=$(ip addr | grep eth1 | sed -n 's/.*inet.\([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\).*/\1/p')" > /etc/environment
   sudo echo "COREOS_PRIVATE_IPV4=$(ip addr | grep eth1 | sed -n 's/.*inet.\([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\).*/\1/p')" >> /etc/environment
   sudo echo "private_ipv4=$(ip addr | grep eth1 | sed -n 's/.*inet.\([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\).*/\1/p')" >> /etc/environment
   source /etc/environment
done

if [ -z "$(mount | awk '/oem/ && /rw/ {print}')" ]; then
   sudo mount -o remount,rw /usr/share/oem/
fi
cat > "/tmp/cloud-config.yml" <<EOF
#cloud-config

coreos:
  etcd2:
    discovery: https://discovery.etcd.io/3eaccdff779f276109317cc33d67dda0
    advertise-client-urls: http://$private_ipv4:2379,http://$private_ipv4:4001
    initial-advertise-peer-urls: http://$private_ipv4:2380
  units:
    - name: etcd2.service
      command: start
    - name: fleet.service
      command: start
ssh_authorized_keys:
  - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCh5/Evt1CGZ1gi9AFYC5VrWx5/ppnXRflOiVoKizYCuLs7WPaRSLurOaOsXh/UoqyaEsjTw5UXuQhoLueF2krCIWeIfD1QAPOXgnbAkp1GWfS6sxlvxhHh2mi1mMrVYEt+Jg/MFW8aU8hV2iW3oAEr9UqtSLoSlQTdKjkMaRtCN4JnEp8t2xvL/xUYM+1SepdJhebSsTKLL+ogfP8j3sYvpDMmGkXdHXXFNeQ37oBZMjbEg71aP0NmCXIbzTIaiIhG6WlerlNkcDUDe4GsJFtKMXkJQaGvqIb8pXXVIpc8s7YamVzd/2ZtnctFrr4x00rFSehqvplSeGG2+FVww6mL
EOF

export COREOS_PUBLIC_IPV4
export COREOS_PRIVATE_IPV4

sudo coreos-cloudinit --from-file='/tmp/cloud-config.yml'
sudo reboot
