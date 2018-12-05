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

HELM_VERSION    ?= "2.10.0"
HELM_SHA256SUM  ?= "0fa2ed4983b1e4a3f90f776d08b88b0c73fd83f305b5b634175cb15e61342ffe"
HELM_PLATFORM   ?= "linux-amd64"

KAFKA_CHART_VERSION  ?= 0.8.8

# Targets
ponsim: $(M)/siab

bbsim: $(M)/bbsim-tosca

both: BBSIM_DHCP_TOSCA =
both: $(M)/siab $(M)/bbsim-tosca

# https://ftp.gnu.org/old-gnu/Manuals/make-3.79.1/html_chapter/make_6.html#SEC69
latest: SEBAVALUES := configs/seba-ponsim-latest.yaml
latest: all

stable: SEBAVALUES := configs/seba-ponsim.yaml
stable: all

$(M)/setup:
	mkdir -p $(M)
	sudo apt update
	sudo apt install -y httpie jq software-properties-common
	sudo swapoff -a
	sudo iptables -P FORWARD ACCEPT
	touch $@

/usr/bin/docker: | $(M)/setup
	sudo apt-key adv --keyserver keyserver.ubuntu.com --recv 0EBFCD88
	sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(shell lsb_release -cs) stable"
	sudo apt update
	sudo apt install -y "docker-ce=17.03*"

/usr/bin/kubeadm: | $(M)/setup /usr/bin/docker
	curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
	echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" > /tmp/kubernetes.list
	sudo cp /tmp/kubernetes.list /etc/apt/sources.list.d/kubernetes.list
	sudo apt update
	sudo apt install -y "kubeadm=1.11.3-*" "kubelet=1.11.3-*" "kubectl=1.11.3-*"

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
	kubectl apply -f https://docs.projectcalico.org/v2.6/getting-started/kubernetes/installation/hosted/kubeadm/1.6/calico.yaml
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
	touch $@

$(WORKSPACE)/cord/helm-charts: | $(M)/setup
	mkdir -p $(WORKSPACE)/cord
	cd $(WORKSPACE)/cord; git clone https://gerrit.opencord.org/helm-charts

$(M)/kafka: | $(WORKSPACE)/cord/helm-charts $(M)/helm-init
	cd $(WORKSPACE)/cord/helm-charts && \
	helm upgrade --install cord-kafka --version $(KAFKA_CHART_VERSION) -f examples/kafka-single.yaml incubator/kafka
	touch $@

$(M)/kafka-running: | $(M)/kafka
	kubectl wait pod/cord-kafka-0 --for condition=Ready --timeout=180s
	touch $@

$(M)/nem-monitoring: | $(M)/kafka-running
	cd $(WORKSPACE)/cord/helm-charts && \
	helm dep up nem-monitoring  && \
	helm upgrade --install nem-monitoring nem-monitoring
	$(WORKSPACE)/cord/helm-charts/scripts/wait_for_pods.sh
	touch $@

$(M)/logging: | $(M)/kafka-running
	cd $(WORKSPACE)/cord/helm-charts && \
	helm dep up logging && \
	helm upgrade --install logging -f examples/logging-single.yaml logging
	$(WORKSPACE)/cord/helm-charts/scripts/wait_for_pods.sh
	touch $@

# Dependency on NEM is there to force ordering for parallel install
# The idea is to install VOLTHA / ONOS / Mininet while NEM is initializing
$(M)/onos: | $(M)/kafka-running $(M)/nem $(INFRA_PREREQS)
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install onos onos -f configs/onos.yaml -f $(SEBAVALUES)
	touch $@

$(M)/voltha: | $(M)/kafka-running $(INFRA_PREREQS) $(M)/etcd-operator-ready
	cd $(WORKSPACE)/cord/helm-charts; helm dep up voltha
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install voltha voltha -f $(SEBAVALUES)
	touch $@

$(M)/etcd-operator-ready: | $(WORKSPACE)/cord/helm-charts $(M)/helm-init
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install etcd-operator stable/etcd-operator -f $(SEBAVALUES)
	until kubectl get crd | grep etcdclusters; \
	do \
		echo "Waiting for etcdclusters CRD to be available"; \
		sleep 5; \
	done
	touch $@

$(M)/voltha-running: | $(M)/voltha
	timeout 300s bash -c "until kubectl get pod|grep etcd-cluster|grep 1/1; do echo 'Waiting for etcd-cluster to be ready'; sleep 10; done"
	$(WORKSPACE)/cord/helm-charts/scripts/wait_for_pods.sh voltha
	touch $@

