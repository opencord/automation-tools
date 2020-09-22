#!/usr/bin/env python3

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

# This script iterates through packets captured in pcap file and maps UE IDs to
# corresponding packet indices. Then for each UE it validates if the packet sequence
# looks correct (e.g. including attach/detach request/accept etc.). Otherwise print
# missing packets associtated with UE ID and IMSI.
#
# Usage: pcap-analyze.py xxx.pcap

import sys
import re
import pyshark

# Map from UE ID to packet index
packetMap = {}
# All the packets captured in pcap file
captures = None

def groupPacket(pkt, i):
    if 's1ap' in pkt:
        #ueId = pkt.s1ap.enb_ue_s1ap_id

        # Looks like pyshark cannot handle packets with multiple sctp data chunks
        # So use regex match as a workaround
        ueIds = re.findall(r'ENB-UE-S1AP-ID: (\d+)', str(pkt))
        for ueId in ueIds:
            if not ueId in packetMap.keys():
                packetMap[ueId] = []
            packetMap[ueId].append(i)

def validate(ueId, packets):
    # Get IMSI value from the first packet (assuming it's attach request)
    # Again using regex is a workaround as pyshark cannot handle multiple sctp data chunks

    # FIXME: IMSI value could be wrong if the first packet is not attach request (e.g.
    # when packet contains multiple sctp data chunks)
    imsi = re.findall(r'IMSI: (\d+)', str(captures[packets[0]]))
    # TODO: validate more attach/detach messages in addition to request and accept
    for keyword in ['Attach request', 'Attach accept', 'Detach request', 'Detach accept']:
        try:
            assert any(keyword in str(captures[packet]) for packet in packets)
        except Exception:
            print('UE #{} (IMSI: {}): missing "{}"'.format(ueId, imsi, keyword))
            break

if __name__ == "__main__":
    pcapFile = str(sys.argv[1])
    captures = pyshark.FileCapture(pcapFile)
    p = captures[0]
    i = 0
    # Extract UE ID for each packet and group packets with the same UE ID
    while(p):
        groupPacket(p, i)
        try:
            p = captures.next()
        except Exception:
            break
        i += 1

    # Check attach/detach packets for each UE
    for ueId, packets in packetMap.items():
        validate(ueId, packets)
