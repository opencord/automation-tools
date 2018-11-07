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
#    Pull a list of images into the local Docker Registry   #
#                                                           #
#############################################################

display_help () {
  echo "Downloads the images specified to the local Docker Registry."
  echo " "
  echo "Usage: $0 [-s|--source image-list-file] [-h|--help]"
  echo " "
  echo "   image-list-file               A file where to read images from (if not read by default from stdin)"
  echo " "
  echo "Example usages:"
  echo "   echo alpine:3.6 | bash $0" # read the list of images from stdin
  echo "   cat images | bash $0" # read the list of images from stdin
  echo "   bash $0 -f images" # read images from a file images
}

while :; do
  case $1 in
    -s|--source)
      shift
      if [[ -z $1 ]] || [[ $1 = -h ]]
      then
        display_help
        exit 1
      fi
      custom_file="$1"
      ;;
    -h|--help)
      display_help
      exit 0
      ;;
    *) break
  esac
  shift
done

while IFS= read -r image;
do
  docker pull "${image}" > /dev/null
  echo "${image}"
done < "${custom_file:-/dev/stdin}"
