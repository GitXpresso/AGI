#!/bin/bash
# === KDE + OpenVPN + noVNC startup script ===

set -e

# --- Configuration ---
USER="kdeuser"
OVPN_FILE="/home/${USER}/client.ovpn"
CRED_FILE="/etc/openvpn/credentials.txt"
RUNTIME_DIR="/tmp/runtime-${USER}"
NOVNC_DIR="/usr/share/novnc"
VNC_PORT=5900
NOVNC_PORT=6090
VPN_INTERFACE="tun0"
OPENVPN_LOG="/var/log/openvpn.log"
PERSISTENCE_FILE="/home/${USER}/container_status.log"

# --- Environment setup ---
export DISPLAY=:0
export XDG_RUNTIME_DIR="$RUNTIME_DIR"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$RUNTIME_DIR"

# --- Timezone ---
ln -sf /usr/share/zoneinfo/America/Indiana/Indianapolis /etc/localtime
echo "America/Indiana/Indianapolis" > /etc/timezone

# --- D-Bus setup ---
echo "[+] Starting system D-Bus..."
mkdir -p /run/dbus
if ! dbus-daemon --system --fork; then
    echo "[!] Warning: D-Bus system may not start (container mode)."
fi

echo "[+] Starting user D-Bus session..."
eval $(dbus-launch --sh-syntax)

# --- Virtual Display ---
echo "[+] Starting Xvfb virtual display..."
Xvfb :0 -screen 0 1920x1080x24 &
sleep 3

# --- KDE Plasma ---
echo "[+] Starting KDE Plasma desktop..."
sudo -u "${USER}" bash -c "startplasma-x11" &
sleep 5

# --- KDE Connect ---
echo "[+] Starting KDE Connect daemon..."
sudo -u "${USER}" kdeconnectd &
sleep 3

# --- VNC + noVNC setup ---
echo "[+] Starting x11vnc server on port ${VNC_PORT}..."
x11vnc -display :0 -nopw -forever -shared -rfbport ${VNC_PORT} &

echo "[+] Starting noVNC on port ${NOVNC_PORT}..."
if [ -f "${NOVNC_DIR}/vnc.html" ]; then
    websockify --web "${NOVNC_DIR}" ${NOVNC_PORT} localhost:${VNC_PORT} &
elif [ -f "${NOVNC_DIR}/app/vnc.html" ]; then
    websockify --web "${NOVNC_DIR}/app" ${NOVNC_PORT} localhost:${VNC_PORT} &
else
    echo "[!] ERROR: Could not find vnc.html in ${NOVNC_DIR}"
    exit 1
fi

# --- OpenVPN setup ---
echo "[+] Starting OpenVPN..."
touch "$OPENVPN_LOG"
chmod 644 "$OPENVPN_LOG"

if [ ! -f "$OVPN_FILE" ] || [ ! -f "$CRED_FILE" ]; then
    echo "[!] Missing VPN config or credentials. Running without VPN."
    VPN_IP="VPN_Disabled"
else
    setsid openvpn --config "$OVPN_FILE" \
        --daemon \
        --log "$OPENVPN_LOG" \
        --writepid /var/run/openvpn.pid

    echo "[+] Waiting for VPN tunnel to establish..."
    sleep 15

    if ip addr show "$VPN_INTERFACE" 2>/dev/null | grep -q 'inet '; then
        VPN_IP=$(ip addr show "$VPN_INTERFACE" | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
        echo "[â] VPN IP: $VPN_IP ($VPN_INTERFACE)"
    else
        echo "[â] VPN interface not up. Check log at $OPENVPN_LOG"
        tail -n 10 "$OPENVPN_LOG"
        VPN_IP="Unknown"
    fi
fi

# --- Info output ---
echo "------------------------------------------------------------"
echo "[+] KDE + noVNC started successfully!"
echo "    noVNC URL: http://localhost:${NOVNC_PORT}/vnc.html"
echo "    KDE Connect VPN IP: ${VPN_IP}"
echo "------------------------------------------------------------"

# --- Keep container alive ---
touch "$PERSISTENCE_FILE"
echo "Running persistence loop..."
exec tail -f "$PERSISTENCE_FILE"

