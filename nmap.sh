#!/bin/bash

echo "Starting Network Mapping on host $1" >/home/auto_mode/logs/nmap.log
echo "Finding Hosts..">> /home/auto_mode/logs/nmap.log

#Aktive hosts werden gesucht und IP Adressen der Hosts gespeichert
ips=$(sudo nmap -sn $1 | tee /home/auto_mode/logs/nmap.log | awk '/Nmap scan report for/ {print $6}' | tr -d '()')

echo "List of active hosts in Network:" >>/home/auto_mode/logs/nmap.log
echo $ips | tr ' ' '\n'>> /home/auto_mode/logs/nmap.log

#Mithilfe der Liste der IP Adressen wird versucht mittels OS Fingerprinting das Betriebssystem zu ermitteln
echo "Attempting to determine OS of hosts..">> /home/auto_mode/logs/nmap.log
nmap -O $ips>>/home/auto_mode/logs/nmap.log

#Hier werden die Services gescannt die auf den Hosts laufen
echo "Scanning services that are running on hosts..">> /home/auto_mode/logs/nmap.log
nmap $ips -sV>> /home/auto_mode/logs/nmap.log

#Hier wird die Nmap scripting engine verwendet um nach bekannten Schwachstellen zu suchen
echo "Running Nmap script to look for know vulnerabilities">> /home/auto_mode/logs/nmap.log
nmap $ips -script vuln >> /home/auto_mode/logs/nmap.log

