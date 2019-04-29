SHELL           := /bin/bash
BUILD           ?= /tmp
M               ?= $(BUILD)/milestones
MAKEDIR         := $(dir $(realpath $(firstword $(MAKEFILE_LIST))))
WORKSPACE       ?= $(HOME)
VIRTUALENV      ?= $(WORKSPACE)/cord/test
SEBAVALUES      ?= configs/seba-ponsim.yaml
TESTTAGS        ?= stable

# used to start logging/monitoring and other infrastructure charts
INFRA_CHARTS    ?=
INFRA_PREREQS   = $(foreach chart,$(INFRA_CHARTS),$(M)/$(chart))

DOCKER_VERSION  ?= "17.06"

K8S_VERSION     ?= "1.12.7"

HELM_VERSION    ?= "2.12.1"
HELM_SHA256SUM  ?= "891004bec55431b39515e2cedc4f4a06e93782aa03a4904f2bd742b168160451"
HELM_PLATFORM   ?= "linux-amd64"

KAFKA_CHART_VERSION  ?= 0.13.3
KAFKA_POD := "pod/cord-kafka-0"

ETCD_OPERATOR_VERSION ?= 0.8.3

# Arguments passed to helm install/upgrade for all or specific charts
HELM_GLOBAL_ARGS ?=
HELM_NEM_ARGS    ?= $(HELM_GLOBAL_ARGS)
HELM_ONOS_ARGS   ?= $(HELM_GLOBAL_ARGS)
HELM_VOLTHA_ARGS ?= $(HELM_GLOBAL_ARGS)

NEM_WORKFLOW ?= att-workflow

# Targets
ponsim: $(M)/siab

bbsim: $(M)/bbsim-tosca

both: BBSIM_DHCP_TOSCA =
both: $(M)/siab $(M)/bbsim-tosca

# https://ftp.gnu.org/old-gnu/Manuals/make-3.79.1/html_chapter/make_6.html#SEC69
latest: SEBAVALUES := configs/seba-ponsim-latest.yaml
latest: ponsim

stable: SEBAVALUES := configs/seba-ponsim.yaml
stable: ponsim

siab-1.0: SEBAVALUES := configs/siab-v1.0.0.yaml
siab-1.0: KAFKA_POD := "pod/cord-platform-kafka-0"
# Parallel make won't work here; need to install seba-1.0.0 before siab
siab-1.0: $(M)/seba-1.0.0 $(M)/siab

$(M)/setup:
	sudo $(MAKEDIR)/../scripts/portcheck.sh
	mkdir -p $(M)
	sudo apt update
	sudo apt install -y httpie jq software-properties-common
	sudo swapoff -a
	touch $@

/usr/bin/docker: | $(M)/setup
	sudo apt-key adv --keyserver keyserver.ubuntu.com --recv 0EBFCD88
	sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(shell lsb_release -cs) stable"
	sudo apt update
	sudo apt install -y "docker-ce=${DOCKER_VERSION}*"

/usr/bin/kubeadm: | $(M)/setup /usr/bin/docker
	curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
	echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" > /tmp/kubernetes.list
	sudo cp /tmp/kubernetes.list /etc/apt/sources.list.d/kubernetes.list
	sudo apt update
	sudo apt install -y "kubeadm=${K8S_VERSION}-*" "kubelet=${K8S_VERSION}-*" "kubectl=${K8S_VERSION}-*"

/usr/local/bin/helm:
	curl -L -o /tmp/helm.tgz "https://storage.googleapis.com/kubernetes-helm/helm-v${HELM_VERSION}-${HELM_PLATFORM}.tar.gz"
	echo "${HELM_SHA256SUM}  /tmp/helm.tgz" | sha256sum -c -
	cd /tmp; tar -xzvf helm.tgz; sudo mv ${HELM_PLATFORM}/helm /usr/local/bin/helm
	sudo chmod a+x /usr/local/bin/helm
	rm -rf /tmp/helm.tgz /tmp/${HELM_PLATFORM}

