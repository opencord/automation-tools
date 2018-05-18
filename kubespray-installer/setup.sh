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

#
# Installs Kubespray on remote target machines.
#

set -e -u -o pipefail

install_kubespray () {
  # Cleanup Old Kubespray Installations
  echo "Cleaning Up Old Kubespray Installation"
  rm -rf kubespray

  # Download Kubespray
  echo "Downloading Kubespray"
  git clone https://github.com/kubernetes-incubator/kubespray.git -b "v2.4.0"

  # Generate inventory and var files
  echo "Generating The Inventory File"
  rm -rf "inventories/${DEPLOYMENT_NAME}"
  cp -r kubespray/inventory "inventories/${DEPLOYMENT_NAME}"
  CONFIG_FILE="inventories/${DEPLOYMENT_NAME}/inventory.cfg" python3 kubespray/contrib/inventory_builder/inventory.py "${NODES[@]}"

  # Add configuration to inventory
  ansible-playbook k8s-configs.yaml --extra-vars "deployment_name=${DEPLOYMENT_NAME} k8s_nodes='${NODES[*]}' kubespray_remote_ssh_user='${REMOTE_SSH_USER}'"

  # Prepare Target Machines
  echo "Installing Prerequisites On Remote Machines"
  ansible-playbook -i "inventories/${DEPLOYMENT_NAME}/inventory.cfg" k8s-requirements.yaml

  # Install Kubespray
  echo "Installing Kubespray"
  ansible-playbook -i "inventories/${DEPLOYMENT_NAME}/inventory.cfg" kubespray/cluster.yml -b -v

  # Export the Kubespray Config Location
  echo "Loading Kubespray Configuration"
  cp kubespray/artifacts/admin.conf "configs/${DEPLOYMENT_NAME}.conf"
}

#
# Exports the Kubespray Config Location
#
source_kubeconfig () {
  export KUBECONFIG=${PWD}/configs/${DEPLOYMENT_NAME}.conf
}

#
# Helm init
#
helm_init () {
  echo "Initializing Helm"
  source_kubeconfig "$DEPLOYMENT_NAME"
  helm init --upgrade
  echo "Waiting a minute for Tiller to start"
  sleep 60
}

#
# Deploy an insecure registry
#
deploy_insecure_registry () {
  echo "Deploying insecure registry"
  source_kubeconfig "$DEPLOYMENT_NAME"
  helm install stable/docker-registry --set service.nodePort=30500,service.type=NodePort -n docker-registry
}

#
# Checks if an arbitrary pod name is given during specifc
# operations.
#
check_pod_name () {
  if [ -z "$DEPLOYMENT_NAME" ]
    then
      echo "Missing option: podname" >&2
      echo " "
      display_help
      exit -1
    fi
}

#
# Displays the help menu.
#
display_help () {
  echo "Usage: $0 {--install|--source|--help} [podname] [ip...] " >&2
  echo " "
  echo "   -h, --help              Display this help message."
  echo "   -i, --install           Install Kubespray on <podname>"
  echo "   -s, --source            Source the Kubectl config for <podname>"
  echo " "
  echo "   podname                 An arbitrary name representing the pod"
  echo "   ip                      The IP address of a remote node"
  echo " "
  echo "Example usages:"
  echo "   ./setup.sh -i podname 192.168.10.100 192.168.10.101 192.168.10.102"
  echo "   ./setup.sh -i podname (default is 10.90.0.101 10.90.0.102 10.90.0.103)"
  echo "   source setup.sh -s podname"
}

#
# Init
#
CLI_OPT=$1
DEPLOYMENT_NAME=$2
shift 2
DEFAULT_NODES=(10.90.0.101 10.90.0.102 10.90.0.103)
NODES=("${@:-${DEFAULT_NODES[@]}}")

REMOTE_SSH_USER="${REMOTE_SSH_USER:-cord}"

while :
do
  case $CLI_OPT in
    -i | --install)
        check_pod_name
        install_kubespray
        helm_init
        deploy_insecure_registry
        exit 0
        ;;
    -h | --help)
        display_help
        exit 0
        ;;
    -s | --source)
        check_pod_name
        source_kubeconfig
        return 0
         ;;
    --) # End of all options
        shift
        break
        ;;
    *)
        echo Error: Unknown option: "$CLI_OPT" >&2
        echo " "
        display_help
        exit -1
        ;;
  esac
done
