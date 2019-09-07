SHELL		:= /bin/bash
BUILD		?= /tmp/build
M		?= $(BUILD)/milestones
MAKEDIR		:= $(dir $(realpath $(firstword $(MAKEFILE_LIST))))
SCRIPTDIR	:= $(MAKEDIR)../scripts
RESOURCEDIR	:= $(MAKEDIR)/resources
WORKSPACE	?= $(HOME)
VENV		?= $(BUILD)/venv/ciab
CIABVALUES	?= $(MAKEDIR)/comac-in-a-box-values.yaml

KUBESPRAY_VERSION ?= release-2.11
DOCKER_VERSION	?= 18.09
K8S_VERSION	?= v1.15.3
HELM_VERSION	?= v2.14.2

# used to start logging/monitoring and other infrastructure charts
INFRA_CHARTS	?=
INFRA_PREREQS   = $(foreach chart,$(INFRA_CHARTS),$(M)/$(chart))

KAFKA_CHART_VERSION ?= 0.13.3
KAFKA_POD	:= "pod/cord-kafka-0"

HELM_GLOBAL_ARGS ?=
HELM_NEM_ARGS	?= $(HELM_GLOBAL_ARGS)
HELM_ONOS_ARGS	?= $(HELM_GLOBAL_ARGS)

cpu_family	:= $(shell lscpu | grep 'CPU family:' | awk '{print $$3}')
cpu_model	:= $(shell lscpu | grep 'Model:' | awk '{print $$2}')
os_vendor	:= $(shell lsb_release -i -s)
os_release	:= $(shell lsb_release -r -s)

ciab: $(M)/system-check $(M)/omec $(M)/oaisim $(M)/comac-platform

.PHONY: ciab test reset-test clean

$(M):
	mkdir -p $(M)

$(M)/system-check: | $(M)
	@if [[ $(cpu_family) -eq 6 ]]; then \
		if [[ $(cpu_model) -lt 60 ]]; then \
			echo "FATAL: haswell CPU or newer is required."; \
			exit 1; \
		fi \
	else \
		echo "FATAL: unsupported CPU family."; \
		exit 1; \
	fi
	@if [[ $(os_vendor) =~ (Ubuntu) ]]; then \
		if [[ ! $(os_release) =~ (16.04) ]]; then \
			echo "WARN: $(os_vendor) $(os_release) has not been tested."; \
		fi; \
		if dpkg --compare-versions 4.15 gt $(shell uname -r); then \
			echo "FATAL: kernel 4.15 or later is required."; \
			echo "Please upgrade your kernel by running" \
			"apt install --install-recommends linux-generic-hwe-$(os_release)"; \
			exit 1; \
		fi \
	else \
		echo "FAIL: unsupported OS."; \
		exit 1; \
	fi
	touch $@

$(M)/setup: | $(M)
	sudo $(SCRIPTDIR)/cloudlab-disksetup.sh
	sudo apt update; sudo apt install -y software-properties-common python-pip jq httpie ipvsadm
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
		-e "{'docker_iptables_enabled' : True}" \
		-e "{'kube_version' : $(K8S_VERSION)}" \
		-e "{'kube_network_plugin_multus' : True, 'multus_version' : stable}" \
		-e "{'kube_proxy_mode': iptables}" \
		-e "{'kube_pods_subnet' : 192.168.0.0/17, 'kube_service_addresses' : 192.168.128.0/17}" \
		-e "{'kube_apiserver_node_port_range' : 2000-36767}" \
		-e "{'kubeadm_enabled': True}" \
		-e "{'kube_feature_gates' : [SCTPSupport=True]}" \
		-e "{'kubelet_custom_flags' : [--allowed-unsafe-sysctls=net.*]}" \
		-e "{'dns_min_replicas' : 1}" \
		-e "{'helm_enabled' : True, 'helm_version' : $(HELM_VERSION)}" \
		cluster.yml
	mkdir -p $(HOME)/.kube
	sudo cp -f /etc/kubernetes/admin.conf $(HOME)/.kube/config
	sudo chown $(shell id -u):$(shell id -g) $(HOME)/.kube/config
	kubectl wait pod -n kube-system --for=condition=Ready --all
	touch $@

$(M)/helm-ready: | $(M)/k8s-ready
	helm init --wait --client-only
	helm repo add incubator https://kubernetes-charts-incubator.storage.googleapis.com/
	helm repo add cord https://charts.opencord.org
	touch $@

$(WORKSPACE)/cord/helm-charts: | $(M)/setup
	mkdir -p $(WORKSPACE)/cord
	cd $(WORKSPACE)/cord; git clone https://gerrit.opencord.org/helm-charts

$(WORKSPACE)/cord/cord-platform: | $(M)/setup
	mkdir -p $(WORKSPACE)/cord
	cd $(WORKSPACE)/cord; git clone https://gerrit.opencord.org/cord-platform

$(WORKSPACE)/cord/comac-helm-charts: | $(M)/setup
	mkdir -p $(WORKSPACE)/cord
	cd $(WORKSPACE)/cord; git clone https://gerrit.opencord.org/comac-helm-charts

$(M)/cord-platform: | $(M)/helm-ready $(WORKSPACE)/cord/cord-platform
	cd $(WORKSPACE)/cord/cord-platform && \
	helm dep update cord-platform && \
	helm upgrade --install $(HELM_GLOBAL_ARGS) cord-platform cord-platform -f $(CIABVALUES)
	touch $@

