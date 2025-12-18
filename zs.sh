#!/usr/bin/env bash
set -e

echo "======================================"
echo " ACME.SH SSL 证书申请脚本"
echo " 自动随机邮箱 + 交互输入域名"
echo "======================================"

# ===== 强制交互输入域名 =====
read -rp "请输入你的域名（如 example.com）: " DOMAIN </dev/tty

if [[ -z "$DOMAIN" ]]; then
  echo "❌ 域名不能为空"
  exit 1
fi

# ===== 随机生成邮箱 =====
RAND=$(tr -dc a-z0-9 </dev/urandom | head -c 8)
EMAIL="${RAND}@gmail.com"

echo ""
echo "🌐 域名: $DOMAIN"
echo "📧 邮箱: $EMAIL"
echo ""

sleep 1

# ===== 安装依赖 =====
if command -v apt >/dev/null 2>&1; then
  apt update -y
  apt install -y curl socat cron
elif command -v yum >/dev/null 2>&1; then
  yum install -y curl socat cronie
else
  echo "❌ 不支持的系统"
  exit 1
fi

# ===== 安装 acme.sh =====
if [ ! -d "$HOME/.acme.sh" ]; then
  echo "📥 安装 acme.sh..."
  curl -s https://get.acme.sh | sh -s email="$EMAIL"
fi

ACME="$HOME/.acme.sh/acme.sh"

# ===== 设置默认 CA =====
$ACME --set-default-ca --server letsencrypt

# ===== 申请证书 =====
echo "🚀 开始申请证书..."
$ACME --issue \
  -d "$DOMAIN" \
  --standalone \
  --keylength ec-256

# ===== 安装证书 =====
CERT_DIR="/etc/ssl/$DOMAIN"
mkdir -p "$CERT_DIR"

CERT_FILE="$CERT_DIR/cert.pem"
KEY_FILE="$CERT_DIR/key.pem"

$ACME --install-cert -d "$DOMAIN" \
  --ecc \
  --fullchain-file "$CERT_FILE" \
  --key-file "$KEY_FILE"

# ===== 最终输出 =====
echo ""
echo "======================================"
echo "✅ 证书申请并安装完成"
echo "--------------------------------------"
echo "📜 证书文件路径:"
echo "  $CERT_FILE"
echo ""
echo "🔐 私钥文件路径:"
echo "  $KEY_FILE"
echo "======================================"
