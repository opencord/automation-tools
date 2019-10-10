#!/bin/bash

HELM_GLOBAL_ARGS="--values /home/cord/pod-configs/deployment-configs/comac-onf-testbed.yaml"
CENTRAL_NODE=10.90.0.151
XOSURL=http://$CENTRAL_NODE:30007/run

helm repo update

# Install CORD platform and COMAC profile
kubectl config use-context central
kubectl get nodes
helm upgrade --install $HELM_GLOBAL_ARGS cord-platform cord/cord-platform
helm upgrade --install $HELM_GLOBAL_ARGS comac-platform cord/comac-platform

# Wait until tosca-loader job completes
echo "Waiting for the platform ready"
kubectl -n default wait --for=condition=complete --timeout=300s job/comac-platform-tosca-loader

# Push Edge fabric config to ONOS-fabric
curl -H "xos-username: admin@opencord.org" \
     -H "xos-password: letmein" \
     -X POST \
     --data-binary @/home/cord/pod-configs/tosca-configs/comac/edge-fabric-accelleran.yaml \
     $XOSURL
echo ""

# Wait until data plane is ready
until ssh edge1 timeout 3 ping 119.0.0.132 -c 1 > /dev/null 2>&1; do
     echo 'Waiting for the fabric switch to be ready';
done

# Install ONOS progran
helm upgrade --install $HELM_GLOBAL_ARGS onos-progran cord/onos-progran
kubectl -n default wait --for=condition=Ready --timeout=300s pod -l app=onos-progran

# Restart progran fro ONOS
sshpass -p karaf ssh \
        -o UserKnownHostsFile=/dev/null \
        -o StrictHostKeyChecking=no \
        -p 30116 \
        -l karaf \
        $CENTRAL_NODE app deactivate org.onosproject.progran
sshpass -p karaf ssh \
        -o UserKnownHostsFile=/dev/null \
        -o StrictHostKeyChecking=no \
        -p 30116 \
        -l karaf \
        $CENTRAL_NODE app activate org.onosproject.progran
sleep 3 

# Push progran config to ONOS-progran
curl -H "xos-username: admin@opencord.org" \
     -H "xos-password: letmein" \
     -X POST \
     --data-binary @/home/cord/pod-configs/tosca-configs/comac/progran.yaml \
     $XOSURL
echo ""

# Install OMEC-DP
kubectl config use-context edge
kubectl get nodes
helm upgrade --install $HELM_GLOBAL_ARGS --namespace omec omec-data-plane cord/omec-data-plane
kubectl -n omec wait --for=condition=Ready --timeout=300s pod -l app=spgwu

# Install OMEC-CP
kubectl config use-context central
kubectl get nodes
helm upgrade --install $HELM_GLOBAL_ARGS --namespace omec omec-control-plane cord/omec-control-plane
kubectl -n omec wait --for=condition=Ready --timeout=300s pod -l app=spgwc

# Install Accelleran CU
helm upgrade --install $HELM_GLOBAL_ARGS --namespace omec comac-cu cord/comac-cu
kubectl -n omec wait --for=condition=Ready --timeout=300s pod -l app=accelleran
ssh edge1 "ssh -i ~/rru_key guest@119.0.0.10 reboot"

# Install CDN remote
helm upgrade --install $HELM_GLOBAL_ARGS --namespace omec cdn-remote cord/cdn-remote

# Install CDN local
kubectl config use-context edge
kubectl get nodes
helm upgrade --install $HELM_GLOBAL_ARGS --namespace omec cdn-local cord/cdn-local