$(M)/kubeadm: | $(M)/setup /usr/bin/kubeadm
	sudo kubeadm init --pod-network-cidr=192.168.0.0/16
	mkdir -p $(HOME)/.kube
	sudo cp -f /etc/kubernetes/admin.conf $(HOME)/.kube/config
	sudo chown $(shell id -u):$(shell id -g) $(HOME)/.kube/config
	kubectl apply -f https://docs.projectcalico.org/v3.3/getting-started/kubernetes/installation/hosted/rbac-kdd.yaml
	kubectl apply -f https://docs.projectcalico.org/v3.3/getting-started/kubernetes/installation/hosted/kubernetes-datastore/calico-networking/1.7/calico.yaml
	kubectl taint nodes --all node-role.kubernetes.io/master-
	touch $@

$(M)/helm-init: | $(M)/kubeadm /usr/local/bin/helm
	kubectl create serviceaccount --namespace kube-system tiller
	kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
	helm init --service-account tiller
	until helm ls >& /dev/null; \
	do \
		echo "Waiting for Helm to be ready"; \
		sleep 5; \
	done
	helm repo add incubator https://kubernetes-charts-incubator.storage.googleapis.com/
	helm repo add cord https://charts.opencord.org
	touch $@

$(WORKSPACE)/cord/helm-charts: | $(M)/setup
	mkdir -p $(WORKSPACE)/cord
	cd $(WORKSPACE)/cord; git clone https://gerrit.opencord.org/helm-charts

$(M)/kafka: | $(WORKSPACE)/cord/helm-charts $(M)/helm-init
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
# The idea is to install VOLTHA / ONOS / Mininet while NEM is initializing
$(M)/onos: | $(M)/kafka-running $(M)/nem $(INFRA_PREREQS)
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install $(HELM_ONOS_ARGS) onos onos -f $(SEBAVALUES)
	touch $@

# SEBA-440 Sometimes VOLTHA install fails with 'namespaces "voltha" not found'
# Work around by repeatedly trying to install the chart until it succeeds
$(M)/voltha: | $(M)/kafka-running $(INFRA_PREREQS) $(M)/etcd-operator-ready
	sudo sh -c "echo 1048576 > /proc/sys/fs/inotify/max_user_watches"
	cd $(WORKSPACE)/cord/helm-charts; helm dep up voltha
	cd $(WORKSPACE)/cord/helm-charts; \
		for i in 1 2 3; \
		do \
			helm upgrade --install $(HELM_VOLTHA_ARGS) voltha voltha -f $(SEBAVALUES) && break; \
			echo "VOLTHA chart install failed; cleaning up and trying again"; \
			helm delete --purge voltha; \
			until ! kubectl get namespace voltha; \
			do \
				sleep 5; \
			done; \
			sleep 5; \
		done
	touch $@

$(M)/etcd-operator-ready: | $(WORKSPACE)/cord/helm-charts $(M)/helm-init
	cd $(WORKSPACE)/cord/helm-charts; \
	helm upgrade --install etcd-operator --version $(ETCD_OPERATOR_VERSION) stable/etcd-operator -f $(SEBAVALUES)
	timeout 120s bash -c "until kubectl get crd | grep etcdclusters; do echo 'Waiting for etcdclusters CRD to be available'; sleep 5; done"
	touch $@

$(M)/voltha-running: | $(M)/voltha
	timeout 300s bash -c "until kubectl get pod|grep etcd-cluster|grep 1/1; do echo 'Waiting for etcd-cluster to be ready'; sleep 10; done"
	$(WORKSPACE)/cord/helm-charts/scripts/wait_for_pods.sh voltha
	touch $@

