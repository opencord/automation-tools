#!/usr/bin/env bash

# Copyright 2017-present Open Networking Foundation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# ansiblelint.sh - check all yaml files that they pass the ansible-lint tool

set +e -u -o pipefail
fail_ansible=0

# verify that we have ansible-lint installed
command -v ansible-lint  >/dev/null 2>&1 || { echo "ansible-lint not found, please install it" >&2; exit 1; }

# when not running under Jenkins, use current dir as workspace
WORKSPACE=${WORKSPACE:-.}

echo "=> Linting Ansible Code with $(ansible-lint --version)"

while IFS= read -r -d '' yf
do
  echo "==> CHECKING: ${yf}"
  ansible-lint -p "${yf}"
  rc=$?
  if [[ $rc != 0 ]]; then
    echo "==> LINTING FAIL: ${yf}"
    fail_ansible=1
  fi
done < <(find "${WORKSPACE}" \( -name "*.yml" -o -name "*.yaml" \) -print0)

exit ${fail_ansible}
