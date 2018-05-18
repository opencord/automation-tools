#!/bin/bash

# Disk setup and symlinks
function cloudlab_setup() {

    # Don't do anything if not a CloudLab node
    [ ! -d /usr/local/etc/emulab ] && return

    # Mount extra space, if haven't already
    if [ ! -d /mnt/extra ]
    then
	sudo mkdir -p /mnt/extra

	# for NVME SSD on Utah Cloudlab, not supported by mkextrafs
	if $(df | grep -q nvme0n1p1) && [ -e /usr/testbed/bin/mkextrafs ]
	then
	    # set partition type of 4th partition to Linux, ignore errors
	    echo -e "t\n4\n82\np\nw\nq" | sudo fdisk /dev/nvme0n1 || true

	    sudo mkfs.ext4 /dev/nvme0n1p4
	    echo "/dev/nvme0n1p4 /mnt/extra/ ext4 defaults 0 0" | sudo tee -a /etc/fstab
	    sudo mount /mnt/extra
	    mount | grep nvme0n1p4 || (echo "ERROR: NVME mkfs/mount failed, exiting!" && exit 1)

	elif [ -e /usr/testbed/bin/mkextrafs ]  # if on Clemson/Wisconsin Cloudlab
	then
	    # Sometimes this command fails on the first try
	    sudo /usr/testbed/bin/mkextrafs -s 1 -r /dev/sdb -qf "/mnt/extra/" || sudo /usr/testbed/bin/mkextrafs -s 1 -r /dev/sdb -qf "/mnt/extra/"

	    # Check that the mount succeeded (sometimes mkextrafs succeeds but device not mounted)
	    mount | grep sdb || (echo "ERROR: mkextrafs failed, exiting!" && exit 1)
	fi
    fi

    for DIR in docker kubelet openstack-helm nova
    do
	sudo mkdir -p /mnt/extra/$DIR
        sudo chmod -R a+rwx /mnt/extra/$DIR
	[ ! -e /var/lib/$DIR ] && sudo ln -s /mnt/extra/$DIR /var/lib/$DIR
    done
}

cloudlab_setup

