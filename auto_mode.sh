#!/bin/bash

#Diese Codezeile führt dazu, dass automatisch aus dem User ausgeloggt wird, wenn das
#Skript abgebrochen wird
trap 'mate-session-save --force-logout' SIGINT SIGTERM SIGQUIT SIGTSTP

#Deaktiviere Maus
mouse_ids=$(xinput list | grep "Mouse" | grep -o 'id=[0-9]*' | awk -F= '{print$2}')

for mouse_id in $mouse_ids; do
    xinput --disable "$mouse_id"
done

#Startcounter für den automatischen Modus
for ((i=0; i>=10; i--));
do
    echo -n -e "Starting auto mode in $i seconds.\nPress Ctrl + C to run Portable Network Scanner in manual mode!"
    sleep 1
    clear
done

echo "Starting automatic mode. Press Ctrl + C to quit"

##################################################################################################################
# Netzwerkverbindung 
##################################################################################################################


#Hilfsfunktion zum extrahieren der IP_Adresse und der Subnetzmaske
get_ip+sub(){
    ip addr show $1 | awk  '/inet / {print $2}'
}

ips=()
active_ifs=()

for ((i=0; i<2; i++));
do
    if [ $i -ne 1 ]; then
        # Überprüfe mittels grep ob das Gerät über Ethernet Kabel an Netzwerk gebunden ist
        if ip addr show eth0 | grep -q "inet "; then
            # Falls ja, extrahiere IP-Adresse & Subnetzmaske mittels Regex
            ip_eth0=$(get_ip+sub eth0)
            ips+=("$ip_eth0")
            active_ifs+=("eth0")
            echo "Device is connected to eth0 with IP address: $ip_eth0">> /home/auto_mode/logs/auto_mode.log
        fi
    fi

    # Überprüfung der integrierten W-Lan Karte
    if ip addr show wlan0 | grep -q "inet "; then
        # Get IP address and subnet for wlan0
        ip_wlan0=$(get_ip+sub wlan0) 
        ips+=("$ip_wlan0") 
        active_ifs+=("wlan0")
        echo "Device is connected to wlan0 with IP address: $ip_wlan0">> /home/auto_mode/logs/auto_mode.log    
    fi

    if [ -z $(ifconfig wlan1 | grep "not found") ]; then
        # Überprüfung der externen W-Lan Karte
        if ip addr show wlan1 | grep -q "inet "; then
            # Get IP address and subnet for wlan0
            ip_wlan1=$(get_ip+sub wlan1)
            ips+=("$ip_wlan1") 
            active_ifs+=("wlan1")
            echo "Device is connected to wlan1 with IP address: $ip_wlan1">> /home/auto_mode/logs/auto_mode.log    
        fi
    fi

    if [ ${#ips[@]} -eq 0 ]; then
        echo "Trying to connect to wireless network...">> /home/auto_mode/logs/auto_mode.log
        /home/auto_mode/scripts/connection.sh>> /home/auto_mode/logs/auto_mode.log

        if [ $? -ne 0 ]; then
            echo "Unable to connect to a network. Exiting...">> /home/auto_mode/logs/auto_mode.log
            mate-session-save --force-logout>> /home/auto_mode/logs/auto_mode.log
        fi
    else
        break
    fi
done

if [ ${#ips[@]} -eq 0 ]; then
    echo "Unable to retrieve IP Adresses. Exiting...">> /home/auto_mode/logs/auto_mode.log
    mate-session-save --force-logout>> /home/auto_mode/logs/auto_mode.log
fi

brd_addr=()


#Netzwerkadressen werden berechnet.
echo "Broadcast addresses are being calculated for given subnets...">> /home/auto_mode/logs/auto_mode.log 
for ip in "${ips[@]}"; do
    echo "Calculating network adress of $ip...">> /home/auto_mode/logs/auto_mode.log 
    brd_addr+=($(ipcalc $ip | awk '/Network/ {print $2}'))
done


#Doppelte Netzwerkadressen werden rausgefilert
brd_addr=($(echo "${brd_addr[@]}" | awk '{for(i=1;i<=NF;i++) if(!seen[$1]++) print $1}'))
echo "${#brd_addr[@]} unique network adress(es) found: ${brd_addr[@]}">> /home/auto_mode/logs/auto_mode.log

#Nmap wird gestartet
echo "Starting network mapping">> /home/auto_mode/logs/auto_mode.log
for network in "${brd_addr[@]}"; do
    echo "Mapping network $network...">> /home/auto_mode/logs/auto_mode.log
   /home/auto_mode/scripts/nmap.sh "$network">> /home/auto_mode/logs/auto_mode.log
done
echo "Finished Nmap scan">> /home/auto_mode/logs/auto_mode.log

echo "Starting packet sniffing"
/home/auto_mode/scripts/nmap.sh>> /home/auto_mode/logs/auto_mode.log 
mate-session-save --force-logout
