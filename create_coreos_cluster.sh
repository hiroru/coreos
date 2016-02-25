#!/bin/bash -x
# Sergi Barroso

NUM_NODES=4

# Building the Virtual Disk
#wget https://raw.github.com/coreos/scripts/master/contrib/create-coreos-vdi
#chmod +x create-coreos-vdi
#./create-coreos-vdi -d .

# Creating iso file to attach as cdrom unit to emulate Openstack config drive
#wget https://raw.github.com/coreos/scripts/master/contrib/create-basic-configdrive
#chmod +x create-basic-configdrive
# Get token from discovery.etcd.io
TOKEN=`curl -w "\n" "https://discovery.etcd.io/new?size=$NUM_NODES" | cut -d "/" -f4`
for x in $(seq 1 $NUM_NODES)
do
  ./create-basic-configdrive -H coreos_$x -S ~/.ssh/id_rsa.pub -t $TOKEN
	VBoxManage clonehd coreos-production-stable.vdi coreos_$x.vdi
	# Resize virtual disk to 10 GB
	VBoxManage modifyhd coreos_$x.vdi --resize 10240
	VBoxManage createvm --name "coreos_$x" --register
	VBoxManage modifyvm "coreos_$x" --memory 1024 --acpi on
	VBoxManage modifyvm "coreos_$x" --nic1 NAT
	VBoxManage modifyvm "coreos_$x" --ostype Linux_64
	VBoxManage storagectl "coreos_$x" --name "IDE Controller" --add ide
	VBoxManage storageattach "coreos_$x" --storagectl "IDE Controller" --port 0 --device 0 --type hdd --medium coreos_$x.vdi
	VBoxManage storageattach "coreos_$x" --storagectl "IDE Controller" --port 1 --device 0 --type dvddrive --medium coreos_$x.iso
	VBoxHeadless --startvm "coreos_$x" &
done
