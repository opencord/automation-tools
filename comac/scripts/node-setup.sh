#!/bin/bash

# Copyright 2019-present Open Networking Foundation
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

set -o pipefail

grub_updated=0
function update_grub_cmdline {
        local param=$1
        IFS='=' read -r key value <<< "$param"
        if ! grep -q "$key"= /etc/default/grub; then
                sed -i "s/^GRUB_CMDLINE_LINUX=\"/&${param} /" /etc/default/grub
        else
                sed -i "s/\\(${key}=\\)\\w*/\\1${value}/g" /etc/default/grub
        fi
        echo "      Added \"${param}\" is to kernel parameters"
        grub_updated=1
}

function check_vf {
        local pfpci
        local num_vfs

        pfpci=$(readlink /sys/devices/pci*/*/*/net/"$SRIOV_PF"/device | awk '{print substr($1,10)}')
        num_vfs=$(cat /sys/class/net/"$SRIOV_PF"/device/sriov_numvfs)
        if [ "$num_vfs" = "0" ]; then
                echo "INFO: SR-IOV VF does not exist"
                return 1
        fi
        return 0
}

function check_vf_vfio {
        local pfpci
        local num_vfs

        pfpci=$(readlink /sys/devices/pci*/*/*/net/"$SRIOV_PF"/device | awk '{print substr($1,10)}')
        num_vfs=$(cat /sys/class/net/"$SRIOV_PF"/device/sriov_numvfs)
        if [ "$num_vfs" = "0" ]; then
                echo "INFO: SR-IOV VF does not exist"
                return 1
        fi

        local vfpci
        local driver
        for ((idx = 0; idx < num_vfs; idx++)); do
                local vfn="virtfn$idx"
                # shellcheck disable=SC2012
                vfpci=$(ls -l /sys/devices/pci*/*/"$pfpci" | awk -v vfn=$vfn 'vfn==$9 {print substr($11,4)}')
                driver=$(lspci -vvv -s "$vfpci" | grep "Kernel driver in use" | awk '{print $5}')
                if [ "$driver" != "vfio-pci" ]; then
                        echo "INFO: SR-IOV VF $idx does not exist or is not binded to vfio-pci"
                        return 1
                fi
        done
        return 0
}

SRIOV_PF=
VFIO_ENABLED=
NR_HUGEPAGE=32

while :; do
    case $1 in
        -i|--interface)
            if [ "$2" ]; then
                SRIOV_PF=$2
                shift
            else
              echo 'FAIL: "--interface" requires a non-empty option arguments'
              exit 1
            fi
            ;;
        -v|--vfio)
            VFIO_ENABLED="-b"
            ;;
        -h|--help)
            echo "Usage:"
            echo "    sudo $0 -i [iface name]          Create VF from [iface name]."
            echo "    sudo $0 -i [iface name] --vfio   Create VF from [iface name] and bind it to VFIO driver."
            echo "    sudo $0 -h                       Display this help message."
            exit 0
            ;;
        *) break
    esac
    shift
done

if [ "$(id -u)" != "0" ]; then
        echo "FAIL: You should run this as root."
        echo "HINT: sudo $0 -i [iface name]"
        exit 1
fi

if [ -z "$SRIOV_PF" ]; then
        echo "FAIL: Interface name is required"
        echo "HINT: sudo $0 -i [iface name]"
        exit 1
fi

# Check VT-d is enabled in BIOS
# --------------------------
if ! dmesg | grep DMAR > /dev/null 2>&1; then
        echo "FAIL: Intel VT-d is not enabled in BIOS"
        echo "HINT: Enter your BIOS setup and enable VT-d and then poweroff/poweron your system"
else
        echo "  OK: Intel VT-d is enabled"
fi

# Ensure IOMMU is enabled
# --------------------------
if ! compgen -G "/sys/class/iommu/*/devices" > /dev/null; then
        disabled=1
        echo "INFO: IOMMU is not enabled"
        update_grub_cmdline "intel_iommu=on"
else
        echo "  OK: IOMMU is enabled"
fi

# Ensure hugepage is enabled
# --------------------------
hugepage=$(grep -i HugePages_Total /proc/meminfo | awk '{print $2}') || true
if [ "$hugepage" -eq "0" ]; then
        disabled=1
        echo "INFO: Hugepage is disabled"

        update_grub_cmdline "hugepages=$NR_HUGEPAGE"
        update_grub_cmdline "default_hugepagesz=1G"
        if ! grep -q "^vm.nr_hugepages" /etc/sysctl.conf; then
                echo "vm.nr_hugepages=$NR_HUGEPAGE" >> /etc/sysctl.conf
        fi
else
        echo "  OK: Hugepage is enabled"
fi

# Ensure SR-IOV is enabled
# --------------------------
if ! lsmod | grep -q vfio-pci; then
        echo 'vfio-pci' | tee /etc/modules-load.d/sriov.conf 1> /dev/null
        systemctl restart systemd-modules-load.service
fi

check_func=check_vf
if [ -n "$VFIO_ENABLED" ]; then
        check_func=check_vf_vfio
fi

if ! $check_func; then
        cp "$(cd "$(dirname "$0")" && pwd)/sriov.sh" /usr/bin/sriov.sh
        tee "/etc/systemd/system/sriov.service" > /dev/null << EOF
[Unit]
Description=Create VFs on $SRIOV_PF

[Service]
Type=oneshot
ExecStart=/usr/bin/sriov.sh $VFIO_ENABLED $SRIOV_PF

[Install]
WantedBy=default.target
EOF
        systemctl daemon-reload
        systemctl enable --now sriov.service &> /dev/null
        echo "      Configured VFs on $SRIOV_PF"
fi

if $check_func; then
        echo "  OK: SR-IOV is enabled on $SRIOV_PF"
else
        disabled=1
fi

if [ "$grub_updated" -eq 1 ]; then
        update-grub &> /dev/null
        echo "HINT: Grub was updated, reboot for changes to take effect"
        exit 1
fi

exit $disabled
