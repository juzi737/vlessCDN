#!/usr/bin/env bash
set -e

echo "========================================"
echo " HTTPS 反代 & 证书 一键脚本"
echo " 支持：CentOS / COS / Ubuntu / Debian"
echo "========================================"

# =========================
# 0. Root 检测
# =========================
if [ "$EUID" -ne 0 ]; then
  echo "❌ 请使用 root 用户运行"
  exit 1
fi

# =========================
# 1. 系统识别
# =========================
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$ID
else
  echo "❌ 无法识别系统"
  exit 1
fi

if [[ "$OS" =~ (centos|almalinux|rocky|rhel|cos) ]]; then
  PM_UPDATE="yum makecache"
  PM_INSTALL="yum install -y"
  CRON_SERVICE="crond"
elif [[ "$OS" =~ (ubuntu|debian) ]]; then
  PM_UPDATE="apt update"
  PM_INSTALL="apt install -y"
  CRON_SERVICE="cron"
else
  echo "❌ 不支持的系统：$OS"
  exit 1
fi

echo "▶ 系统识别：$OS"

# =========================
# 2. 安装依赖
# =========================
echo "▶ 安装依赖..."
$PM_UPDATE
$PM_INSTALL nginx curl socat cron || $PM_INSTALL nginx curl socat cronie

systemctl enable nginx --now
systemctl enable $CRON_SERVICE --now

# =========================
# 3. 交互输入反代规则
# =========================
echo
echo "请输入反代规则（格式：域名 端口）"
echo "示例：ix.ssr.baby 7788"
echo "多行输入，直接回车空行结束"
echo

DOMAINS=()
PORTS=()

while true; do
  read -rp "> " line
  [ -z "$line" ] && break

  domain=$(echo "$line" | awk '{print $1}')
  port=$(echo "$line" | awk '{print $2}')

  if [[ -z "$domain" || -z "$port" ]]; then
    echo "⚠️ 格式错误，已跳过"
    continue
  fi

  DOMAINS+=("$domain")
  PORTS+=("$port")
done

if [ ${#DOMAINS[@]} -eq 0 ]; then
  echo "❌ 未输入任何反代规则，退出"
  exit 1
fi

# =========================
# 4. 安装 acme.sh
# =========================
if [ ! -d "$HOME/.acme.sh" ]; then
  echo "▶ 安装 acme.sh"
  curl https://get.acme.sh | sh
fi

source "$HOME/.bashrc"

# =========================
# 5. 随机邮箱
# =========================
BASE_DOMAIN=$(echo "${DOMAINS[0]}" | awk -F. '{print $(NF-1)"."$NF}')
EMAIL="ssl-$(date +%s)$((RANDOM%10000))@$BASE_DOMAIN"

echo "▶ ACME 邮箱：$EMAIL"

~/.acme.sh/acme.sh --register-account -m "$EMAIL"

# =========================
# 6. 申请证书
# =========================
mkdir -p /var/www/html

for domain in "${DOMAINS[@]}"; do
  echo "▶ 申请证书：$domain"
  ~/.acme.sh/acme.sh --issue -d "$domain" --webroot /var/www/html
done

# =========================
# 7. Nginx 配置
# =========================
for i in "${!DOMAINS[@]}"; do
  domain="${DOMAINS[$i]}"
  port="${PORTS[$i]}"
  SSL_DIR="/etc/nginx/ssl/$domain"

  mkdir -p "$SSL_DIR"

  ~/.acme.sh/acme.sh --install-cert -d "$domain" \
    --key-file       "$SSL_DIR/privkey.pem" \
    --fullchain-file "$SSL_DIR/fullchain.pem" \
    --reloadcmd "systemctl reload nginx"

  cat >/etc/nginx/conf.d/$domain.conf <<EOF
server {
    listen 80;
    server_name $domain;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $domain;

    ssl_certificate     $SSL_DIR/fullchain.pem;
    ssl_certificate_key $SSL_DIR/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_pass http://127.0.0.1:$port;
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
    }
}
EOF
done

# =========================
# 8. 生效
# =========================
nginx -t
systemctl reload nginx

echo
echo "========================================"
echo "✅ 部署完成"
echo "📧 ACME 邮箱：$EMAIL"
echo "📂 证书目录：/etc/nginx/ssl/"
echo "========================================"
