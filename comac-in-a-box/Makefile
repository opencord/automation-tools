SHELL		:= /bin/bash
BUILD		?= /tmp/build
M		?= $(BUILD)/milestones
MAKEDIR		:= $(dir $(realpath $(firstword $(MAKEFILE_LIST))))
SCRIPTDIR	:= $(MAKEDIR)../scripts
WORKSPACE	?= $(HOME)
VENV		?= $(BUILD)/venv/ciab
CIABVALUES	?= $(MAKEDIR)/ciab-values.yaml

KUBESPRAY_VERSION ?= master
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
ciab: $(M)/omec $(M)/onos-progran $(M)/nem-running

$(M):
	mkdir -p $(M)

$(M)/setup: | $(M)
	$(if $(value SRIOV_PF),,$(error Undefined SRIOV_PF))
	sudo $(SCRIPTDIR)/nodesetup.sh $(SRIOV_PF)
	sudo $(SCRIPTDIR)/cloudlab-disk-setup.sh
	sudo $(SCRIPTDIR)/portcheck.sh	 
	sudo apt update
	sudo apt install -y httpie jq software-properties-common
	touch $@

$(BUILD)/kubespray:
	mkdir -p $(BUILD)
	cd $(BUILD); git clone https://github.com/kubernetes-incubator/kubespray.git -b $(KUBESPRAY_VERSION)

$(VENV)/bin/activate:
	sudo apt install -y python-pip
	sudo pip install virtualenv
	virtualenv $(VENV) --no-site-packages

$(M)/k8s: | $(M)/setup $(BUILD)/kubespray $(VENV)/bin/activate
	source "$(VENV)/bin/activate" && \
	cd $(BUILD)/kubespray && \
	pip install -r requirements.txt && \
	ansible-playbook -b -i inventory/local/hosts.ini \
		-e "{'override_system_hostname' : False, 'disable_swap' : True}" \
		-e "{'docker_version' : $(DOCKER_VERSION), 'docker_insecure_registries': [$(REGISTRY)]}" \
		-e "{'kube_version' : $(K8S_VERSION)}" \
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

$(M)/helm-init: | $(M)/k8s
	helm init --wait --client-only
	helm repo add incubator https://kubernetes-charts-incubator.storage.googleapis.com/
	helm repo add cord https://charts.opencord.org
	touch $@

$(WORKSPACE)/cord/helm-charts: | $(M)/setup
	mkdir -p $(WORKSPACE)/cord
	cd $(WORKSPACE)/cord; git clone https://gerrit.opencord.org/helm-charts

$(M)/kafka: | $(M)/helm-init $(WORKSPACE)/cord/helm-charts
	cd $(WORKSPACE)/cord/helm-charts && \
	helm upgrade --install $(HELM_GLOBAL_ARGS) cord-kafka --version $(KAFKA_CHART_VERSION) -f examples/kafka-single.yaml incubator/kafka
	touch $@

$(M)/kafka-running: | $(M)/kafka
	kubectl wait $(KAFKA_POD) --for condition=Ready --timeout=180s
	touch $@

$(M)/nem-monitoring: | $(M)/kafka-running
	cd $(WORKSPACE)/cord/helm-charts && \
	helm dep up nem-monitoring  && \
	helm upgrade --install $(HELM_GLOBAL_ARGS) nem-monitoring nem-monitoring
	$(WORKSPACE)/cord/helm-charts/scripts/wait_for_pods.sh
	touch $@

$(M)/logging: | $(M)/kafka-running
	cd $(WORKSPACE)/cord/helm-charts && \
	helm dep up logging && \
	helm upgrade --install $(HELM_GLOBAL_ARGS) logging -f examples/logging-single.yaml logging
	$(WORKSPACE)/cord/helm-charts/scripts/wait_for_pods.sh
	touch $@

# Dependency on NEM is there to force ordering for parallel install
# The idea is to install ONOS while NEM is initializing
$(M)/onos: | $(M)/kafka-running $(M)/nem $(INFRA_PREREQS)
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install $(HELM_ONOS_ARGS) onos onos -f $(CIABVALUES)
	kubectl wait pod --for=condition=Ready -l app=onos --timeout=180s
	@timeout 180s bash -c \
	"until curl -u karaf:karaf http://node1:30120/onos/v1/applications; do \
		echo 'Waiting for ONOS to become ready'; \
		sleep 5; \
	done"
	touch $@

