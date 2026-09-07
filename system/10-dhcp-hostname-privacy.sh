#!/bin/bash
# /etc/NetworkManager/dispatcher.d/pre-up.d/10-dhcp-hostname-privacy.sh
# Managed by omarchy-plugin-wifi-privacy
# Automatically assigns realistic consumer hostnames to untrusted Wi-Fi connections.

set -euo pipefail

IFACE="${1:-}"
ACTION="${2:-}"

# Only handle pre-up events on wireless interfaces
[[ "$ACTION" == "pre-up" ]] || exit 0
[[ -n "$IFACE" ]] || exit 0
[[ -d "/sys/class/net/${IFACE}/wireless" ]] || exit 0

UUID="${CONNECTION_UUID:-}"
[[ -n "$UUID" ]] || exit 0

# Check if connection is explicitly configured to preserve physical MAC (trusted)
CLONED_MAC=$(nmcli -g 802-11-wireless.cloned-mac-address connection show "$UUID" 2>/dev/null || true)
if [[ "$CLONED_MAC" == "preserve" ]]; then
  # Trusted network: keep real system hostname
  exit 0
fi

# For untrusted networks, check if a fake hostname is already assigned
CURRENT_DHCP_HOST=$(nmcli -g ipv4.dhcp-hostname connection show "$UUID" 2>/dev/null || true)
if [[ -z "$CURRENT_DHCP_HOST" ]]; then
  # Generate a realistic laptop name (e.g. LAPTOP-7F4K2A)
  RAND_ID=$(head -c 16 /dev/urandom | tr -dc 'A-Z0-9' | head -c 6)
  if [[ ${#RAND_ID} -lt 6 ]]; then
    RAND_ID=$(printf '%04X%02X' "$RANDOM" "$((RANDOM % 256))")
  fi
  FAKE_NAME="LAPTOP-${RAND_ID}"

  nmcli connection modify "$UUID" \
    ipv4.dhcp-send-hostname "true" \
    ipv6.dhcp-send-hostname "true" \
    ipv4.dhcp-hostname "$FAKE_NAME" \
    ipv6.dhcp-hostname "$FAKE_NAME" 2>/dev/null || true
fi

exit 0
