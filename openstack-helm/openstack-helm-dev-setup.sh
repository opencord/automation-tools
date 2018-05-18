#!/bin/bash
set -xe

STEPS="000-install-packages 010-deploy-k8s 020-setup-client 030-ingress 040-ceph 045-ceph-ns-activate 050-mariadb 060-rabbitmq 070-memcached 080-keystone 090-heat 110-ceph-radosgateway 120-glance 140-openvswitch 150-libvirt"

sudo delgroup docker || true

# Set up extra disk space if running on CloudLab
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
[ -d /usr/local/etc/emulab ] && $DIR/cloudlab-disk-setup.sh

cd ~
[ ! -e openstack-helm-infra ] && git clone https://git.openstack.org/openstack/openstack-helm-infra.git
[ ! -e openstack-helm ] && git clone https://git.openstack.org/openstack/openstack-helm.git

cd ~/openstack-helm
for STEP in $STEPS
do
    ./tools/deployment/developer/ceph/$STEP.sh
done

# Customizations for CORD
cat <<EOF > /tmp/nova.yaml
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
    placement: 2
    osapi: 2
    conductor: 2
    consoleauth: 2
    scheduler: 1
    novncproxy: 1
EOF
helm upgrade --install nova ./nova --namespace=openstack --values=/tmp/nova.yaml

cat <<EOF > /tmp/neutron.yaml
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
    server: 2
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
helm upgrade --install neutron ./neutron --namespace=openstack --values=/tmp/neutron.yaml