$(M)/comac-platform: | $(M)/helm-ready $(WORKSPACE)/cord/comac-helm-charts $(M)/cord-platform
	cd $(WORKSPACE)/cord/comac-helm-charts && \
	helm dep update comac-platform && \
	helm upgrade --install $(HELM_GLOBAL_ARGS) comac-platform comac-platform -f $(CIABVALUES)
	touch $@

/opt/cni/bin/simpleovs: | $(M)/k8s-ready
	sudo cp $(RESOURCEDIR)/simpleovs /opt/cni/bin/

/opt/cni/bin/static: | $(M)/k8s-ready
	mkdir -p $(BUILD)/cni-plugins; cd $(BUILD)/cni-plugins; \
	wget https://github.com/containernetworking/plugins/releases/download/v0.8.2/cni-plugins-linux-amd64-v0.8.2.tgz && \
	tar xvfz cni-plugins-linux-amd64-v0.8.2.tgz
	sudo cp $(BUILD)/cni-plugins/static /opt/cni/bin/

# TODO: need to connect ONOS
$(M)/fabric: | $(M)/setup /opt/cni/bin/simpleovs
	sudo apt install -y openvswitch-switch
	sudo ovs-vsctl --may-exist add-br br-s1u-net
	sudo ovs-vsctl --may-exist add-port br-s1u-net s1u-enb -- set Interface s1u-enb type=internal
	sudo ip addr add 119.0.0.4/24 dev s1u-enb || true
	sudo ip link set s1u-enb up
	kubectl apply -f $(RESOURCEDIR)/sgi-net.yaml
	kubectl apply -f $(RESOURCEDIR)/router.yaml
	kubectl wait pod --for=condition=Ready -l app=router --timeout=60s
	kubectl exec router ip route add 16.0.0.0/8 via 13.1.1.3
	kubectl delete net-attach-def sgi-net
	touch $@

$(M)/omec: | $(M)/helm-ready $(WORKSPACE)/cord/helm-charts /opt/cni/bin/simpleovs /opt/cni/bin/static $(M)/fabric
	cd $(WORKSPACE)/cord/helm-charts/omec; \
	helm dep up omec-data-plane && \
	helm dep up omec-control-plane && \
	helm upgrade --install $(HELM_GLOBAL_ARGS) omec-data-plane omec-data-plane -f $(CIABVALUES) && \
	helm upgrade --install $(HELM_GLOBAL_ARGS) omec-control-plane omec-control-plane -f $(CIABVALUES)
	$(WORKSPACE)/cord/helm-charts/scripts/wait_for_pods.sh default
	touch $@

# UE images includes kernel module, ue_ip.ko
# which should be built in the exactly same kernel version of the host machine
$(BUILD)/openairinterface: | $(M)/setup
	mkdir -p $(BUILD)
	cd $(BUILD); git clone https://github.com/opencord/openairinterface.git

$(M)/ue-image: | $(M)/k8s-ready $(BUILD)/openairinterface
	cd $(BUILD)/openairinterface; \
	sudo docker build . --target lte-uesoftmodem \
		--build-arg build_base=omecproject/oai-base:1.0.0 \
		--file Dockerfile.ue \
		--tag omecproject/lte-uesoftmodem:1.0.0
	touch $@

$(M)/oaisim: | $(M)/omec $(M)/ue-image
	sudo ip addr add 127.0.0.2/8 dev lo || true
	$(eval mme_iface=$(shell ip -4 route list default | awk -F 'dev' '{ print $$2; exit }' | awk '{ print $$1 }'))
	cd $(WORKSPACE)/cord/helm-charts; \
	helm upgrade --install $(HELM_GLOBAL_ARGS) oaisim oaisim -f $(CIABVALUES) \
		--set config.enb.networks.s1_mme.interface=$(mme_iface)
	$(WORKSPACE)/cord/helm-charts/scripts/wait_for_pods.sh default
	@timeout 60s bash -c \
	"until ip addr show oip1 | grep -q inet; \
	do \
		echo 'Waiting for UE 1 gets IP address'; \
		sleep 3; \
	done"
	touch $@

test: | $(M)/fabric $(M)/omec $(M)/oaisim
	@timeout 120s bash -c \
	"until timeout 3 ping -I oip1 13.1.1.254 -c 1 > /dev/null 2>&1; do \
		echo 'Waiting for DP to be ready'; \
	done"
	ping -I oip1 13.1.1.254 -c 3

reset-test:
	helm delete --purge oaisim || true
	helm delete --purge omec-control-plane || true
	helm delete --purge omec-data-plane || true
	cd $(M); rm -f oaisim omec

clean: reset-test
	helm delete --purge $(shell helm ls -q) || true
	kubectl delete po router
	kubectl delete net-attach-def sgi-net
	sudo ovs-vsctl del-br br-s1u-net || true
	sudo ovs-vsctl del-br br-sgi-net || true
	sudo apt remove --purge openvswitch-switch -y
	source "$(VENV)/bin/activate" && cd $(BUILD)/kubespray; \
	ansible-playbook -b -i inventory/local/hosts.ini reset.yml
	@if [ -d /usr/local/etc/emulab ]; then \
		mount | grep /mnt/extra/kubelet/pods | cut -d" " -f3 | sudo xargs umount; \
		sudo rm -rf /mnt/extra/kubelet; \
	fi
	rm -rf $(M)
