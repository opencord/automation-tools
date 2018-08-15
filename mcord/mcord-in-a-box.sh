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

# This script assumes the following repos exist and will create them if not
# ~/cord/automation-tools
# ~/cord/helm-charts

# Sanity tests
if [[ $UID == 0 ]]; then
    echo "Please run this script as non-root user"
    exit 1
fi

if ! sudo -n true; then
    echo "Please configure passwordless sudo on this account"
    exit 1
fi



# Location of 'cord' directory for checkouts on the local system
CORDDIR="${CORDDIR:-${HOME}/cord}"
XOSDBDIR="/var/local/vol1"

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

cat <<EOF > /tmp/xos-values.yaml
---
xos-db:
  needDBPersistence: true
  storageClassName: local-directory

xos-gui:
  xos_projectName: "M-CORD"

volumes:
  - name: "db-pv"
    size: "2Gi"
    host: "$( hostname -f )"
    directory: "${XOSDBDIR}"

computeNodes:
  master:
    name: "$( hostname )"

vtn-service:
  sshUser: "$( whoami )"

global:
  proxySshUser: "$( whoami )"
EOF
sudo mkdir -p "${XOSDBDIR}"
helm upgrade --install local-directory ./storage/local-directory \
    -f /tmp/xos-values.yaml

helm dep update ./xos-core
helm upgrade --install xos-core ./xos-core \
    -f /tmp/xos-values.yaml
~/openstack-helm/tools/deployment/common/wait-for-pods.sh default

helm dep update ./xos-profiles/base-openstack
helm upgrade --install base-openstack ./xos-profiles/base-openstack \
    -f /tmp/xos-values.yaml
~/openstack-helm/tools/deployment/common/wait-for-pods.sh default

helm upgrade --install onos-cord ./onos
~/openstack-helm/tools/deployment/common/wait-for-pods.sh default

helm dep update ./xos-profiles/mcord
helm upgrade --install mcord ./xos-profiles/mcord \
    -f /tmp/xos-values.yaml
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
