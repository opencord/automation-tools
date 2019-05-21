SHELL		:= /bin/bash
BUILD		?= /tmp/build
M		?= $(BUILD)/milestones
MAKEDIR		:= $(dir $(realpath $(firstword $(MAKEFILE_LIST))))
SCRIPTDIR	:= $(MAKEDIR)../scripts
WORKSPACE	?= $(HOME)
VENV		?= $(BUILD)/venv/ciab
CIABVALUES	?= $(MAKEDIR)/ciab-values.yaml

KUBESPRAY_VERSION ?= master
KUBESPRAY_VALUES  ?= $(MAKEDIR)/kubespray-values.yml
DOCKER_VERSION	?= 18.06
K8S_VERSION	?= v1.14.1
HELM_VERSION	?= v2.13.1

# used to start logging/monitoring and other infrastructure charts
INFRA_CHARTS	?=
INFRA_PREREQS   = $(foreach chart,$(INFRA_CHARTS),$(M)/$(chart))

KAFKA_CHART_VERSION ?= 0.13.3
KAFKA_POD	:= "pod/cord-kafka-0"

ETCD_OPERATOR_VERSION ?= 0.8.3

HELM_GLOBAL_ARGS ?=
HELM_NEM_ARGS	?= $(HELM_GLOBAL_ARGS)
HELM_ONOS_ARGS	?= $(HELM_GLOBAL_ARGS)

# Targets
ciab: $(M)/omec $(M)/onos $(M)/nem-running

$(M)/setup:
	mkdir -p $(M)
	sudo $(SCRIPTDIR)/cloudlab-disksetup.sh
	sudo apt update; sudo apt install -y software-properties-common python-pip jq httpie
	touch $@

$(BUILD)/kubespray: | $(M)/setup
	mkdir -p $(BUILD)
	cd $(BUILD); git clone https://github.com/kubernetes-incubator/kubespray.git -b $(KUBESPRAY_VERSION)

$(VENV)/bin/activate: | $(M)/setup
	sudo pip install virtualenv
	virtualenv $(VENV) --no-site-packages

$(M)/kubespray-requirements: $(BUILD)/kubespray | $(VENV)/bin/activate
	source "$(VENV)/bin/activate" && \
	pip install -r $(BUILD)/kubespray/requirements.txt
	touch $@

$(M)/k8s-ready: | $(M)/setup $(BUILD)/kubespray $(VENV)/bin/activate $(M)/kubespray-requirements
	source "$(VENV)/bin/activate" && cd $(BUILD)/kubespray; \
	ansible-playbook -b -i inventory/local/hosts.ini \
		-e "{'override_system_hostname' : False, 'disable_swap' : True}" \
		-e "{'docker_version' : $(DOCKER_VERSION)}" \
		-e "{'kube_version' : $(K8S_VERSION)}" \
		-e "{'kube_network_plugin_multus' : True}" \
		-e "{'kube_proxy_mode': iptables}" \
		-e "{'kube_pods_subnet' : 192.168.0.0/17, 'kube_service_addresses' : 192.168.128.0/17}" \
		-e "{'kubeadm_enabled': True}" \
		-e "{'kube_feature_gates' : [SCTPSupport=True]}" \
		-e "{'dns_min_replicas' : 1}" \
		-e "{'helm_enabled' : True, 'helm_version' : $(HELM_VERSION)}" \
		cluster.yml
	mkdir -p $(HOME)/.kube
	sudo cp -f /etc/kubernetes/admin.conf $(HOME)/.kube/config
	sudo chown $(shell id -u):$(shell id -g) $(HOME)/.kube/config
	kubectl wait pod -n kube-system --for=condition=Ready --all
	touch $@

/opt/cni/bin/ptp: | $(M)/k8s-ready
	mkdir -p $(BUILD)/cni-plugins; cd $(BUILD)/cni-plugins; \
	wget https://github.com/containernetworking/plugins/releases/download/v0.8.0/cni-plugins-linux-amd64-v0.8.0.tgz && \
	tar xvfz cni-plugins-linux-amd64-v0.8.0.tgz
	sudo cp $(BUILD)/cni-plugins/ptp /opt/cni/bin/

$(M)/helm-ready: | $(M)/k8s-ready
	helm init --wait --client-only
	helm repo add incubator https://kubernetes-charts-incubator.storage.googleapis.com/
	helm repo add cord https://charts.opencord.org
	touch $@

$(WORKSPACE)/cord/helm-charts: | $(M)/setup
	mkdir -p $(WORKSPACE)/cord
	cd $(WORKSPACE)/cord; git clone https://gerrit.opencord.org/helm-charts

