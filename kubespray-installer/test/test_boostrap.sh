#!/usr/bin/env bash
#
# Copyright 2017-present Open Networking Foundation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# test_bootstrap.sh
# Bootstraps VM's for testing kubernetes-installer script
# runs only on Ubuntu 16.04

set -e -u -o pipefail

function cloudlab_setup() {

  # Don't do anything if not a CloudLab node
  [ ! -d /usr/local/etc/emulab ] && return

  # The watchdog will sometimes reset groups, turn it off
  if [ -e /usr/local/etc/emulab/watchdog ]
  then
    sudo /usr/bin/perl -w /usr/local/etc/emulab/watchdog stop
    sudo mv /usr/local/etc/emulab/watchdog /usr/local/etc/emulab/watchdog-disabled
  fi

  # Mount extra space, if haven't already
  if [ ! -d /mnt/extra ]
  then
    sudo mkdir -p /mnt/extra

    # for NVME SSD on Utah Cloudlab, not supported by mkextrafs
    if df | grep -q nvme0n1p1 && [ -e /usr/testbed/bin/mkextrafs ]
    then
      # set partition type of 4th partition to Linux, ignore errors
      printf "t\\n4\\n82\\np\\nw\\nq" | sudo fdisk /dev/nvme0n1 || true

      sudo mkfs.ext4 /dev/nvme0n1p4
      echo "/dev/nvme0n1p4 /mnt/extra/ ext4 defaults 0 0" | sudo tee -a /etc/fstab
      sudo mount /mnt/extra
      mount | grep nvme0n1p4 || (echo "ERROR: NVME mkfs/mount failed, exiting!" && exit 1)

    elif [ -e /usr/testbed/bin/mkextrafs ]  # if on Clemson/Wisconsin Cloudlab
    then
      # Sometimes this command fails on the first try
      sudo /usr/testbed/bin/mkextrafs -r /dev/sdb -qf "/mnt/extra/" || sudo /usr/testbed/bin/mkextrafs -r /dev/sdb -qf "/mnt/extra/"

      # Check that the mount succeeded (sometimes mkextrafs succeeds but device not mounted)
      mount | grep sdb || (echo "ERROR: mkextrafs failed, exiting!" && exit 1)
    fi
  fi

  # replace /var/lib/libvirt/images with a symlink
  [ -d /var/lib/libvirt/images/ ] && [ ! -h /var/lib/libvirt/images ] && sudo rmdir /var/lib/libvirt/images
  sudo mkdir -p /mnt/extra/libvirt_images

  if [ ! -e /var/lib/libvirt/images ]
  then
    sudo ln -s /mnt/extra/libvirt_images /var/lib/libvirt/images
  fi
}

echo "Installing prereqs..."
sudo apt-get update
sudo apt-get -y install apt-transport-https build-essential curl git python-dev \
                        python-netaddr python-pip software-properties-common sshpass \
                        qemu-kvm libvirt-bin libvirt-dev nfs-kernel-server
sudo pip install gitpython graphviz "Jinja2>=2.9" virtualenv

if [ ! -x "/usr/bin/ansible" ]
then
  echo "Installing Ansible..."
  sudo apt-add-repository -y ppa:ansible/ansible  # latest supported version
  sudo apt-get update
  sudo apt-get install -y ansible
fi

if [ ! -x "/usr/bin/vagrant" ]
then
  echo "Installing vagrant and associated tools..."

  VAGRANT_SHA256SUM="2f9498a83b3d650fcfcfe0ec7971070fcd3803fad6470cf7da871caf2564d84f"  # version 2.0.1
  curl -o /tmp/vagrant.deb https://releases.hashicorp.com/vagrant/2.0.1/vagrant_2.0.1_x86_64.deb
  echo "$VAGRANT_SHA256SUM  /tmp/vagrant.deb" | sha256sum -c -
  sudo dpkg -i /tmp/vagrant.deb
fi

cloudlab_setup

echo "Installing vagrant plugins if needed..."
VAGRANT_LIBVIRT_VERSION="0.0.40"
vagrant plugin list | grep -q vagrant-libvirt || vagrant plugin install vagrant-libvirt --plugin-version ${VAGRANT_LIBVIRT_VERSION}
vagrant plugin list | grep -q vagrant-mutate || vagrant plugin install vagrant-mutate

echo "Obtaining libvirt image of Ubuntu"
UBUNTU_VERSION=${UBUNTU_VERSION:-bento/ubuntu-16.04}
vagrant box list | grep "${UBUNTU_VERSION}" | grep virtualbox || vagrant box add --provider virtualbox "${UBUNTU_VERSION}"
vagrant box list | grep "${UBUNTU_VERSION}" | grep libvirt || vagrant mutate "${UBUNTU_VERSION}" libvirt --input-provider virtualbox

if [ ! -e "${HOME}/.gitconfig" ]
  then
    echo "No ${HOME}/.gitconfig, setting testing defaults..."
    git config --global user.name 'Test User'
    git config --global user.email 'test@null.com'
    git config --global color.ui false
fi

if [ ! -d "automation-tools" ]
then
  # make sure we can find gerrit.opencord.org as DNS failures will fail the build
  dig +short gerrit.opencord.org || (echo "ERROR: gerrit.opencord.org can't be looked up in DNS" && exit 1)

  echo "Downloading automation-tools..."
  git clone https://gerrit.opencord.org/automation-tools.git automation-tools

fi

if [ ! -x "/usr/local/bin/kubectl" ]
then
  echo "Installing kubectl..."

  # install kubectl
  KUBECTL_VERSION="1.9.5"
  KUBECTL_SHA256SUM="9c67b6e80e9dd3880511c7d912c5a01399c1d74aaf4d71989c7d5a4f2534bcd5"
  curl -L -o /tmp/kubectl "https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  echo "$KUBECTL_SHA256SUM  /tmp/kubectl" | sha256sum -c -
  sudo cp /tmp/kubectl /usr/local/bin/kubectl
  sudo chmod a+x /usr/local/bin/kubectl
  rm -f /tmp/kubectl
fi


if [ ! -x "/usr/local/bin/helm" ]
then
  echo "Installing helm..."

  # install helm
  HELM_VERSION="2.8.2"
  HELM_SHA256SUM="614b5ac79de4336b37c9b26d528c6f2b94ee6ccacb94b0f4b8d9583a8dd122d3"
  HELM_PLATFORM="linux-amd64"
  curl -L -o /tmp/helm.tgz "https://storage.googleapis.com/kubernetes-helm/helm-v${HELM_VERSION}-${HELM_PLATFORM}.tar.gz"
  echo "$HELM_SHA256SUM  /tmp/helm.tgz" | sha256sum -c -
  pushd /tmp
  tar -xzvf helm.tgz
  sudo cp ${HELM_PLATFORM}/helm /usr/local/bin/helm
  sudo chmod a+x /usr/local/bin/helm
  rm -rf helm.tgz ${HELM_PLATFORM}
  popd
fi


echo "DONE! Docs: automation-tools/kubespray-installer/test/README.md"