$(M)/ponsim: | $(M)/voltha
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install $(HELM_GLOBAL_ARGS) ponnet ponnet
	$(WORKSPACE)/cord/helm-charts/scripts/wait_for_pods.sh kube-system
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install $(HELM_GLOBAL_ARGS) ponsimv2 ponsimv2 -f $(SEBAVALUES)
	touch $@

$(M)/pon0_fwd: | $(M)/ponsim
	echo 8 > /tmp/pon0_group_fwd_mask
	until sudo cp /tmp/pon0_group_fwd_mask /sys/class/net/pon0/bridge/group_fwd_mask; \
	do \
		echo "waiting for pon0..."; \
		sleep 5; \
	done
	rm /tmp/pon0_group_fwd_mask
	touch $@

# Make sure that we're using the ofdpa-ovs driver with OvS.
$(M)/mininet: | $(M)/onos $(M)/ponsim $(M)/pon0_fwd $(M)/ponsim-tosca
	sudo modprobe openvswitch
	timeout 60s bash -c "until ! http -a admin@opencord.org:letmein GET http://127.0.0.1:30001/xosapi/v1/fabric/switches|jq '.items[].driver'|grep -v ofdpa-ovs ; do echo 'waiting for switch driver == ofdpa-ovs'; sleep 5; done"
	timeout 60s bash -c "until ! http -a admin@opencord.org:letmein GET http://127.0.0.1:30001/xosapi/v1/fabric/switches|jq '.items[].backend_status'|grep -v OK; do echo 'waiting for switch driver to sync'; sleep 5; done"
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install $(HELM_GLOBAL_ARGS) mininet mininet -f $(SEBAVALUES)
	touch $@

$(M)/nem: | $(M)/kafka-running $(INFRA_PREREQS)
	cd $(WORKSPACE)/cord/helm-charts; helm dep update xos-core
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install $(HELM_NEM_ARGS) xos-core xos-core -f $(SEBAVALUES)
	cd $(WORKSPACE)/cord/helm-charts; helm dep update xos-profiles/seba-services
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install $(HELM_NEM_ARGS) seba-services xos-profiles/seba-services -f $(SEBAVALUES)
	cd $(WORKSPACE)/cord/helm-charts; helm dep update workflows/$(NEM_WORKFLOW)
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install $(HELM_NEM_ARGS) $(NEM_WORKFLOW) workflows/$(NEM_WORKFLOW) -f $(SEBAVALUES)
	cd $(WORKSPACE)/cord/helm-charts; helm dep update xos-profiles/base-kubernetes
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install $(HELM_NEM_ARGS) base-kubernetes xos-profiles/base-kubernetes -f $(SEBAVALUES)
	touch $@

$(M)/nem-running: | $(M)/nem
	$(WORKSPACE)/cord/helm-charts/scripts/wait_for_pods.sh
	touch $@

$(M)/ponsim-tosca: | $(M)/onos $(M)/nem-running
	timeout 60s bash -c "until ! http -a admin@opencord.org:letmein GET http://127.0.0.1:30001/xosapi/v1/core/serviceinstanceattributes|jq '.items[].backend_status'|grep -v OK; do echo 'waiting for ONOS config to sync'; sleep 5; done"
	timeout 60s bash -c "until ! http -a admin@opencord.org:letmein GET http://127.0.0.1:30001/xosapi/v1/onos/onosapps|jq '.items[].backend_status'|grep -v OK; do echo 'waiting for ONOS apps to sync'; sleep 5; done"
	timeout 60s bash -c "until http -a karaf:karaf GET http://127.0.0.1:30120/onos/v1/applications/org.opencord.kafka|jq '.state'|grep -q ACTIVE; do echo 'Waiting for Kafka app to become ACTIVE'; sleep 5; done"
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install $(HELM_GLOBAL_ARGS) ponsim-pod xos-profiles/ponsim-pod -f $(SEBAVALUES) --set workflow=$(NEM_WORKFLOW)
	$(WORKSPACE)/cord/helm-charts/scripts/wait_for_pods.sh
	touch $@

