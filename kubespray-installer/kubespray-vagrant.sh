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

# kubespray-vagrant.sh
# Bootstraps Vagrant VM's for testing kubernetes-installer scripts

set -eu -o pipefail

# configure git
if [ ! -e "${HOME}/.gitconfig" ]
then
  echo "No ${HOME}/.gitconfig, setting testing defaults..."
  git config --global user.name 'Test User'
  git config --global user.email 'test@null.com'
  git config --global color.ui false
fi

# install repo if needed
if [ ! -x "/usr/local/bin/repo" ]
then
  echo "Installing repo..."

  REPO_SHA256SUM="394d93ac7261d59db58afa49bb5f88386fea8518792491ee3db8baab49c3ecda"
  curl -o /tmp/repo 'https://gerrit.opencord.org/gitweb?p=repo.git;a=blob_plain;f=repo;hb=refs/heads/stable'
  echo "$REPO_SHA256SUM  /tmp/repo" | sha256sum -c -
  sudo cp /tmp/repo /usr/local/bin/repo
  sudo chmod a+x /usr/local/bin/repo
fi

# check out cord repo
if [ ! -d "${HOME}/cord" ]
then
  # make sure we can find gerrit.opencord.org as DNS failures will fail the build
  dig +short gerrit.opencord.org || (echo "ERROR: gerrit.opencord.org can't be looked up in DNS" && exit 1)

  echo "Downloading cord with repo..."
  pushd "${HOME}"
  mkdir -p cord
  cd cord
  repo init -u https://gerrit.opencord.org/manifest -b master
  repo sync
  popd
fi

# if on cloudlab, format extra space - has to happen before Vagrant install or root will overfill
"$HOME"/cord/automation-tools/scripts/cloudlab-disksetup.sh

echo "Installing prereqs..."
sudo apt-get update
sudo apt-get -y install apt-transport-https build-essential curl git python-dev \
                        python-pip python-virtualenv software-properties-common \
                        sshpass libffi-dev qemu-kvm libvirt-bin libvirt-dev \
                        nfs-kernel-server socat

# Install kubernetes tools (if not installed)
if [ ! -x "/usr/bin/kubeadm" ]
then

  cat << EOF | base64 -d > /tmp/k8s-apt-key.gpg
mQENBFUd6rIBCAD6mhKRHDn3UrCeLDp7U5IE7AhhrOCPpqGF7mfTemZYHf/5JdjxcOxoSFlK
7zwmFr3lVqJ+tJ9L1wd1K6P7RrtaNwCiZyeNPf/Y86AJ5NJwBe0VD0xHTXzPNTqRSByVYtdN
94NoltXUYFAAPZYQls0x0nUD1hLMlOlC2HdTPrD1PMCnYq/NuL/Vk8sWrcUt4DIS+0RDQ8tK
Ke5PSV0+PnmaJvdF5CKawhh0qGTklS2MXTyKFoqjXgYDfY2EodI9ogT/LGr9Lm/+u4OFPvmN
9VN6UG+s0DgJjWvpbmuHL/ZIRwMEn/tpuneaLTO7h1dCrXC849PiJ8wSkGzBnuJQUbXnABEB
AAG0QEdvb2dsZSBDbG91ZCBQYWNrYWdlcyBBdXRvbWF0aWMgU2lnbmluZyBLZXkgPGdjLXRl
YW1AZ29vZ2xlLmNvbT6JAT4EEwECACgFAlUd6rICGy8FCQWjmoAGCwkIBwMCBhUIAgkKCwQW
AgMBAh4BAheAAAoJEDdGwginMXsPcLcIAKi2yNhJMbu4zWQ2tM/rJFovazcY28MF2rDWGOnc
9giHXOH0/BoMBcd8rw0lgjmOosBdM2JT0HWZIxC/Gdt7NSRA0WOlJe04u82/o3OHWDgTdm9M
S42noSP0mvNzNALBbQnlZHU0kvt3sV1YsnrxljoIuvxKWLLwren/GVshFLPwONjw3f9Fan6G
WxJyn/dkX3OSUGaduzcygw51vksBQiUZLCD2Tlxyr9NvkZYTqiaWW78L6regvATsLc9L/dQU
iSMQZIK6NglmHE+cuSaoK0H4ruNKeTiQUw/EGFaLecay6Qy/s3Hk7K0QLd+gl0hZ1w1VzIeX
Lo2BRlqnjOYFX4CwAgADmQENBFrBaNsBCADrF18KCbsZlo4NjAvVecTBCnp6WcBQJ5oSh7+E
98jX9YznUCrNrgmeCcCMUvTDRDxfTaDJybaHugfba43nqhkbNpJ47YXsIa+YL6eEE9emSmQt
jrSWIiY+2YJYwsDgsgckF3duqkb02OdBQlh6IbHPoXB6H//b1PgZYsomB+841XW1LSJPYlYb
IrWfwDfQvtkFQI90r6NknVTQlpqQh5GLNWNYqRNrGQPmsB+NrUYrkl1nUt1LRGu+rCe4bSaS
mNbwKMQKkROE4kTiB72DPk7zH4Lm0uo0YFFWG4qsMIuqEihJ/9KNX8GYBr+tWgyLooLlsdK3
l+4dVqd8cjkJM1ExABEBAAG0QEdvb2dsZSBDbG91ZCBQYWNrYWdlcyBBdXRvbWF0aWMgU2ln
bmluZyBLZXkgPGdjLXRlYW1AZ29vZ2xlLmNvbT6JAT4EEwECACgFAlrBaNsCGy8FCQWjmoAG
CwkIBwMCBhUIAgkKCwQWAgMBAh4BAheAAAoJEGoDCyG6B/T78e8H/1WH2LN/nVNhm5TS1VYJ
G8B+IW8zS4BqyozxC9iJAJqZIVHXl8g8a/Hus8RfXR7cnYHcg8sjSaJfQhqO9RbKnffiuQgG
rqwQxuC2jBa6M/QKzejTeP0Mgi67pyrLJNWrFI71RhritQZmzTZ2PoWxfv6b+Tv5v0rPaG+u
t1J47pn+kYgtUaKdsJz1umi6HzK6AacDf0C0CksJdKG7MOWsZcB4xeOxJYuy6NuO6KcdEz8/
XyEUjIuIOlhYTd0hH8E/SEBbXXft7/VBQC5wNq40izPi+6WFK/e1O42DIpzQ749ogYQ1eode
xPNhLzekKR3XhGrNXJ95r5KO10VrsLFNd8KwAgAD
EOF

  sudo apt-key add /tmp/k8s-apt-key.gpg

  echo "deb http://apt.kubernetes.io/ kubernetes-$(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

  sudo apt-get update

  sudo apt-get -y install \
    "kubeadm=1.14.6-*" \
    "kubelet=1.14.6-*" \
    "kubectl=1.14.6-*"

  # enable kubectl bash completion
  echo "source <(kubectl completion bash)" >> ~/.bashrc