$(M)/omec: | /opt/cni/bin/ptp $(M)/helm-ready $(WORKSPACE)/cord/helm-charts
	cd $(WORKSPACE)/cord/helm-charts/mcord-release; \
	helm upgrade --install $(HELM_GLOBAL_ARGS) mcord-services mcord-services -f $(CIABVALUES)
	$(WORKSPACE)/cord/helm-charts/scripts/wait_for_pods.sh default
	touch $@

$(M)/ovs-setup: $(M)/omec
	sudo apt install openvswitch-switch
	sudo ovs-vsctl --may-exist add-br br-omec
	sudo ovs-vsctl set-controller br-omec tcp:127.0.0.1:31653
	sudo ovs-vsctl set bridge br-omec protocols=OpenFlow13
	for NET in s1u sgi; do \
		peer_idx=`kubectl exec spgwu-0 ip link show $${NET}-net | grep -oP "@if\K.*(?=:)"`; \
		peer_lnk=`ip link | grep "^$${peer_idx}:" | grep -oP ": \K.*(?=@)"`; \
		sudo ip addr flush $$peer_lnk; \
		sudo ovs-vsctl --may-exist add-port br-omec $$peer_lnk; \
	done
	touch $@

$(M)/kafka: | $(M)/helm-ready $(WORKSPACE)/cord/helm-charts
	cd $(WORKSPACE)/cord/helm-charts && \
	helm upgrade --install $(HELM_GLOBAL_ARGS) cord-kafka -f examples/kafka-single.yaml incubator/kafka --version $(KAFKA_CHART_VERSION)
	touch $@

$(M)/kafka-running: | $(M)/kafka
	kubectl wait $(KAFKA_POD) --for condition=Ready --timeout=180s
	touch $@

$(M)/nem-monitoring: | $(M)/kafka-running
	helm upgrade --install $(HELM_GLOBAL_ARGS) nem-monitoring cord/nem-monitoring --version 1.0.1
	$(WORKSPACE)/cord/helm-charts/scripts/wait_for_pods.sh
	touch $@

# Dependency on NEM is there to force ordering for parallel install
# The idea is to install ONOS while NEM is initializing
$(M)/onos: | $(M)/kafka-running $(M)/nem $(M)/ovs-setup $(INFRA_PREREQS)
	helm upgrade --install $(HELM_ONOS_ARGS) onos cord/onos --version 1.1.0
	kubectl wait pod --for=condition=Ready -l app=onos --timeout=180s
	timeout 360s bash -c \
	"until curl -u karaf:karaf http://node1:30120/onos/v1/applications; do \
		echo 'Waiting for ONOS to become ready'; \
		sleep 5; \
	done"
	touch $@

$(M)/nem: | $(M)/kafka-running $(INFRA_PREREQS)
	helm upgrade --install $(HELM_NEM_ARGS) xos-core cord/xos-core --version 2.3.3
	helm upgrade --install $(HELM_NEM_ARGS) mcord-profile cord/mcord --version 1.0.11
	helm upgrade --install $(HELM_NEM_ARGS) base-kubernetes cord/base-kubernetes --version 1.0.2
	touch $@

$(M)/nem-running: | $(M)/nem
	$(WORKSPACE)/cord/helm-charts/scripts/wait_for_pods.sh
	timeout 60s bash -c \
	"until ! http -a admin@opencord.org:letmein GET http://node1:30001/xosapi/v1/core/serviceinstanceattributes | \
	jq '.items[].backend_status' | grep -v OK; do \
		echo 'waiting for ONOS config to sync';\
		sleep 5; \
	done"
	timeout 60s bash -c \
	"until ! http -a admin@opencord.org:letmein GET http://node1:30001/xosapi/v1/onos/onosapps | \
	jq '.items[].backend_status' | grep -v OK; do \
		echo 'waiting for ONOS apps to sync'; \
		sleep 5; \
	done"
	touch $@

remove-chart-milestones:
	cd $(M); rm -f kafka kafka-running omec ovs-setup onos nem nem-running logging nem-monitoring

clean-charts: remove-chart-milestones
	helm delete --purge $(shell helm ls -q | grep -v docker-registry)

clean:
	helm delete --purge $(shell helm ls -q | grep -v docker-registry)
	sudo ovs-vsctl del-br br-omec
	source "$(VENV)/bin/activate" && cd $(BUILD)/kubespray; \
	ansible-playbook -b -i inventory/local/hosts.ini reset.yml
	@if [ -d /usr/local/etc/emulab ]; then \
		mount | grep /mnt/extra/kubelet/pods | cut -d" " -f3 | sudo xargs umount; \
		sudo rm -rf /mnt/extra/kubelet; \
	fi
	rm -rf $(BUILD)