$(M)/siab: | $(M)/voltha-running $(M)/mininet $(M)/ponsim-tosca
	until http -a karaf:karaf --ignore-stdin --check-status GET http://127.0.0.1:30120/onos/v1/configuration/org.opencord.olt.impl.Olt; \
	do \
		sleep 5; \
	done
	http -a karaf:karaf --ignore-stdin POST http://127.0.0.1:30120/onos/v1/configuration/org.opencord.olt.impl.Olt defaultVlan=65535
	timeout 1m bash -c "until http GET http://127.0.0.1:30125/health|jq '.state'|grep -q HEALTHY; do echo 'Waiting for VOLTHA to be HEALTHY'; sleep 10; done"
	echo "[passed] VOLTHA is HEALTHY"
	timeout 2m bash -c "until http GET http://127.0.0.1:30125/api/v1/devices|jq '.items[].admin_state'|grep ENABLED|wc -l|grep -q 2; do echo 'Waiting for OLT and ONU to be enabled in VOLTHA'; sleep 10; done"
	echo "[passed] OLT and ONU are enabled in VOLTHA"
	timeout 2m bash -c "until http -a karaf:karaf GET http://127.0.0.1:30120/onos/v1/devices|jq '.devices[].available'|grep true|wc -l|grep -q 2; do echo 'Waiting for VOLTHA logical device and agg switch to be available in ONOS'; sleep 10; done"
	echo "[passed] VOLTHA logical device and agg switch are available in ONOS"
	# For some reason the dhcpl2relay app needs to be restarted after connecting the switch to ONOS's ofdpa-ovs driver.
	# Without this step the DHCP trap flow is not added to the agg switch.
	http -a karaf:karaf --ignore-stdin DELETE http://127.0.0.1:30120/onos/v1/applications/org.opencord.dhcpl2relay/active
	http -a karaf:karaf --ignore-stdin POST http://127.0.0.1:30120/onos/v1/applications/org.opencord.dhcpl2relay/active
	http -a karaf:karaf --ignore-stdin POST http://127.0.0.1:30120/onos/v1/applications/org.opencord.kafka/active
ifeq ($(NEM_WORKFLOW),att-workflow)
	timeout 2m bash -c "until http -a admin@opencord.org:letmein GET http://127.0.0.1:30001/xosapi/v1/att-workflow-driver/attworkflowdriverserviceinstances |jq '.items[0].authentication_state'|grep -q AWAITING; do echo 'waiting for ATT Workflow Driver ServiceInstance to be in AWAITING state'; sleep 10; done"
	echo "[passed] ATT Workflow Driver ServiceInstance is in AWAITING state"
endif
ifeq ($(NEM_WORKFLOW),tt-workflow)
	timeout 2m bash -c "until http -a admin@opencord.org:letmein GET http://127.0.0.1:30001/xosapi/v1/tt-workflow-driver/ttworkflowdriverserviceinstances |jq '.items[0].dhcp_state'|grep -q AWAITING; do echo 'waiting for TT Workflow Driver ServiceInstance to be in AWAITING state'; sleep 10; done"
	echo "[passed] TT Workflow Driver ServiceInstance is in AWAITING state"
endif
	sudo iptables -P FORWARD ACCEPT
	sudo apparmor_parser -R /etc/apparmor.d/sbin.dhclient || true
	touch $@
	echo "SEBA-in-a-Box installation finished!"

$(M)/seba-1.0.0: | $(WORKSPACE)/cord/helm-charts $(M)/helm-init
	helm install -n cord-platform cord/cord-platform --version=6.1.0 -f $(WORKSPACE)/cord/helm-charts/$(SEBAVALUES)
	until kubectl get crd | grep etcdclusters; \
	do \
		echo "Waiting for etcdclusters CRD to be available"; \
		sleep 5; \
	done
	touch $(M)/kafka
	touch $(M)/onos
	touch $(M)/etcd-operator-ready
	helm install -n seba cord/seba --version=1.0.0 -f $(WORKSPACE)/cord/helm-charts/$(SEBAVALUES)
	helm install -n att-workflow cord/att-workflow --version=1.0.2 -f $(WORKSPACE)/cord/helm-charts/$(SEBAVALUES)
	touch $(M)/voltha
	touch $(M)/nem
	touch $@

