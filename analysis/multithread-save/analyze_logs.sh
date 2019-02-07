#!/bin/bash

AGGLOGS=/tmp/logs.out

kubectl logs -l release=att-workflow > $AGGLOGS
kubectl logs -l release=seba-services --all-containers >> $AGGLOGS
grep "save()" $AGGLOGS | ./logparse.py
