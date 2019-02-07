#!/bin/bash

# Copyright 2018-present Open Networking Foundation
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License.  You may obtain a copy
# of the License at:
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
# License for the specific language governing permissions and limitations under
# the License.

# copy-ssh-keys.sh - Adds ssh keys to nodes given as parameters to the script,
# after removing them from the ~/.ssh/known_hosts file on the local system.
#
# This script should be run interactively as it will prompt for input, and only
# invoked once, so as not to add multiple copies of the SSH key to the remote
# system.

AGGLOGS=/tmp/logs.out

kubectl logs -l release=att-workflow > $AGGLOGS
kubectl logs -l release=seba-services --all-containers >> $AGGLOGS
grep "save()" $AGGLOGS | ./logparse.py
