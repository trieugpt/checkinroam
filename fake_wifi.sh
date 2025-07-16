#!/bin/bash

wifi_iface="wlan1"
net_iface="enp0s3"
hostapd_conf="/etc/hostapd/hostapd.conf"
dnsmasq_conf="/etc/dnsmasq.conf"
dnsmasq_backup="/etc/dnsmasq.conf.bak"

cleanup() {
    sudo pkill hostapd
    sudo pkill dnsmasq
    sudo iptables -t nat -F
    sudo systemctl restart NetworkManager
    [[ -f "$dnsmasq_backup" ]] && sudo mv "$dnsmasq_backup" "$dnsmasq_conf"
    echo "[✓] Done."
}
trap cleanup EXIT

if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo."
    exit 1
fi

while true; do
    echo -e "\nEnter 3 lines:"
    echo "1. MAC"
    echo "2. SSID"
    echo "3. Password"
    echo -n "> "
    input=""
    for i in {1..3}; do read line; input+="$line"$'\n'; done
    mac_raw=$(echo "$input" | sed -n '1p')
    ssid=$(echo "$input" | sed -n '2p')
    pass=$(echo "$input" | sed -n '3p')
    mac_clean=$(echo "$mac_raw" | tr -d ':-|%#&$@*^{}[]()<>"\\''' ')
    mac=$(echo "$mac_clean" | sed 's/..\B/&:/g')
    [[ ! "$mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] && echo "Invalid MAC" && continue
    [[ -z "$ssid" ]] && echo "SSID empty" && continue
    [[ ${#pass} -lt 8 ]] && echo "Password too short" && continue
    break
done

sudo ip link set $wifi_iface down
sudo ip link set $wifi_iface address $mac
sudo ip link set $wifi_iface up

sudo bash -c "cat > $hostapd_conf" <<EOF
interface=$wifi_iface
driver=nl80211
ssid=$ssid
hw_mode=g
channel=6
wmm_enabled=0
auth_algs=1
wpa=2
wpa_passphrase=$pass
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

sudo pkill dnsmasq 2>/dev/null
[[ -f "$dnsmasq_conf" ]] && sudo mv "$dnsmasq_conf" "$dnsmasq_backup"
sudo bash -c "cat > $dnsmasq_conf" <<EOF
interface=$wifi_iface
dhcp-range=192.168.88.10,192.168.88.100,12h
EOF

sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null
sudo iptables -t nat -A POSTROUTING -o $net_iface -j MASQUERADE
sudo systemctl stop NetworkManager
sudo hostapd $hostapd_conf &
sleep 2
sudo dnsmasq

echo -e "\n✅ Hotspot running!"
echo "SSID : $ssid"
echo "PASS : $pass"
echo "MAC  : $mac"
echo "[Ctrl+C to stop]"
sleep infinity
