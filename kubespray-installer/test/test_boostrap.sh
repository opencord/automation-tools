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

echo "Installing vagrant..."

if [ ! -x "/usr/bin/vagrant" ]
then
  echo "Installing vagrant and associated tools..."

  VAGRANT_SHA256SUM="2f9498a83b3d650fcfcfe0ec7971070fcd3803fad6470cf7da871caf2564d84f"  # version 2.0.1
  curl -o /tmp/vagrant.deb https://releases.hashicorp.com/vagrant/2.0.1/vagrant_2.0.1_x86_64.deb
  echo "$VAGRANT_SHA256SUM  /tmp/vagrant.deb" | sha256sum -c -
  sudo dpkg -i /tmp/vagrant.deb
fi

echo "Installing vagrant plugins if needed..."
VAGRANT_LIBVIRT_VERSION="0.0.40"
vagrant plugin list | grep -q vagrant-libvirt || vagrant plugin install vagrant-libvirt --plugin-version ${VAGRANT_LIBVIRT_VERSION}
vagrant plugin list | grep -q vagrant-mutate || vagrant plugin install vagrant-mutate

echo "Obtaining libvirt image of Ubuntu"
UBUNTU_VERSION=${UBUNTU_VERSION:-bento/ubuntu-16.04}
vagrant box list | grep "${UBUNTU_VERSION}" | grep virtualbox || vagrant box add --provider virtualbox "${UBUNTU_VERSION}"
vagrant box list | grep "${UBUNTU_VERSION}" | grep libvirt || vagrant mutate "${UBUNTU_VERSION}" libvirt --input-provider virtualbox


