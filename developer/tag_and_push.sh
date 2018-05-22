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
  echo "Usage: $0 {--push|--help} [docker-registry] [tag=candidate] " >&2
  echo " "
  echo "   -h, --help              Display this help message."
  echo "   -r, --registry          Tags and push all the local docker images to <docker-registry>"
  echo " "
  echo "   docker-registry         The address of the registry"
  echo "   tag                     The tag to be used"
  echo " "
  echo "Example usages:"
  echo "   ./tag_and_push.sh -r 192.168.10.100:30500"
  echo "   ./tag_and_push.sh -r 192.168.10.100:30500 devel"
}

#
# Tag and push all the locally available docker images
#
tag_and_push () {
  echo "Pushing images to $DOCKER_REGISTRY with tag $DOCKER_TAG"
  echo " "

  # reading docker images
  DOCKER_IMAGES_STR=$(docker images --format="{{.Repository}} {{.Tag}}" --filter "dangling=false" | grep -v none | grep "^xosproject")
  DOCKER_IMAGES=($DOCKER_IMAGES_STR)

  # looping over docker images
  IMAGELIST_LENGTH=${#DOCKER_IMAGES[@]}
  while [ $IMAGELIST_LENGTH -gt 0 ]
  do
    IMAGE=${DOCKER_IMAGES[0]}:${DOCKER_IMAGES[1]}

    docker tag $IMAGE $DOCKER_REGISTRY/$IMAGE
    docker push $DOCKER_REGISTRY/$IMAGE

    # removing the already tagged and pushed image
    DOCKER_IMAGES=("${DOCKER_IMAGES[@]:2}")
    IMAGELIST_LENGTH=${#DOCKER_IMAGES[@]}
  done
}

#
# Init
#
CLI_OPT=$1
DOCKER_REGISTRY=$2
DOCKER_TAG=${3:-"candidate"}

while :
do
  case $CLI_OPT in
    -r | --registry)
        tag_and_push
        exit 0
        ;;
    -h | --help)
        display_help
        exit 0
        ;;
    --) # End of all options
        shift
        break
        ;;
    *)
        echo Error: Unknown option: $CLI_OPT >&2
        echo " "
        display_help
        exit -1
        ;;
  esac
done