$(M)/mcord-setup: | $(M)/helm-init $(WORKSPACE)/cord/helm-charts
	$(if $(value SRIOV_PF),,$(error Undefined SRIOV_PF))
	$(eval pci_addr=$(shell sudo lshw -c network -businfo | grep $(SRIOV_PF) | \
		cut -d' ' -f1 | cut -d'@' -f2))
	cd $(WORKSPACE)/cord/helm-charts/mcord-release; \
	helm upgrade --install --namespace kube-system $(HELM_GLOBAL_ARGS) mcord-setup --set sriov.devicepci=$(pci_addr) mcord-setup
	kubectl wait pod -n kube-system --for=condition=Ready -l name=sriov-device-plugin
	touch $@

$(M)/etcd-operator: | $(M)/helm-init
	helm upgrade --install --namespace kube-system etcd-operator --version $(ETCD_OPERATOR_VERSION) stable/etcd-operator
	@timeout 60s bash -c "until kubectl get etcd; do \
		echo 'Waiting for etcdclusters CRD to be available'; \
		sleep 5; \
	done"
	touch $@

$(M)/etcd-cluster: | $(M)/helm-init $(WORKSPACE)/cord/helm-charts $(M)/etcd-operator
	cd $(WORKSPACE)/cord/helm-charts; \
	helm upgrade --install --namespace kube-system $(HELM_GLOBAL_ARGS) etcd-cluster etcd-cluster -f $(CIABVALUES)
	kubectl wait pod -n kube-system --for=condition=Ready -l app=etcd
	touch $@

$(M)/omec: | $(M)/mcord-setup $(M)/etcd-cluster
	cd $(WORKSPACE)/cord/helm-charts/mcord-release; \
	helm upgrade --install --namespace omec $(HELM_GLOBAL_ARGS) mcord-services mcord-services -f $(CIABVALUES)
	$(WORKSPACE)/cord/helm-charts/scripts/wait_for_pods.sh omec
	touch $@

$(M)/onos-progran: | $(M)/kafka-running $(M)/nem $(INFRA_PREREQS)
	cd $(WORKSPACE)/cord/helm-charts; \
	helm upgrade --install $(HELM_ONOS_ARGS) onos-progran -f $(CIABVALUES) onos-progran
	$(WORKSPACE)/cord/helm-charts/scripts/wait_for_pods.sh default
	@timeout 60s bash -c \
	"until curl -I -u karaf:karaf http://node1:30121/onos/v1/applications | grep -q 200; do \
		echo 'Waiting for ONOS to be ready'; \
		sleep 5; \
	done"
	http -a karaf:karaf --ignore-stdin DELETE http://node1:30121/onos/v1/applications/org.onosproject.progran/active
	http -a karaf:karaf --ignore-stdin POST http://node1:30121/onos/v1/applications/org.onosproject.progran/active
	touch $@

$(M)/nem: | $(M)/kafka-running $(INFRA_PREREQS)
	cd $(WORKSPACE)/cord/helm-charts; helm dep update xos-core
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install $(HELM_NEM_ARGS) xos-core xos-core -f $(CIABVALUES)
	cd $(WORKSPACE)/cord/helm-charts; helm dep update xos-profiles/mcord
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install $(HELM_NEM_ARGS) mcord-profile xos-profiles/mcord -f $(CIABVALUES)
	cd $(WORKSPACE)/cord/helm-charts; helm dep update xos-profiles/base-kubernetes
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install $(HELM_NEM_ARGS) base-kubernetes xos-profiles/base-kubernetes -f $(CIABVALUES)
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
	cd $(M); rm -f kafka kafka-running onos mcord-setup etcd-operator etcd-cluster \
	omec onos-progran nem nem-running logging nem-monitoring

clean-charts: remove-chart-milestones
	helm delete --purge $(shell helm ls -q | grep -v docker-registry)

clean:
	source "$(VENV)/bin/activate" && \
	cd $(BUILD)/kubespray && \
	ansible-playbook -b -i inventory/local/hosts.ini reset.yml
	@if [ -d /usr/local/etc/emulab ]; then \
		mount | grep /mnt/extra/kubelet/pods | cut -d" " -f3 | sudo xargs umount; \
		sudo rm -rf /mnt/extra/kubelet; \
	fi
	rm -rf $(BUILD)
