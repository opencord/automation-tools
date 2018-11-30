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

# Build voltha with a specific commit, and tag and push the images to a target
# registry and run tests against it
# Note: make sure kubernetes-configs file is already pointing to the images
# with correct tag and registry location

set -e

TESTING_TOOL_DIR=${HOME}/automation-tools/testing
HELM_CHARTS_DIR="${HELM_CHARTS_DIR:-${HOME}/helm-charts}"
POD_CONFIGS_DIR="${POD_CONFIGS_DIR:-${HOME}/pod-configs}"
VOLTHA_DIR="${VOLTHA_DIR:-${HOME}/voltha}"
TEST_DIR="${TEST_DIR:-${HOME}/cord-tester/src/test/cord-api/Tests}"
POD_NAME="flex-pod1-olt"
COMMIT="HEAD"
TAG="debug"
REGISTRY="10.192.4.244:30500"
LOG_FILE="/tmp/test.log"

while getopts "hc:r:t:d:m:p" opt; do
  case ${opt} in
    h) echo "Usage: $0 [-c] <commit> [-t] <tag> [-r] <registry> [-d] <test_directory> [-m] <test_command> [-p] [-h]";
       echo "-c <commit>         : start test from commit <commit>";
       echo "-t <tag>            : use <tag> for tagging voltha images";
       echo "-r <registry>       : use <registry> for pushing voltha images";
       echo "-d <test_directory> : directory where test scripts are located";
       echo "-m <test_command>   : bash command to execute tests";
       echo "-p                  : continue to test previous commits after testing the current one";
       echo "-h                  : show this help message";
       exit 0;;
    c) COMMIT=$OPTARG;;
    t) TAG=$OPTARG;;
    r) REGISTRY=$OPTARG;;
    d) TEST_DIR=$OPTARG;;
    m) TEST_COMMAND=$OPTARG;;
    p) TEST_PREVIOUS_COMMITS=true;;
    \? ) echo "Invalid option: -$OPTARG"; exit 1;;
  esac
done

function build_and_test() {
  cd $TESTING_TOOL_DIR
  bash build_and_push_voltha.sh -c $COMMIT -t $TAG -r $REGISTRY

  # Note that the test should handle reinstallation of voltha
  echo "Starting tests with commit "$COMMIT | tee -a $LOG_FILE
  cd $TEST_DIR
  TEST_COMMAND="pybot -d Log -l log-$COMMIT -i debug -V $POD_CONFIGS_DIR/deployment-configs/$POD_NAME.yaml WorkflowValidations/ATT_Test001.robot"
  $TEST_COMMAND | tee -a $LOG_FILE
}

> $LOG_FILE

if [ -n $TEST_PREVIOUS_COMMITS ]; then
  while true; do
    build_and_test
    cd $VOLTHA_DIR
    COMMIT=$(git rev-parse HEAD^)
    cd -
  done
else
  build_and_test
fi