fi

# install helm
if [ ! -x "/usr/local/bin/helm" ]
then
  echo "Installing helm..."

  HELM_VERSION="2.14.3"
  HELM_SHA256SUM="38614a665859c0f01c9c1d84fa9a5027364f936814d1e47839b05327e400bf55"
  HELM_PLATFORM="linux-amd64"
  curl -L -o /tmp/helm.tgz "https://storage.googleapis.com/kubernetes-helm/helm-v${HELM_VERSION}-${HELM_PLATFORM}.tar.gz"
  echo "$HELM_SHA256SUM  /tmp/helm.tgz" | sha256sum -c -
  pushd /tmp
  tar -xzvf helm.tgz
  sudo cp ${HELM_PLATFORM}/helm /usr/local/bin/helm
  sudo chmod a+x /usr/local/bin/helm
  rm -rf helm.tgz ${HELM_PLATFORM}
  popd

  helm init --client-only
  helm repo add incubator https://kubernetes-charts-incubator.storage.googleapis.com/

  echo "source <(helm completion bash)" >> ~/.bashrc
fi

# install vagrant
if [ ! -x "/usr/bin/vagrant" ]
then
  echo "Installing vagrant and associated tools..."

  VAGRANT_VERSION="2.2.5"
  VAGRANT_SHA256SUM="415f50b93235e761db284c761f6a8240a6ef6762ee3ec7ff869d2bccb1a1cdf7"
  curl -o /tmp/vagrant.deb https://releases.hashicorp.com/vagrant/${VAGRANT_VERSION}/vagrant_${VAGRANT_VERSION}_x86_64.deb
  echo "$VAGRANT_SHA256SUM  /tmp/vagrant.deb" | sha256sum -c -
  sudo dpkg -i /tmp/vagrant.deb
fi

echo "Installing vagrant plugins if needed..."
VAGRANT_LIBVIRT_VERSION="0.0.45"
vagrant plugin list | grep -q vagrant-libvirt || vagrant plugin install vagrant-libvirt --plugin-version ${VAGRANT_LIBVIRT_VERSION}
vagrant plugin list | grep -q vagrant-mutate || vagrant plugin install vagrant-mutate

echo "Obtaining libvirt image of Ubuntu"
UBUNTU_VERSION=${UBUNTU_VERSION:-bento/ubuntu-16.04}
vagrant box list | grep "${UBUNTU_VERSION}" | grep virtualbox || vagrant box add --provider virtualbox "${UBUNTU_VERSION}"
vagrant box list | grep "${UBUNTU_VERSION}" | grep libvirt || vagrant mutate "${UBUNTU_VERSION}" libvirt --input-provider virtualbox

echo "DONE! 'cd ~/cord/automation-tools/kubespray-installer && vagrant up' to start the VMs"

