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

###########################################################
# Install openstack-helm dev setup on Ubuntu 16.04 server #
#     Including customizations to Neutron for CORD        #
###########################################################

set -xe

# CORD versioning
OPENSTACK_HELM_BRANCH="${OPENSTACK_HELM_BRANCH:-master}"
OPENSTACK_HELM_COMMIT="${OPENSTACK_HELM_COMMIT:-79128a94fc4c7e7b301497abeab094fa01efaa06}"
OPENSTACK_HELM_INFRA_BRANCH="${OPENSTACK_HELM_BRANCH:-master}"
OPENSTACK_HELM_INFRA_COMMIT="${OPENSTACK_HELM_INFRA_COMMIT:-5d622a806e09e19c15189081299dc3155916550b}"


# openstack-helm steps to execute
STEPS="000-install-packages 010-deploy-k8s 020-setup-client 030-ingress 040-ceph 045-ceph-ns-activate 050-mariadb 060-rabbitmq 070-memcached 080-keystone 090-heat 110-ceph-radosgateway 120-glance 140-openvswitch 150-libvirt 160-compute-kit"


# Set up extra disk space if running on CloudLab
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [ -d /usr/local/etc/emulab ]
then
  sudo delgroup docker || true
  "$DIR"/../scripts/cloudlab-disksetup.sh
fi

if [ ! -e ~/openstack-helm-infra ]
then
  cd ~
  git clone https://git.openstack.org/openstack/openstack-helm-infra.git -b "${OPENSTACK_HELM_INFRA_BRANCH}"
  if [ -n "${OPENSTACK_HELM_INFRA_COMMIT}" ]
  then
    cd openstack-helm-infra
    git reset --hard "${OPENSTACK_HELM_INFRA_COMMIT}"
  fi
fi

if [ ! -e ~/openstack-helm ]
then
  cd ~
  git clone https://git.openstack.org/openstack/openstack-helm.git -b "${OPENSTACK_HELM_BRANCH}"
  if [ -n "${OPENSTACK_HELM_COMMIT}" ]
  then
    cd openstack-helm
    git reset --hard "${OPENSTACK_HELM_COMMIT}"
  fi
  sed -i 's/--remote=db:Open_vSwitch,Open_vSwitch,manager_options/--remote=db:Open_vSwitch,Open_vSwitch,manager_options --remote=ptcp:6641/' ~/openstack-helm/openvswitch/templates/bin/_openvswitch-db-server.sh.tpl
fi

# Customizations for CORD
cat <<EOF > /tmp/glance-cord.yaml
---
network:
  api:
    ingress:
      annotations:
        nginx.ingress.kubernetes.io/proxy-body-size: "0"
EOF
export OSH_EXTRA_HELM_ARGS_GLANCE="-f /tmp/glance-cord.yaml"

cat <<EOF > /tmp/libvirt-cord.yaml
---
network:
  backend: []
EOF
export OSH_EXTRA_HELM_ARGS_LIBVIRT="-f /tmp/libvirt-cord.yaml"

cat <<EOF > /tmp/nova-cord.yaml
---
labels:
  api_metadata:
    node_selector_key: openstack-helm-node-class
    node_selector_value: primary
network:
  backend: []
pod:
  replicas:
    api_metadata: 1
    placement: 1
    osapi: 1
    conductor: 1
    consoleauth: 1
    scheduler: 1
    novncproxy: 1
EOF
export OSH_EXTRA_HELM_ARGS_NOVA="-f /tmp/nova-cord.yaml"

cat <<EOF > /tmp/neutron-cord.yaml
---
images:
  tags:
    neutron_server: xosproject/neutron-onos:newton
manifests:
  daemonset_dhcp_agent: false
  daemonset_l3_agent: false
  daemonset_lb_agent: false
  daemonset_metadata_agent: false
  daemonset_ovs_agent: false
  daemonset_sriov_agent: false
network:
  backend: []
  interface:
    tunnel: "eth0"
pod:
  replicas:
    server: 1
conf:
  plugins:
    ml2_conf:
      ml2:
        type_drivers: vxlan
        tenant_network_types: vxlan
        mechanism_drivers: onos_ml2
      ml2_type_vxlan:
        vni_ranges: 1001:2000
      onos:
        url_path: http://onos-cord-ui.default.svc.cluster.local:8181/onos/cordvtn
        username: onos
        password: rocks
EOF
export OSH_EXTRA_HELM_ARGS_NEUTRON="-f /tmp/neutron-cord.yaml"

cd ~/openstack-helm
for STEP in $STEPS
do
    ./tools/deployment/developer/ceph/"$STEP".sh
done
