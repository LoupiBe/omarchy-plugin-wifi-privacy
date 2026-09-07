#!/bin/bash
# install.sh - Installer for omarchy-plugin-wifi-privacy
# Configures NetworkManager, Avahi, dispatcher scripts, and the Omarchy Shell plugin.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_HOME="${HOME}"

echo "=== Installing Omarchy Wi-Fi Privacy Plugin ==="

# 1. Require sudo privileges for system configuration
if [[ $EUID -ne 0 ]]; then
  echo "Elevating privileges with sudo to install system rules..."
  exec sudo "$0" "$@"
fi

# Detect calling regular user if run via sudo
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

echo "[1/5] Installing NetworkManager privacy configurations..."
mkdir -p /etc/NetworkManager/conf.d
cp -f "$SCRIPT_DIR/system/30-wifi-privacy.conf" /etc/NetworkManager/conf.d/30-wifi-privacy.conf
chmod 644 /etc/NetworkManager/conf.d/30-wifi-privacy.conf

echo "[2/5] Installing NetworkManager dispatcher hostname cloaking hook..."
mkdir -p /etc/NetworkManager/dispatcher.d/pre-up.d
cp -f "$SCRIPT_DIR/system/10-dhcp-hostname-privacy.sh" /etc/NetworkManager/dispatcher.d/pre-up.d/10-dhcp-hostname-privacy.sh
chmod 755 /etc/NetworkManager/dispatcher.d/pre-up.d/10-dhcp-hostname-privacy.sh

echo "[3/5] Hardening Avahi mDNS (disabling local network advertising)..."
AVAHI_STATE_FILE="/etc/avahi/.wifi-privacy-avahi.state"
if [[ -f /etc/avahi/avahi-daemon.conf ]]; then
  # Record exact prior state before modifying if not already saved
  if [[ ! -f "$AVAHI_STATE_FILE" ]]; then
    if grep -qE "^\s*disable-publishing\s*=\s*yes" /etc/avahi/avahi-daemon.conf; then
      echo "yes" > "$AVAHI_STATE_FILE"
    elif grep -qE "^\s*disable-publishing\s*=\s*no" /etc/avahi/avahi-daemon.conf; then
      echo "no" > "$AVAHI_STATE_FILE"
    else
      echo "unset" > "$AVAHI_STATE_FILE"
    fi
    chmod 600 "$AVAHI_STATE_FILE"
  fi

  if grep -qE "^\s*#?\s*disable-publishing\s*=" /etc/avahi/avahi-daemon.conf; then
    sed -i -E 's/^[#\s]*disable-publishing\s*=.*/disable-publishing=yes/' /etc/avahi/avahi-daemon.conf
  else
    if grep -q "\[publish\]" /etc/avahi/avahi-daemon.conf; then
      sed -i '/\[publish\]/a disable-publishing=yes' /etc/avahi/avahi-daemon.conf
    else
      echo -e "\n[publish]\ndisable-publishing=yes" >> /etc/avahi/avahi-daemon.conf
    fi
  fi
  systemctl restart avahi-daemon 2>/dev/null || true
fi

echo "[4/5] Installing CLI utility to /usr/local/bin/omarchy-wifi-privacy..."
cp -f "$SCRIPT_DIR/bin/omarchy-wifi-privacy" /usr/local/bin/omarchy-wifi-privacy
chmod 755 /usr/local/bin/omarchy-wifi-privacy

echo "[5/5] Linking Omarchy shell plugin for user '$TARGET_USER'..."
PLUGIN_DEST="$TARGET_HOME/.config/omarchy/plugins/io.github.loupibe.omarchy-wifi-privacy"
mkdir -p "$TARGET_HOME/.config/omarchy/plugins"

if [[ -L "$PLUGIN_DEST" && "$(readlink -f "$PLUGIN_DEST")" == "$SCRIPT_DIR" ]]; then
  echo "Development symlink for '$PLUGIN_DEST' already points to repo; preserving."
else
  rm -rf "$PLUGIN_DEST"
  mkdir -p "$PLUGIN_DEST"
  cp -r "$SCRIPT_DIR/manifest.json" "$SCRIPT_DIR/omarchy-plugin.json" "$SCRIPT_DIR/BarWidget.qml" "$SCRIPT_DIR/Panel.qml" "$SCRIPT_DIR/Model.js" "$SCRIPT_DIR/bin" "$PLUGIN_DEST/"
  chown -R "$TARGET_USER:$TARGET_USER" "$PLUGIN_DEST"
fi

# Reload NetworkManager to pick up conf.d
echo "Reloading NetworkManager..."
systemctl reload NetworkManager 2>/dev/null || true

# Rescan plugins in omarchy-shell
echo "Rescanning Omarchy shell plugins..."
su - "$TARGET_USER" -c "omarchy-shell shell rescanPlugins 2>/dev/null || true"

echo ""
echo "=== Installation Complete! ==="
echo "All untrusted Wi-Fi connections will now automatically use randomized MACs"
echo "and cloaked DHCP hostnames."
echo ""
echo "To trust a specific network (such as your home or office Wi-Fi) and"
echo "preserve your hardware MAC and real hostname, run:"
echo "  omarchy-wifi-privacy trust [SSID]"
echo ""
echo "You can add the widget to your bar by running:"
echo "  omarchy bar add io.github.loupibe.omarchy-wifi-privacy --section right"
echo ""
echo "Check your privacy status at any time with:"
echo "  omarchy-wifi-privacy status"
