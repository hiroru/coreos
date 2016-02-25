#!/bin/bash
# Dirty fix for CoreOS cloud-init on Openstack with multiple interfaces.
# by Sergi Barroso <hiroru@lionclan.org>

if ! [ -f /etc/environment ]; then
   if [ -z "$(mount | awk '/oem/ && /rw/ {print}')" ]; then
      sudo mount -o remount,rw /usr/share/oem/
   fi
   sudo echo "COREOS_PUBLIC_IPV4=$(ip addr | grep eth1 | sed -n 's/.*inet.\([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\).*/\1/p')" > /etc/environment
   sudo echo "COREOS_PRIVATE_IPV4=$(ip addr | grep eth0 | sed -n 's/.*inet.\([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\).*/\1/p')" >> /etc/environment
   sudo echo "\$private_ipv4=$(ip addr | grep eth0 | sed -n 's/.*inet.\([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\).*/\1/p')" >> /etc/environment
   source /etc/environment
   sudo sed -i 's/--oem=ec2-compat/--from-configdrive=\/media\/configdrive\//g' /usr/share/oem/cloud-config.yml
   sudo /usr/bin/coreos-cloudinit --from-configdrive=/media/configdrive/
   sudo reboot
fi
