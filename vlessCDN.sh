#!/bin/bash
# ============================================================
# NAT 主机一体化部署：Cloudflare Tunnel（按你原脚本逻辑）+ sing-box VLESS+WS (TLS 由 CF)
# by ziYang 2025
# ============================================================

set -euo pipefail

echo "🌍 Cloudflare Tunnel + sing-box 一体化部署（NAT 适配）"
echo "-------------------------------------------------------"

# ========== 1) 基础输入 ==========
read -p "请输入 Tunnel 名称（例如 tw-01）: " TUNNEL_NAME
read -p "请输入要绑定的域名（例如 tw.ssr.com）: " DOMAIN
read -p "请输入本地转发端口（例如 19090）: " LOCAL_PORT

# sing-box 相关补充输入
read -p "请输入 WebSocket 路径（例如 /xui，以 / 开头）: " WS_PATH
read -p "请输入 VLESS 用户 UUID（留空自动生成）: " USER_UUID

if [[ -z "${TUNNEL_NAME}" || -z "${DOMAIN}" || -z "${LOCAL_PORT}" || -z "${WS_PATH}" ]]; then
  echo "❌ TUNNEL_NAME / DOMAIN / LOCAL_PORT / WS_PATH 不能为空"
  exit 1
fi

# 自动生成 UUID
if [[ -z "${USER_UUID}" ]]; then
  if command -v uuidgen >/dev/null 2>&1; then
    USER_UUID=$(uuidgen)
  else
    USER_UUID=$(cat /proc/sys/kernel/random/uuid)
  fi
fi

echo "✅ UUID: ${USER_UUID}"

# ========== 2) Cloudflare Tunnel（完全按你原脚本逻辑） ==========
echo ""
echo "---------------------------------------"
echo "🧩 检查并安装 cloudflared（如未安装）..."
if ! command -v cloudflared &> /dev/null; then
  wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -O /tmp/cloudflared.deb
  dpkg -i /tmp/cloudflared.deb >/dev/null 2>&1 || (apt-get update -y && apt-get install -y /tmp/cloudflared.deb >/dev/null 2>&1)
  rm -f /tmp/cloudflared.deb
fi

mkdir -p /root/.cloudflared
cd /root/.cloudflared

# 2.1 登录（会在终端打印一个“授权链接”，按提示在浏览器完成授权）
echo ""
echo "🔑 即将进行 Cloudflare 授权登录..."
echo "👉 注意：终端会输出一个 URL（授权链接），请在浏览器打开完成登录授权。"
cloudflared tunnel login   # <== 按你的脚本原样执行，这里会输出授权链接

# 2.2 创建 Tunnel
echo ""
echo "⚙️ 创建 Tunnel：$TUNNEL_NAME"
cloudflared tunnel create "$TUNNEL_NAME"

# 获取 Tunnel ID
TUNNEL_ID=$(cloudflared tunnel list | grep -w "$TUNNEL_NAME" | awk '{print $1}' | head -n1 || true)
if [ -z "$TUNNEL_ID" ]; then
  echo "❌ 创建失败，未获取到 Tunnel ID"
  exit 1
fi
echo "✅ Tunnel ID: $TUNNEL_ID"

# 2.3 写入 cloudflared 配置
cat > /root/.cloudflared/config.yml <<EOF
tunnel: $TUNNEL_ID
credentials-file: /root/.cloudflared/$TUNNEL_ID.json

ingress:
  - hostname: $DOMAIN
    service: http://localhost:$LOCAL_PORT
  - service: http_status:404
EOF

# 2.4 绑定 DNS
echo ""
echo "🌐 绑定域名到 Tunnel..."
cloudflared tunnel route dns "$TUNNEL_NAME" "$DOMAIN"

# 2.5 创建 systemd 服务（与原脚本一致）
echo ""
echo "⚙️ 创建并启动 cloudflared systemd 服务..."
cat >/etc/systemd/system/cloudflared.service <<EOF
[Unit]
Description=Cloudflare Tunnel Service ($TUNNEL_NAME)
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/cloudflared --no-autoupdate --config /root/.cloudflared/config.yml tunnel run
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

# ========== 3) 安装 & 配置 sing-box（VLESS+WS，本地监听；TLS 由 CF） ==========
echo ""
echo "---------------------------------------"
echo "📦 安装/检查 sing-box..."

