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

###########################################################
#                                                         #
# Tags and push all the local images to a docker-registry #
#                                                         #
###########################################################

#
# Displays the help menu.
#
display_help () {
  echo "Tags and pushes to a remote registry all the images present in the local docker registry."
  echo "Note that this script won't change the tag on the container"
  echo " "
  echo "Usage: $0 [filter] [docker-registry] "
  echo " "
  echo "   filter                  A string used to filter the images (used as 'grep -E \"^$FILTER\"')"
  echo "   docker-registry         The address of the registry"
  echo " "
  echo "Example usages:"
  echo "   ./tag_and_push.sh xosproject 192.168.10.100:30500" # tag all the xosproject images and push them to the registry
  echo "   ./tag_and_push.sh . 192.168.10.100:30500" # tag all the images and push them to the registry
  echo "   ./tag_and_push.sh xosproject" # push the xosproject images to dockerhub
}

#
# Tag and push all the locally available docker images
#
FILTER=$1
REGISTRY=$2

if [ "$FILTER" == "-h" ]; then
  display_help
else
  echo "REGISTRY: $REGISTRY"
  echo "FILTER:   $FILTER"
  if [ "$FILTER" != "" ]; then
    images=$(docker images | grep -E "$FILTER" | grep -v "$REGISTRY" | awk '{if (NR!=1) {print}}' | awk '{ a=$1":"$2; print a }')
  else
    # NOTE I don't this is ever used
    images=$(docker images | awk '{if (NR!=1) {print}}' | awk '{ a=$1":"$2; print a }')
  fi
  echo "Tagging Images:"
  echo "$images"
  echo " "
  for i in $images; do
    if [ "$REGISTRY" != "" ]; then
      docker tag "$i" "$REGISTRY/$i"
      docker push "$REGISTRY/$i"
    else
      docker push "$i"
    fi
  done
fi
