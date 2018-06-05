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

# This script assumes the following repos exist
# ~/cord/automation-tools

# Location of 'cord' directory for checkouts on the local system
CORDDIR="${CORDDIR:-${HOME}/cord}"

[ ! -d "$CORDDIR" ] && mkdir -p "$CORDDIR"
[ ! -d "$CORDDIR"/automation-tools ] && cd "$CORDDIR" && git clone https://gerrit.opencord.org/automation-tools
[ ! -d "$CORDDIR"/helm-charts ] && cd "$CORDDIR" && git clone https://gerrit.opencord.org/helm-charts


# Install K8S, Helm, Openstack
"$CORDDIR"/automation-tools/openstack-helm/openstack-helm-dev-setup.sh


# Add keys for VTN
[ ! -e ~/.ssh/id_rsa ] && ssh-keygen -f ~/.ssh/id_rsa -t rsa -N ""
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
cp ~/.ssh/id_rsa "$CORDDIR"/helm-charts/xos-profiles/base-openstack/files/node_key

# Add dummy fabric interface
if ! ifconfig fabric &>> /dev/null
then
    sudo modprobe dummy
    sudo ip link set name fabric dev dummy0
    sudo ifconfig fabric up
fi

# Install charts for M-CORD
cd "$CORDDIR"/helm-charts
helm dep update ./xos-core
helm upgrade --install xos-core ./xos-core
~/openstack-helm/tools/deployment/common/wait-for-pods.sh default

helm dep update ./xos-profiles/base-openstack
helm upgrade --install base-openstack ./xos-profiles/base-openstack \
    --set computeNodes.master.name="$( hostname )" \
    --set vtn-service.sshUser="$( whoami )"
~/openstack-helm/tools/deployment/common/wait-for-pods.sh default

helm upgrade --install onos-cord ./onos
~/openstack-helm/tools/deployment/common/wait-for-pods.sh default

helm dep update ./xos-profiles/mcord
helm upgrade --install mcord ./xos-profiles/mcord \
    --set global.proxySshUser="$( whoami )"
~/openstack-helm/tools/deployment/common/wait-for-pods.sh default


# Firewall VNC ports for security (CloudLab)
if [ -d /mnt/extra ]
then
    sudo ufw default allow incoming
    sudo ufw default allow outgoing
    sudo ufw default allow routed
    sudo ufw deny proto tcp from any to any port 5900:5950 comment 'vnc'
    sudo ufw --force enable
fi

echo "M-CORD has been successfully installed"