# BBSim support
BBSIM_OLT_TOSCA ?= examples/bbsim-16.yaml
BBSIM_DHCP_TOSCA ?= examples/bbsim-dhcp.yaml

$(M)/bbsim: | $(M)/onos $(M)/voltha-running $(M)/nem-running
	cd $(WORKSPACE)/cord/helm-charts && \
	helm upgrade --install bbsim bbsim -f $(SEBAVALUES) && \
	scripts/wait_for_pods.sh voltha && \
	touch $@

$(M)/bbsim-tosca: | $(M)/bbsim
	cd $(WORKSPACE)/cord/helm-charts && \
	echo "Loading BBSim TOSCA: $(BBSIM_DHCP_TOSCA) $(BBSIM_OLT_TOSCA)" && \
	for tosca in $(BBSIM_DHCP_TOSCA) $(BBSIM_OLT_TOSCA) ; do \
		curl -H "xos-username: admin@opencord.org" -H "xos-password: letmein" -X POST --data-binary @$$tosca http://127.0.0.1:30007/run ; \
	done && \
	touch $@

run-tests: | $(M)/qatests

run-tests-latest: PYBOT_ARGS := '-v SUBSCRIBER_FILENAME:SIABSubscriberLatest'
run-tests-latest: run-tests

$(M)/qatests-prereqs:
	sudo apt install -y python-pip virtualenv
	touch $@

$(WORKSPACE)/cord/test/cord-tester: | $(M)/setup
	mkdir -p $(WORKSPACE)/cord/test
	cd $(WORKSPACE)/cord/test && git clone https://gerrit.opencord.org/cord-tester

$(WORKSPACE)/cord/incubator/voltha: | $(M)/setup
	mkdir -p $(WORKSPACE)/cord/incubator
	cd $(WORKSPACE)/cord/incubator && git clone https://gerrit.opencord.org/voltha

PYBOT_ARGS ?=
$(M)/qatests: | $(M)/siab $(M)/qatests-prereqs $(WORKSPACE)/cord/test/cord-tester $(WORKSPACE)/cord/incubator/voltha
	cd $(WORKSPACE)/cord/test/cord-tester/src/test/cord-api/ && \
	WORKSPACE=$(VIRTUALENV) bash ./setup_venv.sh && \
	source $(VIRTUALENV)/venv-cord-tester/bin/activate && \
	cd Tests/WorkflowValidations/ && \
	robot $(PYBOT_ARGS) --removekeywords wuks -e notready -i $(TESTTAGS) -v VOLTHA_DIR:$(WORKSPACE)/cord/incubator/voltha SIAB.robot
	touch $@

remove-chart-milestones:
	cd $(M); rm -f kafka kafka-running onos voltha etcd-operator-ready etcd-cluster \
		voltha-running ponsim mininet nem nem-running ponsim-tosca siab bbsim bbsim-tosca \
		logging nem-monitoring seba-1.0.0

remove-kube-milestones:
	cd $(M); rm -f kubeadm helm-init

remove-test-milestones:
	cd $(M); rm -f qatests qatests-prereqs

teardown-charts: remove-chart-milestones
	helm delete --purge $(shell helm ls -q | grep -v docker-registry)

reset-kubeadm: remove-chart-milestones remove-kube-milestones remove-test-milestones
	sudo kubeadm reset -f || true
	sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X
	sudo rm -f /var/lib/cni/networks/pon0/* || true
	sudo rm -f /var/lib/cni/networks/pon1/* || true
	sudo rm -f /var/lib/cni/networks/k8s-pod-network/* || true
