#!/bin/bash
# uninstall.sh - Uninstaller for omarchy-plugin-wifi-privacy
# Reverts system configurations and removes the Omarchy shell plugin.

set -euo pipefail

echo "=== Uninstalling Omarchy Wi-Fi Privacy Plugin ==="

if [[ $EUID -ne 0 ]]; then
  echo "Elevating privileges with sudo to remove system rules..."
  exec sudo "$0" "$@"
fi

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

echo "[1/4] Removing NetworkManager privacy configurations..."
rm -f /etc/NetworkManager/conf.d/30-wifi-privacy.conf
rm -f /etc/NetworkManager/dispatcher.d/pre-up.d/10-dhcp-hostname-privacy.sh
systemctl reload NetworkManager 2>/dev/null || true

echo "[2/4] Restoring Avahi mDNS configuration..."
AVAHI_STATE_FILE="/etc/avahi/.wifi-privacy-avahi.state"
if [[ -f /etc/avahi/avahi-daemon.conf ]]; then
  if [[ -f "$AVAHI_STATE_FILE" ]]; then
    PRIOR_STATE=$(cat "$AVAHI_STATE_FILE" 2>/dev/null | tr -d '[:space:]' || echo "unset")
    if [[ "$PRIOR_STATE" == "yes" ]]; then
      # Administrator originally had disable-publishing=yes; preserve it
      sed -i -E 's/^[#\s]*disable-publishing\s*=.*/disable-publishing=yes/' /etc/avahi/avahi-daemon.conf
    elif [[ "$PRIOR_STATE" == "no" ]]; then
      # Administrator originally had disable-publishing=no; restore it
      sed -i -E 's/^[#\s]*disable-publishing\s*=.*/disable-publishing=no/' /etc/avahi/avahi-daemon.conf
    else
      # Was not explicitly set prior to install; revert to commented default
      sed -i -E 's/^[#\s]*disable-publishing\s*=.*/#disable-publishing=no/' /etc/avahi/avahi-daemon.conf
    fi
    rm -f "$AVAHI_STATE_FILE"
    systemctl restart avahi-daemon 2>/dev/null || true
  fi
fi

echo "[3/4] Removing CLI utility..."
rm -f /usr/local/bin/omarchy-wifi-privacy

echo "[4/4] Removing Omarchy shell plugin..."
PLUGIN_DEST="$TARGET_HOME/.config/omarchy/plugins/io.github.loupibe.omarchy-wifi-privacy"
rm -rf "$PLUGIN_DEST"

# Remove from bar if present
su - "$TARGET_USER" -c "omarchy bar remove io.github.loupibe.omarchy-wifi-privacy 2>/dev/null || true"
su - "$TARGET_USER" -c "omarchy-shell shell rescanPlugins 2>/dev/null || true"

echo ""
echo "=== Uninstallation Complete! ==="
