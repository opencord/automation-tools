SHELL           := /bin/bash
BUILD           ?= /tmp
M               ?= $(BUILD)/milestones
MAKEDIR         := $(dir $(realpath $(firstword $(MAKEFILE_LIST))))
WORKSPACE       ?= $(HOME)
VIRTUALENV      ?= $(WORKSPACE)/cord/test
SEBAVALUES      ?= configs/seba-ponsim.yaml

HELM_VERSION    ?= "2.10.0"
HELM_SHA256SUM  ?= "0fa2ed4983b1e4a3f90f776d08b88b0c73fd83f305b5b634175cb15e61342ffe"
HELM_PLATFORM   ?= "linux-amd64"

all: $(M)/siab

$(M)/setup:
	mkdir -p $(M)
	sudo apt update
	sudo apt install -y httpie jq software-properties-common
	sudo swapoff -a
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
	touch $@

$(WORKSPACE)/cord/helm-charts: | $(M)/setup
	mkdir -p $(WORKSPACE)/cord
	cd $(WORKSPACE)/cord; git clone https://gerrit.opencord.org/helm-charts

$(M)/kafka: | $(WORKSPACE)/cord/helm-charts $(M)/helm-init
	helm repo add incubator https://kubernetes-charts-incubator.storage.googleapis.com/
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install cord-kafka -f examples/kafka-single.yaml incubator/kafka
	touch $@

$(M)/kafka-running: | $(M)/kafka
	kubectl wait pod/cord-kafka-0 --for condition=Ready --timeout=180s
	touch $@

# Dependency on NEM is there to force ordering for parallel install
# The idea is to install VOLTHA / ONOS / Mininet while NEM is initializing
$(M)/onos: | $(M)/kafka-running $(M)/nem
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install onos onos -f configs/onos.yaml -f $(SEBAVALUES)
	touch $@

$(M)/voltha: | $(M)/kafka-running
	cd $(WORKSPACE)/cord/helm-charts; helm dep up voltha
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install voltha -f $(SEBAVALUES) \
    	--set etcd-operator.customResources.createEtcdClusterCRD=false \
    	voltha
	touch $@

$(M)/etcd-operator-ready: | $(M)/voltha
	until kubectl api-versions | grep etcd.database.coreos.com/v1beta2; \
	do \
		echo "Waiting for etcd.database.coreos.com/v1beta2 to be available"; \
		sleep 5; \
	done
	until kubectl api-resources | grep EtcdCluster; \
	do \
		echo "Waiting for EtcdCluster API resource to be available"; \
		sleep 5; \
	done
	touch $@

$(M)/etcd-cluster: | $(M)/etcd-operator-ready
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade voltha -f $(SEBAVALUES) \
    	--set etcd-operator.customResources.createEtcdClusterCRD=true \
    	voltha
	touch $@

$(M)/voltha-running: | $(M)/etcd-cluster
	$(WORKSPACE)/cord/helm-charts/scripts/wait_for_pods.sh voltha
	touch $@

$(M)/ponsim: | $(M)/voltha
	sudo iptables -P FORWARD ACCEPT
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

$(M)/nem: $(M)/kafka-running
	cd $(WORKSPACE)/cord/helm-charts; helm dep update xos-core
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install xos-core xos-core
	cd $(WORKSPACE)/cord/helm-charts; helm dep update xos-profiles/att-workflow
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install att-workflow xos-profiles/att-workflow -f $(SEBAVALUES)
	touch $@

$(M)/nem-running: $(M)/nem
	$(WORKSPACE)/cord/helm-charts/scripts/wait_for_pods.sh
	touch $@

$(M)/ponsim-tosca: $(M)/nem-running
	timeout 60s bash -c "until ! http -a admin@opencord.org:letmein GET http://127.0.0.1:30001/xosapi/v1/core/serviceinstanceattributes|jq '.items[].backend_status'|grep -v OK; do echo 'waiting for ONOS config to sync'; sleep 5; done"
	timeout 60s bash -c "until ! http -a admin@opencord.org:letmein GET http://127.0.0.1:30001/xosapi/v1/onos/onosapps|jq '.items[].backend_status'|grep -v OK; do echo 'waiting for ONOS apps to sync'; sleep 5; done"
	cd $(WORKSPACE)/cord/helm-charts; helm upgrade --install ponsim-pod xos-profiles/ponsim-pod
	$(WORKSPACE)/cord/helm-charts/scripts/wait_for_pods.sh
	touch $@

$(M)/siab: | $(M)/voltha-running $(M)/mininet $(M)/ponsim-tosca
	until http -a karaf:karaf --ignore-stdin --check-status GET http://127.0.0.1:30120/onos/v1/configuration/org.opencord.olt.impl.Olt; \
	do \
		sleep 5; \
	done
	http -a karaf:karaf --ignore-stdin POST http://127.0.0.1:30120/onos/v1/configuration/org.opencord.olt.impl.Olt defaultVlan=65535
	timeout 60s bash -c "until http -a admin@opencord.org:letmein GET http://127.0.0.1:30001/xosapi/v1/att-workflow-driver/attworkflowdriverserviceinstances |jq '.items[0].authentication_state'|grep AWAITING; do echo 'waiting for att-workflow-driver to be in AWAITING state'; sleep 5; done"
	touch $@
	echo "SEBA-in-a-Box installation finished!"

run-tests: $(M)/qatests

$(M)/qatests-prereqs:
	sudo apt install -y python-pip virtualenv
	touch $@

$(WORKSPACE)/cord/test/cord-tester: | $(M)/setup
	mkdir -p $(WORKSPACE)/cord/test
	cd $(WORKSPACE)/cord/test && git clone https://gerrit.opencord.org/cord-tester

$(M)/qatests: $(M)/siab $(M)/qatests-prereqs $(WORKSPACE)/cord/test/cord-tester
	cd $(WORKSPACE)/cord/test/cord-tester/src/test/cord-api/ && \
		WORKSPACE=$(VIRTUALENV) bash ./setup_venv.sh && \
		source $(VIRTUALENV)/venv-cord-tester/bin/activate && \
		cd Tests/WorkflowValidations/ && \
		pybot -e notready SIAB.robot
	touch $@

remove-chart-milestones:
	cd $(M); rm -f kafka kafka-running onos voltha etcd-operator-ready etcd-cluster \
		voltha-running ponsim mininet nem nem-running ponsim-tosca siab

remove-kube-milestones:
	cd $(M); rm -f kubeadm helm-init

remove-test-milestones:
	cd $(M); rm -f qatests

teardown-charts: remove-chart-milestones
	helm delete --purge $(shell helm ls -q)

reset-kubeadm: remove-chart-milestones remove-kube-milestones
	sudo kubeadm reset -f
	sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X

