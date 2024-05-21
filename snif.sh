#!/bin/bash

echo "Starting packet sniffing"> /home/auto_mode/logs/dump.log

# Verfügbarer Speicherplatz
strg=$(df -h /dev/mmcblk0p2 | tail -n 1 | awk '{print $4}' | grep G | tr -d 'G')

strg=$((strg-20))

#Wenn weniger als 1 GB verfügbar ist dann Abbruch
if [ -z $strg ]; then
    echo "Not enough storage, consider emptying /home/auto_mode/logs! Exiting..." >> /home/auto_mode/logs/dump.log
    exit -1
fi

interfaces=($@)
network=""

echo "${#interfaces[@]} interfaces" >> /home/auto_mode/logs/dump.log

#alle Interfaces die verwendet werden
for interface in "${interfaces[@]}"; do
    current_net=$(ip -o -4  addr show $interface | awk '{print $6}')
    if [[ $current_net != $network ]]; then
        network=$current_net
        interfaces_ntwrk+=("$interface")
    fi
done

nntwrks="${#interfaces_ntwrk[@]}"

strg=$((strg/nntwrks))
nfiles=$((strg*1000000/200000))

echo "Max storage usable per interface: $strg GB" >> /home/auto_mode/logs/dump.log
echo "Starting packet dumping..." >> /home/auto_mode/logs/dump.log

for interface in $interfaces_ntwrk; do
    dumpcap -i $interface -q -b filesize:200000 -b files:$nfiles -B 1024  >> /home/auto_mode/logs/dump.log
done

#aufgrund eines Bugs funktioniert -w nicht und alle erstellen Dateien müssen in einen anderen ordner verschoben werden
mv /tmp/wireshark* /home/auto_mode/logs/caps

caps="/home/auto_mode/logs/caps"
for capture in "$caps"/*; do
    if [ -f "$file" ]; then
        capinfos $file>> /home/auto_mode/logs/dump.log
    fi
done
