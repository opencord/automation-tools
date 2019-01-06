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

set -e -o pipefail

KS_COMMIT="${KS_COMMIT:-v2.8.1}"

install_kubespray () {
  # Cleanup Old Kubespray Installations
  echo "Cleaning Up Old Kubespray Installation"
  rm -rf kubespray

  # Download Kubespray
  echo "Downloading Kubespray"
  git clone https://github.com/kubernetes-incubator/kubespray.git
  pushd kubespray
  git checkout "$KS_COMMIT"
  popd

  # create a virtualenv with specific packages, if it doesn't exist
  if [ ! -x "ks_venv/bin/activate" ]
  then
    virtualenv ks_venv
    # shellcheck disable=SC1091
    source ks_venv/bin/activate

    pip install ansible==2.5.3
    pip install -r kubespray/requirements.txt
  else
    # shellcheck disable=SC1091
    source ks_venv/bin/activate
  fi


  # Generate inventory and var files
  echo "Generating The Inventory File"

  rm -rf "inventories/${DEPLOYMENT_NAME}"
  mkdir -p "inventories/${DEPLOYMENT_NAME}"

  cp -r kubespray/inventory/sample/group_vars "inventories/${DEPLOYMENT_NAME}/group_vars"
  CONFIG_FILE="inventories/${DEPLOYMENT_NAME}/inventory.cfg" python3 kubespray/contrib/inventory_builder/inventory.py "${NODES[@]}"

  # Add configuration to inventory
  ansible-playbook k8s-configs.yaml --extra-vars "deployment_name=${DEPLOYMENT_NAME} k8s_nodes='${NODES[*]}' kubespray_remote_ssh_user='${REMOTE_SSH_USER}'"

  # Prepare Target Machines
  echo "Installing Prerequisites On Remote Machines"
  ansible-playbook -i "inventories/${DEPLOYMENT_NAME}/inventory.cfg" k8s-requirements.yaml

  # Install Kubespray
  echo "Installing Kubespray"
  ansible-playbook -i "inventories/${DEPLOYMENT_NAME}/inventory.cfg" -e docker_version='17.03' kubespray/cluster.yml -b -v
}

#
# Exports the Kubespray Config Location
#
source_kubeconfig () {

  kubeconfig_path="${PWD}/inventories/${DEPLOYMENT_NAME}/artifacts/admin.conf"

  if [ -f "$kubeconfig_path" ]
  then
    # these options are annoying outside of scripts
    set +e +u +o pipefail

    echo "setting KUBECONFIG=$kubeconfig_path"

    export KUBECONFIG="$kubeconfig_path"
  else
    echo "kubernetes admin.conf not found at: '$kubeconfig_path'"
    exit 1
  fi
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
  echo "   ip                      The IP address of the remote node(s)"
  echo " "
  echo "Example usages:"
  echo "   ./setup.sh -i podname 192.168.10.100 192.168.10.101 192.168.10.102"
  echo "   ./setup.sh -i podname (default is 10.90.0.101 10.90.0.102 10.90.0.103)"
  echo "   source setup.sh -s podname"
}

#
# Init
#
if [ $# -lt 2 ]
then
  display_help
  exit 0
fi

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
        exit 0
        ;;
    -h | --help)
        display_help
        exit 0
        ;;
    -s | --source)
        check_pod_name
        source_kubeconfig
        break
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
