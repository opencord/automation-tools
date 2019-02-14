#!/usr/bin/env bash
#
# Copyright 2018-present Open Networking Foundation
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

# update_xos_docker.sh
# Updates docker FROM lines of synchronizers and xos core, when XOS is updated,
# and the synchronizer has the same parent SemVer major version
#
# Before using this, update XOS version in orchestration/xos/VERSION file
#
# After running script, `repo diff` will show the updated files.
#
# To undo changes: `repo forall -c "git checkout *Dockerfile*"`

set -eu -o pipefail

WORKSPACE=${WORKSPACE:-../../..}

NEW_COMMIT=${NEW_COMMIT:0}

XOS_MAJOR=$(cut -b 1 "${WORKSPACE}/cord/orchestration/xos/VERSION")

XOS_VERSION=$(cat "${WORKSPACE}/cord/orchestration/xos/VERSION")

# Update Synchronizer FROM parent versions
for df in ${WORKSPACE}/cord/orchestration/xos_services/*/Dockerfile.synchronizer
do
  df_contents=$(cat "$df")

  # shellcheck disable=SC2076
  if [[ "$df_contents" =~ "FROM xosproject/xos-synchronizer-base:${XOS_MAJOR}" ||
        "$df_contents" =~ "FROM xosproject/xos-synchronizer-base:master" ]]
  then
    pushd "$(dirname "$df")"

    echo "Updating synchronizer Dockerfile: ${df}"

    perl -pi -e "s/^FROM(.*):.*$/FROM\\1:$XOS_VERSION/" Dockerfile.synchronizer

    # if NEW_COMMIT is nonzero, create a new GIT commit with these changes
    if $NEW_COMMIT
    then
      # check if previous version is semver for patch version bump
      OLD_VERSION=$(head -n1 "VERSION")
      if [[ "$OLD_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]
      then
        repo start "bump$XOS_VERSION"

        # Increment patch by 1
        perl -pi -e 's/(\d+)$/ 1 + $1/ge' VERSION

        git add VERSION Dockerfile.synchronizer

        git commit -m "Updated service to use new XOS core version: $XOS_VERSION"
      else
        echo "This service isn't on a released version, manual intervention required"
      fi
    fi

    popd
  fi
done

# Update XOS parent versions
for df in ${WORKSPACE}/cord/orchestration/xos/containers/*/Dockerfile* \
          ${WORKSPACE}/cord/orchestration/xos-tosca/Dockerfile
do
  echo "Updating core Dockerfile: ${df}"
  perl -pi -e "s/^FROM xos(.*):.*$/FROM xos\\1:$XOS_VERSION/" "$df"
done
