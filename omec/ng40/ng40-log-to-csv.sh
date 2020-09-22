#!/bin/bash

# Copyright 2020-present Open Networking Foundation
#
# SPDX-License-Identifier: Apache-2.0
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

# This script reads an NG40 test log file and extracts from the file
# number of successful/failed attach/detach/ping etc. and saves them in a
# csv file which has the same file name as the test log file.

NG40_LOG_DIR="${NG40_LOG_DIR:-/var/jenkins/workspace/omec_nightly/ng40/log/}"
NG40_LOG_FILE="${NG40_LOG_FILE:-4G_SCALE_200720_083248-1.log}"
verifications=( received_Attach_Acc received_Detach_Acc sent_Attach_Req sent_Detach_Req )
results=( successful_attach successful_detach successful_ping failed_attach failed_detach failed_ping )

# Get expected verification numbers
expected_verifications=$(cat $NG40_LOG_DIR$NG40_LOG_FILE | grep 'Verification =')
for var in "${verifications[@]}"
do
  regex=$var"_ == ([0-9 \*]+)"
  [[ $expected_verifications =~ $regex ]]
  num=$(echo "${BASH_REMATCH[1]}" | bc)
  eval "expected_$var"="$num"
done

# Get actual verification numbers if exist
failed_verifications=$(cat $NG40_LOG_DIR$NG40_LOG_FILE | grep 'verification fail')
for var in "${verifications[@]}"
do
  regex=$var'_=([0-9]+)'
  [[ $failed_verifications =~ $regex ]]
  eval "actual_$var"="${BASH_REMATCH[1]}"
done

# Get sent/received packet numbers if exist
verify_statistics=$(cat $NG40_LOG_DIR$NG40_LOG_FILE)
pktgen_sent_total_packets=0
regex='pktgen_sent_total_packets = ([0-9]+)'
[[ $verify_statistics =~ $regex ]] && pktgen_sent_total_packets=${BASH_REMATCH[1]}

pktgen_received_total_packets=0
regex='pktgen_received_total_packets = ([0-9]+)'
[[ $verify_statistics =~ $regex ]] && pktgen_received_total_packets=${BASH_REMATCH[1]}

# Calculate successful/failed attach
successful_attach=$expected_received_Attach_Acc
if [ ! -z "$actual_received_Attach_Acc" ]
then
  successful_attach=$actual_received_Attach_Acc
fi
failed_attach=0
if [ ! -z "$actual_sent_Attach_Req" ]
then
  failed_attach=$(expr $actual_sent_Attach_Req - $expected_sent_Attach_Req)
  failed_attach=${failed_attach#-}
fi

# Calculate successful/failed detach
successful_detach=$expected_received_Detach_Acc
if [ ! -z "$actual_received_Detach_Acc" ]
then
  successful_detach=$actual_received_Detach_Acc
fi
failed_detach=0
if [ ! -z "$actual_sent_Detach_Req" ]
then
  failed_detach=$(expr $actual_sent_Detach_Req - $expected_sent_Detach_Req)
  failed_detach=${failed_detach#-}
fi

# Calculate successful/failed ping
successful_ping=$pktgen_received_total_packets
failed_ping=$(expr $pktgen_sent_total_packets - $pktgen_received_total_packets)

# Verify that variables values are valid
for var in "${results[@]}"
do
  [ -z "${!var}" ] && echo "$var is empty, skip processing this log..." && exit 1
  [ "${!var}" -lt 0 ] && echo "$var is negative, skip processing this log..." && exit 1
done

# Convert 0 to 0.1 for plotting in log scale
for var in "${results[@]}"
do
  [[ ${!var} == 0 ]] && eval "$var"="0.1"
done

# Generate csv file
CSV_FILE=$NG40_LOG_DIR$(echo $NG40_LOG_FILE | cut -d. -f1)".csv"
> $CSV_FILE

for var in "${results[@]}"
do
  printf $var"," >> $CSV_FILE
done
sed -i '$ s/.$/\n/' $CSV_FILE

for var in "${results[@]}"
do
  printf "${!var}," >> $CSV_FILE
done
sed -i '$ s/.$/\n/' $CSV_FILE

# TODO: extract test duration and save to csv
# TODO: extract more test data (e.g. rate, loop number etc.) and save to csv
