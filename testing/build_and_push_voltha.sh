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

# Build voltha with a specific commit and tag and push the images to a target
# registry

set -e

DEV_TOOL_DIR=${HOME}/automation-tools/developer
VOLTHA_DIR="${VOLTHA_DIR:-${HOME}/voltha}"
COMMIT="HEAD"
TAG="debug"
REGISTRY="10.192.4.244:30500"

while getopts "hc:r:t:" opt; do
  case ${opt} in
    h) echo "Usage: $0 [-c] <commit> [-t] <tag> [-r] <registry> [-h]";
       echo "-c <commit>         : start test from commit <commit>";
       echo "-t <tag>            : use <tag> for tagging voltha images";
       echo "-r <registry>       : use <registry> for pushing voltha images";
       echo "-h                  : show this help message";
       exit 0;;
    c) COMMIT=$OPTARG;;
    t) TAG=$OPTARG;;
    r) REGISTRY=$OPTARG;;
    \? ) echo "Invalid option: -$OPTARG"; exit 1;;
  esac
done

echo "Building voltha images with commit $COMMIT"
cd "$VOLTHA_DIR"
git reset --hard "$COMMIT"
source env.sh
REPOSITORY=voltha/ TAG=$TAG VOLTHA_BUILD=docker make build

echo "Tagging and pushing voltha images with commit $COMMIT"
cd "$DEV_TOOL_DIR"
bash tag_and_push.sh -t "$TAG" -f "$TAG" -r "$REGISTRY"
