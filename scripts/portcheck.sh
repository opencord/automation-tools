#!/bin/bash
#Below are the list of ports which are required to be free, for the SEBA services to use. If any new services get added into SEBA, Update the required node ports below and also add it to the arrray arr.

#Service name :  node Port number
#onos-debugger: 30555
#onos-openflow: 31653
#onos-ssh: 30115
#onos-ui: 30120
#xos-chameleon: 30006
#xos-core: 30010, 30011
#xos-core-prometheus: 30009
#xos-gui: 30001
#xos-tosca: 30007
#xos-ws: 30008
#ingress-nginx: 30080, 30443
#vcli: 30110
#voltha: 30125, 30613, 32443, 31390
#kpi-exporter: 31080
#logging-elasticsearch-client: 31636
#logging-kibana: 30601
#nem-monitoring-grafana: 31300
#nem-monitoring-prometheus-server: 31301

declare -a arr=("30555" "31653" "30115" "30120" "30006" "30010" "30011" "30009" "30001" "30007" "30008" "30080" "30443" "30110" "30125" "30613" "32443" "31390" "31080" "31636" "30601" "31300" "31301")

listenPortCount=0

#Below loop is to check whether any port in the list is already being used
for port in "${arr[@]}"
do
        if netstat -lntp | grep :":$port" > /dev/null ; then
                used_process=$(netstat -lntp | grep :":$port" | tr -s ' ' | cut -f7 -d' ')
                echo "Process with PID/Program_name $used_process is already listening on port: $port needed by SEBA"
                listenPortCount=$((listenPortCount+1))
        fi
done

#If any of the ports are already used then the user will be notified to kill the running services before installing SEBA
if [ $listenPortCount -gt 0 ]
    then
        echo "Kill the running services mentioned above before proceeding to install SEBA"
        echo "Terminating make"
        exit 64
fi

#The ports that are required by SEBA components will be added to the reserved port list
        var=$(printf '%s,' "${arr[@]}")
        echo "$var" > /proc/sys/net/ipv4/ip_local_reserved_ports