if ! command -v sing-box >/dev/null 2>&1; then
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64) SB_ARCH="amd64" ;;
    aarch64|arm64) SB_ARCH="arm64" ;;
    *) echo "❌ 不支持的架构：$ARCH"; exit 1 ;;
  esac
  TMP_DIR=$(mktemp -d)
  cd "$TMP_DIR"
  LATEST=$(wget -qO- https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep tag_name | cut -d'"' -f4)
  if [[ -z "$LATEST" ]]; then
    echo "❌ 无法获取 sing-box 最新版本号"
    exit 1
  fi
  FILE="sing-box-${LATEST#v}-linux-${SB_ARCH}.tar.gz"
  wget -q "https://github.com/SagerNet/sing-box/releases/download/${LATEST}/${FILE}"
  tar -xzf "$FILE"
  install -m 0755 "sing-box-${LATEST#v}-linux-${SB_ARCH}/sing-box" /usr/local/bin/sing-box
  cd /
  rm -rf "$TMP_DIR"
else
  echo "✅ sing-box 已安装"
fi

mkdir -p /etc/sing-box
mkdir -p /var/log/sing-box
touch /var/log/sing-box/access.log /var/log/sing-box/error.log

# 写入 sing-box 配置：VLESS + WS（无本地 TLS）
cat >/etc/sing-box/config.json <<EOF
{
  "log": { "disabled": false, "level": "info", "timestamp": true },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-ws-in",
      "listen": "127.0.0.1",
      "listen_port": ${LOCAL_PORT},
      "users": [{ "uuid": "${USER_UUID}" }],
      "transport": {
        "type": "ws",
        "path": "${WS_PATH}",
        "headers": { "Host": "${DOMAIN}" }
      },
      "tls": { "enabled": false },
      "sniff": true,
      "udp_fragment": true
    }
  ],
  "outbounds": [{ "type": "direct" }]
}
EOF

# 写入 sing-box systemd
cat >/etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box service (VLESS+WS behind CF Tunnel)
After=network.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
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

# ========== 4) BBR（只在支持时启用，不支持静默跳过） ==========
echo ""
echo "---------------------------------------"
echo "🔍 检测内核是否支持 BBR..."
if [[ -f /proc/sys/net/ipv4/tcp_congestion_control ]]; then
  if sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1; then
    echo "✅ BBR 已启用"
  else
    echo "ℹ️ 当前环境不支持 BBR（可能是 OpenVZ/旧内核），已跳过"
  fi
else
  echo "ℹ️ 容器环境或内核裁剪，未发现 tcp_congestion_control，跳过 BBR"
fi

# ========== 5) 输出最终信息 ==========
# 生成 URL 编码 path
ENC_PATH_RAW="${WS_PATH}"
ENC_PATH=$(
  python3 - <<PY
import urllib.parse,sys
print(urllib.parse.quote(sys.argv[1]))
PY
"${ENC_PATH_RAW}" 2>/dev/null || echo "${WS_PATH}"
)

VLESS_URL="vless://${USER_UUID}@${DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&sni=${DOMAIN}&path=${ENC_PATH}#VLESS-WS-CF"

echo ""
echo "✅ 部署完成！"
echo "---------------------------------------"
echo "域名：${DOMAIN}"
echo "Tunnel 名称：${TUNNEL_NAME}"
echo "本地端口：${LOCAL_PORT}"
echo "WS 路径：${WS_PATH}"
echo "UUID：${USER_UUID}"
echo "cloudflared 配置：/root/.cloudflared/config.yml"
echo "sing-box 配置：/etc/sing-box/config.json"
echo "---------------------------------------"
echo "服务状态："
systemctl is-active --quiet cloudflared && echo " - cloudflared: running" || echo " - cloudflared: not running"
systemctl is-active --quiet sing-box && echo " - sing-box: running" || echo " - sing-box: not running"
echo "---------------------------------------"
echo "🔗 客户端一键链接："
echo "${VLESS_URL}"
echo "---------------------------------------"
echo "📌 如需查看 cloudflared 授权链接，请重跑登录：cloudflared tunnel login"
echo "📜 查看日志：journalctl -u cloudflared -f | journalctl -u sing-box -f"
