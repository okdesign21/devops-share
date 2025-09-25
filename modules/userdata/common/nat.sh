#!/usr/bin/env bash

# Optional: PRIVATE_CIDRS exported by TF; default to RFC1918
PRIVATE_CIDRS="${PRIVATE_CIDRS:-10.0.0.0/8 172.16.0.0/12 192.168.0.0/16}"

# Ensure packages are present (iptables + persistence helpers)
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y iptables iptables-persistent netfilter-persistent

# Enable IP forwarding (persistent)
sed -i '/^net.ipv4.ip_forward/d' /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" >/etc/sysctl.conf
sysctl -p

# Write the NAT config script (logs to /var/log/nat-bootstrap.log)
install -d -m 0755 /usr/local/bin
cat >/usr/local/bin/configure-nat.sh <<'EOF'
#!/usr/bin/env bash
set -euxo pipefail
exec > >(tee -a /var/log/nat-bootstrap.log) 2>&1

PRIVATE_CIDRS="${PRIVATE_CIDRS:-10.0.0.0/8 172.16.0.0/12 192.168.0.0/16}"
NIC="$(ip -o -4 route show to default | awk '{print $5}' || true)"
NIC="${NIC:-eth0}"

# Add MASQUERADE rules (idempotent)
for cidr in ${PRIVATE_CIDRS}; do
  iptables -t nat -C POSTROUTING -s "${cidr}" -o "${NIC}" -j MASQUERADE 2>/dev/null \
    || iptables -t nat -A POSTROUTING -s "${cidr}" -o "${NIC}" -j MASQUERADE
done

# Save rules & ensure persistence
iptables-save >/etc/iptables/rules.v4
systemctl enable netfilter-persistent
systemctl restart netfilter-persistent || true
EOF
chmod +x /usr/local/bin/configure-nat.sh

# Create a systemd unit that runs after network is up
cat >/etc/systemd/system/nat-snat.service <<'EOF'
[Unit]
Description=Configure NAT SNAT (MASQUERADE)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=-/etc/default/nat-snat
ExecStart=/usr/local/bin/configure-nat.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Export PRIVATE_CIDRS to the unit (optional)
mkdir -p /etc/default
echo "PRIVATE_CIDRS=\"${PRIVATE_CIDRS}\"" >/etc/default/nat-snat

# Enable & start
systemctl daemon-reload
systemctl enable nat-snat.service
systemctl start nat-snat.service

