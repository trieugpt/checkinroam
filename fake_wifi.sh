#!/bin/bash

# ===================== CẤU HÌNH =====================
wifi_iface="wlan1"    # ← card WiFi dùng phát (sửa nếu cần)
net_iface="enp0s3"    # ← card có mạng Internet

hostapd_conf="/etc/hostapd/hostapd.conf"
dnsmasq_conf="/etc/dnsmasq.conf"
dnsmasq_backup="/etc/dnsmasq.conf.bak"

# ===================== DỌN DẸP KHI THOÁT =====================
cleanup() {
    echo "[•] Dọn dẹp..."
    sudo pkill hostapd
    sudo pkill dnsmasq
    sudo iptables -t nat -F
    sudo systemctl restart NetworkManager
    [[ -f "$dnsmasq_backup" ]] && sudo mv "$dnsmasq_backup" "$dnsmasq_conf"
    echo "[✓] Đã dọn dẹp."
}
trap cleanup EXIT

# ===================== KIỂM TRA ROOT =====================
if [[ $EUID -ne 0 ]]; then
    echo "❌ Vui lòng chạy với quyền sudo!"
    exit 1
fi

# ===================== NHẬP DỮ LIỆU NGƯỜI DÙNG =====================
while true; do
    echo -e "\n📥 Dán vào 3 dòng liên tiếp:"
    echo "1. Địa chỉ MAC"
    echo "2. Tên Wi-Fi (SSID)"
    echo "3. Mật khẩu (≥ 8 ký tự)"
    echo -n "> "

    input=""
    for i in {1..3}; do
        read line
        input+="$line"$'\n'
    done

    mac_raw=$(echo "$input" | sed -n '1p')
    ssid=$(echo "$input" | sed -n '2p')
    pass=$(echo "$input" | sed -n '3p')

    # Làm sạch MAC
    mac_clean=$(echo "$mac_raw" | tr -d ':-|%#&$@*^{}[]()<>"\\''' ')
    mac=$(echo "$mac_clean" | sed 's/.\{2\}/&:/g' | sed 's/:$//')

    if [[ ! "$mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
        echo "❌ MAC không hợp lệ: $mac"
        continue
    fi

    if [[ -z "$ssid" ]]; then
        echo "❌ SSID không được để trống!"
        continue
    fi

    if [[ ${#pass} -lt 8 ]]; then
        echo "❌ Mật khẩu phải ≥ 8 ký tự!"
        continue
    fi

    break
done

# ===================== CẤU HÌNH MAC =====================
echo "[•] Đặt MAC $mac cho $wifi_iface..."
sudo ip link set $wifi_iface down
sudo ip link set $wifi_iface address $mac
sudo ip link set $wifi_iface up

# ===================== CẤU HÌNH HOSTAPD =====================
echo "[•] Cấu hình hostapd..."
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

# ===================== CẤU HÌNH DHCP (dnsmasq) =====================
echo "[•] Cấu hình dnsmasq..."
sudo pkill dnsmasq 2>/dev/null
[[ -f "$dnsmasq_conf" ]] && sudo mv "$dnsmasq_conf" "$dnsmasq_backup"

sudo bash -c "cat > $dnsmasq_conf" <<EOF
interface=$wifi_iface
dhcp-range=192.168.88.10,192.168.88.100,12h
EOF

# ===================== CẤU HÌNH CHIA SẺ INTERNET =====================
echo "[•] Bật NAT và chia sẻ Internet..."
sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null
sudo iptables -t nat -A POSTROUTING -o $net_iface -j MASQUERADE

# ===================== KHỞI ĐỘNG HOTSPOT =====================
echo "[•] Tắt NetworkManager tạm thời..."
sudo systemctl stop NetworkManager

echo "[•] Bắt đầu phát WiFi..."
sudo hostapd $hostapd_conf &
sleep 2
sudo dnsmasq

# ===================== HOÀN TẤT =====================
echo -e "\n✅ HOTSPOT ĐÃ HOẠT ĐỘNG!"
echo "📶 SSID : $ssid"
echo "🔐 PASS : $pass"
echo "🕵️‍♂️ MAC  : $mac"
echo "🌐 Qua Internet: $net_iface"
echo "[!] Nhấn Ctrl+C để dừng và dọn dẹp."
sleep infinity
