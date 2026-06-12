#!/usr/bin/env bash

set -euo pipefail

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "Please run this script as root."
    exit 1
  fi
}

validate_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( "$1" >= 1 && "$1" <= 65535 ))
}

require_root

echo "Cloudflare Tunnel + sing-box installer"
echo "--------------------------------------"

read -rp "Tunnel name (example: tw-01): " TUNNEL_NAME
read -rp "Domain to bind (example: tw.example.com): " DOMAIN
read -rp "Local port (example: 19090): " LOCAL_PORT
read -rp "WebSocket path (must start with /, example: /xui): " WS_PATH
read -rp "VLESS UUID (leave empty to auto-generate): " USER_UUID

if [[ -z "${TUNNEL_NAME}" || -z "${DOMAIN}" || -z "${LOCAL_PORT}" || -z "${WS_PATH}" ]]; then
  echo "TUNNEL_NAME, DOMAIN, LOCAL_PORT and WS_PATH are required."
  exit 1
fi

if ! validate_port "${LOCAL_PORT}"; then
  echo "LOCAL_PORT must be a number between 1 and 65535."
  exit 1
fi

if [[ "${WS_PATH}" != /* ]]; then
  echo "WS_PATH must start with /"
  exit 1
fi

if [[ -z "${USER_UUID}" ]]; then
  if need_cmd uuidgen; then
    USER_UUID="$(uuidgen)"
  else
    USER_UUID="$(cat /proc/sys/kernel/random/uuid)"
  fi
fi

echo "UUID: ${USER_UUID}"

echo
echo "--------------------------------------"
echo "Installing or checking cloudflared..."

if ! need_cmd cloudflared; then
  TMP_DEB="$(mktemp /tmp/cloudflared.XXXXXX.deb)"
  wget -q "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb" -O "${TMP_DEB}"
  dpkg -i "${TMP_DEB}" >/dev/null 2>&1 || (apt-get update -y && apt-get install -y "${TMP_DEB}")
  rm -f "${TMP_DEB}"
fi

CLOUDFLARED_BIN="$(command -v cloudflared)"

mkdir -p /root/.cloudflared
cd /root/.cloudflared

echo
echo "Cloudflare login is required."
echo "A browser authorization URL will be printed next."
cloudflared tunnel login

if cloudflared tunnel list | awk 'NR>1 {print $2}' | grep -Fxq "${TUNNEL_NAME}"; then
  echo "Tunnel ${TUNNEL_NAME} already exists, reusing it."
else
  echo "Creating tunnel ${TUNNEL_NAME}..."
  cloudflared tunnel create "${TUNNEL_NAME}"
fi

TUNNEL_ID="$(cloudflared tunnel list | awk -v name="${TUNNEL_NAME}" '$2 == name {print $1; exit}')"
if [[ -z "${TUNNEL_ID}" ]]; then
  echo "Failed to get tunnel ID for ${TUNNEL_NAME}."
  exit 1
fi

echo "Tunnel ID: ${TUNNEL_ID}"

cat > /root/.cloudflared/config.yml <<EOF
tunnel: ${TUNNEL_ID}
credentials-file: /root/.cloudflared/${TUNNEL_ID}.json

ingress:
  - hostname: ${DOMAIN}
    service: http://127.0.0.1:${LOCAL_PORT}
  - service: http_status:404
EOF

echo
echo "Routing DNS to Cloudflare Tunnel..."
if ! cloudflared tunnel route dns "${TUNNEL_NAME}" "${DOMAIN}"; then
  echo "cloudflared tunnel route dns failed."
  echo "If the DNS record already exists, verify it in Cloudflare and continue."
fi

cat > /etc/systemd/system/cloudflared.service <<EOF
[Unit]
Description=Cloudflare Tunnel Service (${TUNNEL_NAME})
After=network.target

[Service]
Type=simple
ExecStart=${CLOUDFLARED_BIN} --no-autoupdate --config /root/.cloudflared/config.yml tunnel run
Restart=always
RestartSec=5s
User=root
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable cloudflared
systemctl restart cloudflared

sleep 2
systemctl status cloudflared --no-pager | sed -n '1,15p'

echo
echo "--------------------------------------"
echo "Installing or checking sing-box..."

if ! need_cmd sing-box; then
  ARCH="$(uname -m)"
  case "${ARCH}" in
    x86_64) SB_ARCH="amd64" ;;
    aarch64|arm64) SB_ARCH="arm64" ;;
    *)
      echo "Unsupported architecture: ${ARCH}"
      exit 1
      ;;
  esac

  TMP_DIR="$(mktemp -d)"
  cd "${TMP_DIR}"

  LATEST="$(wget -qO- "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | grep tag_name | cut -d'"' -f4)"
  if [[ -z "${LATEST}" ]]; then
    echo "Failed to get the latest sing-box version."
    exit 1
  fi

  FILE="sing-box-${LATEST#v}-linux-${SB_ARCH}.tar.gz"
  wget -q "https://github.com/SagerNet/sing-box/releases/download/${LATEST}/${FILE}"
  tar -xzf "${FILE}"
  install -m 0755 "sing-box-${LATEST#v}-linux-${SB_ARCH}/sing-box" /usr/local/bin/sing-box

  cd /
  rm -rf "${TMP_DIR}"
else
  echo "sing-box is already installed."
fi

SINGBOX_BIN="$(command -v sing-box)"

mkdir -p /etc/sing-box
mkdir -p /var/log/sing-box
touch /var/log/sing-box/access.log /var/log/sing-box/error.log

cat > /etc/sing-box/config.json <<EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-ws-in",
      "listen": "127.0.0.1",
      "listen_port": ${LOCAL_PORT},
      "users": [
        {
          "uuid": "${USER_UUID}"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "${WS_PATH}",
        "headers": {
          "Host": "${DOMAIN}"
        }
      },
      "tls": {
        "enabled": false
      },
      "udp_fragment": true
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF

"${SINGBOX_BIN}" check -c /etc/sing-box/config.json

cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box service (VLESS+WS behind CF Tunnel)
After=network.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
ExecStart=${SINGBOX_BIN} run -c /etc/sing-box/config.json
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

sleep 2
systemctl status sing-box --no-pager | sed -n '1,15p'

echo
echo "--------------------------------------"
echo "Checking BBR support..."
if [[ -f /proc/sys/net/ipv4/tcp_congestion_control ]]; then
  if sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1; then
    echo "BBR enabled."
  else
    echo "BBR is not supported in the current environment. Skipped."
  fi
else
  echo "tcp_congestion_control not found. Skipped."
fi

if need_cmd python3; then
  ENC_PATH="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "${WS_PATH}" 2>/dev/null || printf '%s' "${WS_PATH}")"
else
  ENC_PATH="${WS_PATH}"
fi

VLESS_URL="vless://${USER_UUID}@${DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&sni=${DOMAIN}&path=${ENC_PATH}#VLESS-WS-CF"

echo
echo "Install complete."
echo "--------------------------------------"
echo "Domain: ${DOMAIN}"
echo "Tunnel name: ${TUNNEL_NAME}"
echo "Local port: ${LOCAL_PORT}"
echo "WS path: ${WS_PATH}"
echo "UUID: ${USER_UUID}"
echo "cloudflared config: /root/.cloudflared/config.yml"
echo "sing-box config: /etc/sing-box/config.json"
echo "--------------------------------------"
echo "Service status:"
systemctl is-active --quiet cloudflared && echo " - cloudflared: running" || echo " - cloudflared: not running"
systemctl is-active --quiet sing-box && echo " - sing-box: running" || echo " - sing-box: not running"
echo "--------------------------------------"
echo "Client URL:"
echo "${VLESS_URL}"
echo "--------------------------------------"
echo "To inspect logs:"
echo "journalctl -u cloudflared -f"
echo "journalctl -u sing-box -f"
