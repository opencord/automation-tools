#!/bin/bash
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

set -xe

INTERNET_TEST_IP="8.8.8.8"
HELM_CHART_BR="master"

# Sanity tests
if [[ $UID == 0 ]]; then
    echo "Please run this script as non-root user"
    exit 1
fi

if ! sudo -n true; then
    echo "Please configure passwordless sudo on this account"
    exit 1
fi

if ! ping -c 1 $INTERNET_TEST_IP; then
  echo "Please make sure node can reach the internet"
  exit 1
fi

# Update dependencies
sudo apt-get update

# Ref: https://kubernetes.io/docs/setup/independent/install-kubeadm/
# Install docker, Kubernetes, and Kubeadm
sudo apt-get install -y docker.io
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker "$USER"

sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF

sudo apt-get update
sudo apt-get install -y kubelet=1.10.* kubeadm=1.10.* kubectl

# Start Kubernetes by Kubeadm
# Ref: https://kubernetes.io/docs/setup/independent/create-cluster-kubeadm/
sudo kubeadm init --pod-network-cidr 10.244.0.0/16 --kubernetes-version stable-1.10

mkdir -p "$HOME/.kube"
sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

# Install helm
helm init
kubectl create serviceaccount --namespace kube-system tiller
kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
kubectl patch deploy --namespace kube-system tiller-deploy -p '{"spec":{"template":{"spec":{"serviceAccount":"tiller"}}}}'
helm init --service-account tiller --upgrade

# Applying flannel CNI
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.9.1/Documentation/kube-flannel.yml

# Install helm charts
git clone https://gerrit.opencord.org/helm-charts -b "$HELM_CHART_BR"
cd helm-charts

# Kubernetes
helm dep update xos-profile/base-kubernetes
helm install -n base-kubernetes xos-profile/base-kubernetes

# XOS Core
helm dep update xos-core
helm install --set xos_projectName="M-CORD" -n xos-core xos-core

# ONOS fabric control
helm install -n onos -f configs/onos.yaml onos

# MCORD
helm dep update xos-profile/mcord
helm install -n mcord xos-profile/mcord

# Verify the installation
helm list

echo "M-CORD has been successfully installed"