$(M)/ponsim: | $(M)/voltha
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install ponnet ponnet
	$(WORKSPACE)/cord/helm-charts/scripts/wait_for_pods.sh kube-system
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install ponsimv2 ponsimv2 -f $(SEBAVALUES)
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

$(M)/mininet: | $(M)/onos $(M)/ponsim $(M)/pon0_fwd
	sudo modprobe openvswitch
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install mininet mininet
	touch $@

$(M)/nem: | $(M)/kafka-running $(INFRA_PREREQS)
	cd $(WORKSPACE)/cord/helm-charts; helm dep update xos-core
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install xos-core xos-core -f $(SEBAVALUES)
	cd $(WORKSPACE)/cord/helm-charts; helm dep update xos-profiles/att-workflow
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install att-workflow xos-profiles/att-workflow -f $(SEBAVALUES)
	cd $(WORKSPACE)/cord/helm-charts; helm dep update xos-profiles/base-kubernetes
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install base-kubernetes xos-profiles/base-kubernetes -f $(SEBAVALUES)
	touch $@

$(M)/nem-running: | $(M)/nem
	$(WORKSPACE)/cord/helm-charts/scripts/wait_for_pods.sh
	touch $@

$(M)/ponsim-tosca: | $(M)/nem-running
	timeout 60s bash -c "until ! http -a admin@opencord.org:letmein GET http://127.0.0.1:30001/xosapi/v1/core/serviceinstanceattributes|jq '.items[].backend_status'|grep -v OK; do echo 'waiting for ONOS config to sync'; sleep 5; done"
	timeout 60s bash -c "until ! http -a admin@opencord.org:letmein GET http://127.0.0.1:30001/xosapi/v1/onos/onosapps|jq '.items[].backend_status'|grep -v OK; do echo 'waiting for ONOS apps to sync'; sleep 5; done"
	timeout 60s bash -c "until http -a karaf:karaf GET http://127.0.0.1:30120/onos/v1/applications/org.opencord.kafka|jq '.state'|grep -q ACTIVE; do echo 'Waiting for Kafka app to become ACTIVE'; sleep 5; done"
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install ponsim-pod xos-profiles/ponsim-pod -f $(SEBAVALUES)
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
	timeout 2m bash -c "until http -a admin@opencord.org:letmein GET http://127.0.0.1:30001/xosapi/v1/att-workflow-driver/attworkflowdriverserviceinstances |jq '.items[0].authentication_state'|grep -q AWAITING; do echo 'waiting for ATT Workflow Driver ServiceInstance to be in AWAITING state'; sleep 10; done"
	echo "[passed] ATT Workflow Driver ServiceInstance is in AWAITING state"
	touch $@
	echo "SEBA-in-a-Box installation finished!"

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

$(M)/qatests-prereqs:
	sudo apt install -y python-pip virtualenv
	touch $@

$(WORKSPACE)/cord/test/cord-tester: | $(M)/setup
	mkdir -p $(WORKSPACE)/cord/test
	cd $(WORKSPACE)/cord/test && git clone https://gerrit.opencord.org/cord-tester

PYBOT_ARGS ?=
$(M)/qatests: | $(M)/siab $(M)/qatests-prereqs $(WORKSPACE)/cord/test/cord-tester
	cd $(WORKSPACE)/cord/test/cord-tester/src/test/cord-api/ && \
		WORKSPACE=$(VIRTUALENV) bash ./setup_venv.sh && \
		source $(VIRTUALENV)/venv-cord-tester/bin/activate && \
		cd Tests/WorkflowValidations/ && \
		pybot $(PYBOT_ARGS) --removekeywords wuks -e notready -i $(TESTTAGS) SIAB.robot
	touch $@

remove-chart-milestones:
	cd $(M); rm -f kafka kafka-running onos voltha etcd-operator-ready etcd-cluster \
		voltha-running ponsim mininet nem nem-running ponsim-tosca siab bbsim bbsim-tosca \
		logging nem-monitoring

remove-kube-milestones:
	cd $(M); rm -f kubeadm helm-init

remove-test-milestones:
	cd $(M); rm -f qatests qatests-prereqs

teardown-charts: remove-chart-milestones
	helm delete --purge $(shell helm ls -q)

reset-kubeadm: remove-chart-milestones remove-kube-milestones remove-test-milestones
	sudo kubeadm reset -f
	sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X

