#!/usr/bin/env bash

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

#############################################################
#                                                           #
#    Returns a list of images given a list of helm charts   #
#                                                           #
#############################################################

output=""
for chart in "$@";
do
  if [ "${chart}" = "etcd-cluster" ]; then
    # shellcheck disable=SC1117
    output+=$(helm template "${chart}" | grep "busyboxImage:\|version:\|repository:" | sed 's/busyboxImage://g' | sed 's/version://g'| sed 's/repository://g' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d \" | awk '(NR%2){print$0p}{p=":"$0}')
    # shellcheck disable=SC1117
    output+="\n"
  else
    output+=$(helm template "${chart}" | grep "image:" | sed 's/image://g' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d \")
    # shellcheck disable=SC1117
    output+="\n"
  fi
done

echo -e "${output}" | sort | uniq | sed '/^\s*$/d'
