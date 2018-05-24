#!/usr/bin/env bash
#
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

# bootstrap-repo.sh
# Downloads CORD source into ~/cord

set -e -u -o pipefail

# Location of 'cord' directory checked out on the local system
CORDDIR="${CORDDIR:-${HOME}/cord}"

# CORD versioning
REPO_BRANCH="${REPO_BRANCH:-master}"

# Parse options
GERRIT_PATCHES=()

while getopts "hp:" opt; do
  case ${opt} in
    h ) echo "Usage for $0:"
      echo "  -p <project:change/revision> Download a patch from gerrit. Can be repeated."
      exit 0
      ;;
    p ) GERRIT_PATCHES+=("$OPTARG")
      ;;
    \? ) echo "Invalid option: -$OPTARG"
      exit 1
      ;;
  esac
done

if [ ! -x "/usr/local/bin/repo" ]
then
  echo "Installing repo..."
  # v1.23, per https://source.android.com/source/downloading
  REPO_SHA256SUM="394d93ac7261d59db58afa49bb5f88386fea8518792491ee3db8baab49c3ecda"
  curl -o /tmp/repo 'https://gerrit.opencord.org/gitweb?p=repo.git;a=blob_plain;f=repo;hb=refs/heads/stable'
  echo "$REPO_SHA256SUM  /tmp/repo" | sha256sum -c -
  sudo mv /tmp/repo /usr/local/bin/repo
  sudo chmod a+x /usr/local/bin/repo
fi

if [ ! -d "$CORDDIR/build" ]
then
  # make sure we can find gerrit.opencord.org as DNS failures will fail the build
  dig +short gerrit.opencord.org || (echo "ERROR: gerrit.opencord.org can't be looked up in DNS" && exit 1)

  echo "Downloading CORD/XOS, branch:'${REPO_BRANCH}'..."

  if [ ! -e "${HOME}/.gitconfig" ]
  then
    echo "No ${HOME}/.gitconfig, setting testing defaults"
    git config --global user.name 'Test User'
    git config --global user.email 'test@null.com'
    git config --global color.ui false
  fi

  mkdir -p "${CORDDIR}" && cd "${CORDDIR}"
  repo init -u https://gerrit.opencord.org/manifest -b "${REPO_BRANCH}"
  repo sync

  # download gerrit patches using repo
  if [[ ! -z "${GERRIT_PATCHES[*]-}" ]]
  then
    for gerrit_patch in "${GERRIT_PATCHES[@]-}"
    do
      echo "Checking out gerrit changeset: '${gerrit_patch}'"
      IFS=: read -r gerrit_project gerrit_changeset <<< "${gerrit_patch}"
      repo download "${gerrit_project}" "${gerrit_changeset}"
    done
  fi
fi
