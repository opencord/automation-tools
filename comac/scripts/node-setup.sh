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

SRIOV_PF=${1:?"Specify SR-IOV interface name as argv[1]"}
NR_HUGEPAGE=32

if [ "$(id -u)" != "0" ]; then
        echo "FAIL: You should run this as root."
        echo "HINT: sudo $0 $SRIOV_PF"
        exit 1
fi

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

# Check hardware virtualization is enabled
# --------------------------
virt=$(grep -E -m1 -w '^flags[[:blank:]]*:' /proc/cpuinfo | grep -E -wo '(vmx|svm)') || true
if [ -z "$virt" ]; then
        echo "FATAL: Your CPU does not support hardware virtualization."
        exit 1
fi

msr="/dev/cpu/0/msr"
if [ ! -r "$msr" ]; then
        modprobe msr
fi

disabled=0
if [ "$virt" = "vmx" ]; then
        BIT=$(rdmsr --bitfield 0:0 0x3a 2>/dev/null || true)
        if [ "$BIT" = "1" ]; then
                BIT=$(rdmsr --bitfield 2:2 0x3a 2>/dev/null || true)
                if [ "$BIT" = "0" ]; then
                        disabled=1
                fi
        fi
elif [ "$virt" = "svm" ]; then
        BIT=$(rdmsr --bitfield 4:4 0xc0010114 2>/dev/null || true)
        if [ "$BIT" = "1" ]; then
                disabled=1
        fi
else
        echo "FATAL: Unknown virtualization extension: $virt."
        exit 1
fi

if [ "$disabled" -eq 1 ]; then
        echo "FAIL: $virt is disabled by BIOS"
        echo "HINT: Enter your BIOS setup and enable Virtualization Technology (VT),"
        echo "      and then hard poweroff/poweron your system"
else
        echo "  OK: $virt is enabled"
fi

# Ensure IOMMU is enabled
# --------------------------
if ! compgen -G "/sys/class/iommu/*/devices" > /dev/null; then
        disabled=1
        echo "INFO: IOMMU is disabled"
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

if ! check_vf; then
        cp "$(cd "$(dirname "$0")" && pwd)/sriov.sh" /usr/bin/sriov.sh
        tee "/etc/systemd/system/sriov.service" > /dev/null << EOF
[Unit]
Description=Create VFs on $SRIOV_PF

[Service]
Type=oneshot
ExecStart=/usr/bin/sriov.sh -b $SRIOV_PF

[Install]
WantedBy=default.target
EOF
        systemctl daemon-reload
        systemctl enable --now sriov.service &> /dev/null
        echo "      Configured VFs on $SRIOV_PF"
fi

if check_vf; then
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
