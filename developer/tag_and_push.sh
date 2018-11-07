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
# Tags and push a list of local images to a target registry #
#                                                           #
#############################################################

#
# Displays the help menu.
#
display_help () {
  echo "Tags and pushes to a target Docker registry a list of images on the system or given in stdin."
  echo " "
  echo "Usage: $0 [-f|--filter filter] [-r|--registry docker-registry] [-s|--source image-file] [-t|--tag custom-tag] [-h --help]"
  echo " "
  echo "   filter                  A string used to filter the image names (used as 'grep -E \"^$filter\"')"
  echo "   docker-registry         The address of the target registry. DockerHub will be instead used by default"
  echo "   custom-tag              An optional, custom tag to be used to tag images. The same tag of the original images will be used otherwise"
  echo " "
  echo "Example usages:"
  echo "   echo onosproject/onos:1.13.5 | ./tag_and_push.sh" # push the local onosproject/onos:1.13.5 image given in input and pushes it to DockerHub
  echo "   cat images | ./tag_and_push.sh -t my_tag" # tag with "my_tag" the images in the file images given in input and push them to DockerHub
  echo "   ./tag_and_push.sh -s images.txt -t my_tag" # tag with "my_tag" the images in the file images.txt and push them to DockerHub
  echo "   ./tag_and_push.sh -f xosproject 192.168.10.100:30500" # tag all the xosproject images and push them to the registry 192.168.10.100:30500
  echo "   ./tag_and_push.sh -r 192.168.10.100:30500" # tag all local images and push them to the registry 192.168.10.100:30500
  echo "   ./tag_and_push.sh --f xosproject" # push all local images containing xosproject in the name and pushes them to dockerhub
}

# Parse params
while :; do
  case $1 in
    -s|--source)
      shift
      if [[ -z $1 ]] || [[ $1 = -f ]] || [[ $1 = -t ]] || [[ $1 = -r ]] || [[ $1 = -h ]]
      then
        display_help
        exit 1
      fi
      custom_file="$1"
      ;;
    -r|--registry)
      shift
      if [[ -z $1 ]] || [[ $1 = -f ]] || [[ $1 = -t ]] || [[ $1 = -s ]] || [[ $1 = -h ]]
      then
        display_help
        exit 1
      fi
      registry="$1"
      ;;
    -f|--filter)
      shift
      if [[ -z $1 ]] || [[ $1 = -r ]] || [[ $1 = -t ]] || [[ $1 = -s ]] || [[ $1 = -h ]]
      then
        display_help
        exit 1
      fi
      filter="$1"
      ;;
    -t|--tag)
      shift
      if [[ -z $1 ]] || [[ $1 = -r ]] || [[ $1 = -f ]] || [[ $1 = -s ]] || [[ $1 = -h ]]
      then
        display_help
        exit 1
      fi
      custom_tag="$1"
      ;;
    -h|--help)
      display_help
      exit 0
      ;;
    *) break
  esac
  shift
done

# Source images list
if [ -t 0 ]; then
  images=$(docker images | awk '{if (NR!=1) {print}}' | awk '{ a=$1":"$2; print a }')
else
  images=""
  while IFS= read -r line; do
    # shellcheck disable=SC1117
    images+="$line\n"
  done < "${custom_file:-/dev/stdin}"
fi

# Filter images
if [[ ! -z "$filter" ]]
then
  images=$(echo -e "${images}" | grep -E "${filter}" | grep -v "${registry}")
fi

for image in $(echo -e "${images}"); do
  new_image=""

  # Set registry
  new_image+="${registry}"

  IFS=':' read -r -a image_tag_splitted <<< "$image"

  # Set image name
  new_image+="/${image_tag_splitted[0]}:"

  # Set tag
  splitted_tag="${image_tag_splitted[1]}"
  new_image+="${custom_tag:-$splitted_tag}"

  docker tag "${image}" "${new_image}" > /dev/null
  docker push "${new_image}" > /dev/null

  echo "${new_image}"
done
