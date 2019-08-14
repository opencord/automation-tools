SHELL		:= /bin/bash
BUILD		?= /tmp/build
M		?= $(BUILD)/milestones
MAKEDIR		:= $(dir $(realpath $(firstword $(MAKEFILE_LIST))))
SCRIPTDIR	:= $(MAKEDIR)../scripts
RESOURCEDIR	:= $(MAKEDIR)/resources
WORKSPACE	?= $(HOME)
VENV		?= $(BUILD)/venv/ciab
CIABVALUES	?= $(MAKEDIR)/comac-in-a-box-values.yaml

KUBESPRAY_VERSION ?= release-2.10
DOCKER_VERSION	?= 18.06
K8S_VERSION	?= v1.14.3
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

cpu_family	:= $(shell lscpu | grep 'CPU family:' | awk '{print $$3}')
cpu_model	:= $(shell lscpu | grep 'Model:' | awk '{print $$2}')
os_vendor	:= $(shell lsb_release -i -s)
os_release	:= $(shell lsb_release -r -s)

# TODO: include CORD platform
ciab: $(M)/system_check $(M)/omec $(M)/oaisim

.PHONY: ciab run-test reset-test clean

$(M):
	mkdir -p $(M)

$(M)/system_check: | $(M)
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

# TODO: need to connect ONOS
$(M)/ovs-setup: | $(M)/setup
	sudo apt install -y openvswitch-switch
	sudo ovs-vsctl --may-exist add-br br-s1u-net
	sudo ovs-vsctl --may-exist add-port br-s1u-net s1u-enb -- set Interface s1u-enb type=internal
	sudo ip link set s1u-enb address 0a:00:00:00:00:01
	sudo ip addr add 119.0.0.253/24 dev s1u-enb || true
	sudo ip link set s1u-enb up
	touch $@

/opt/cni/bin/simpleovs: | $(M)/k8s-ready
	sudo cp $(RESOURCEDIR)/simpleovs /opt/cni/bin/

$(M)/omec: | $(M)/ovs-setup $(M)/helm-ready $(WORKSPACE)/cord/helm-charts /opt/cni/bin/simpleovs
	cd $(WORKSPACE)/cord/helm-charts/mcord-release; \
	helm upgrade --install $(HELM_GLOBAL_ARGS) mcord-services mcord-services -f $(CIABVALUES)
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
		--set conf.enb.networks.s1_mme.interface=$(mme_iface)
	$(WORKSPACE)/cord/helm-charts/scripts/wait_for_pods.sh default
	@timeout 60s bash -c \
	"until ip addr show oip1 | grep -q inet; \
	do \
		echo 'Waiting for UE 1 gets IP address'; \
		sleep 3; \
	done"
	touch $@

$(M)/router: | /opt/cni/bin/simpleovs $(M)/ovs-setup
	kubectl apply -f $(RESOURCEDIR)/quagga.yaml
	kubectl wait pod --for=condition=Ready -l app=quagga
	$(eval spgwu_ip=$(shell kubectl get pod -ojson spgwu-0 2>/dev/null | \
		jq -r '.metadata.annotations["k8s.v1.cni.cncf.io/networks-status"]' | \
		jq -r '.[] | select(.name=="sgi-net") | .ips[0]'))
	kubectl exec router ip route add 16.0.0.0/8 via $(spgwu_ip)
	touch $@

test: | $(M)/router
	@timeout 60s bash -c \
	"until timeout 3 ping -I oip1 13.1.1.254 -c 1 > /dev/null 2>&1; do \
		echo 'Waiting for DP to be ready'; \
	done"
	ping -I oip1 13.1.1.254 -c 3

reset-test:
	kubectl delete po router || true
	helm delete --purge oaisim || true
	helm delete --purge mcord-services || true
	cd $(M); rm -f router oaisim omec

clean: reset-test
	helm delete --purge $(shell helm ls -q) || true
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
