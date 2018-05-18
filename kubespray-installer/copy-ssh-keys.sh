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

set -e -u -o pipefail

REMOTE_SSH_USER="${REMOTE_SSH_USER:-cord}"
SSH_PUBKEY_PATH="${SSH_PUBKEY_PATH:-${HOME}/.ssh/id_rsa.pub}"

SSH_PUBKEY=$(cat "${SSH_PUBKEY_PATH}")

for NODE in "$@";
do
  # remove key for this node from local ~/.ssh/known_hosts file
  ssh-keygen -R "${NODE}"

  # copy the ssh key to the remote system ~/.ssh/authorized_keys file
  # shellcheck disable=SC2029
  ssh "${REMOTE_SSH_USER}@${NODE}" "umask 0077 && mkdir -p ~/.ssh && echo \"${SSH_PUBKEY}\" >> ~/.ssh/authorized_keys"
done
