#!/bin/bash
# ==============================================
# Sing-box VLESS+WS+TLS 一键部署脚本
# 作者: Yangzi 优化版
# 适配: Debian / Ubuntu / CentOS 全版本
# ==============================================

set -e

echo -e "\033[1;32m========== Sing-box VLESS+WS+TLS 一键安装 ==========\033[0m"

# 1️⃣ 环境检测
if ! command -v curl >/dev/null; then
  echo "正在安装 curl..."
  apt update -y && apt install curl -y
fi

if ! command -v socat >/dev/null; then
  echo "正在安装 acme 依赖..."
  apt install -y socat
fi

# 2️⃣ 交互输入
read -p "请输入你的域名（已解析到本机IP）: " domain
read -p "请输入 UUID（留空自动生成）: " uuid
read -p "请输入 WebSocket 路径（默认 /cdn）: " path

[ -z "$uuid" ] && uuid=$(cat /proc/sys/kernel/random/uuid)
[ -z "$path" ] && path="/cdn"

echo -e "\n配置如下："
echo -e "域名: $domain"
echo -e "UUID: $uuid"
echo -e "路径: $path"
sleep 1

# 3️⃣ 关闭可能占用 80/443 的程序
echo -e "\n检查端口占用..."
for port in 80 443; do
  pid=$(lsof -t -i:$port || true)
  if [ -n "$pid" ]; then
    echo "检测到端口 $port 被占用，尝试释放..."
    systemctl stop nginx 2>/dev/null || true
    systemctl stop apache2 2>/dev/null || true
    kill -9 $pid 2>/dev/null || true
  fi
done

# 4️⃣ 安装 acme.sh 签发 ECC 证书
echo -e "\n正在签发 SSL 证书..."
curl https://get.acme.sh | sh
source ~/.bashrc
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
~/.acme.sh/acme.sh --issue -d $domain --standalone --keylength ec-256 --force
mkdir -p /etc/ssl/private /etc/ssl/certs
~/.acme.sh/acme.sh --install-cert -d $domain --ecc \
  --key-file /etc/ssl/private/${domain}.key \
  --fullchain-file /etc/ssl/certs/${domain}.crt

# 5️⃣ 安装 sing-box 最新稳定版（自动适配系统）
echo -e "\n安装 sing-box..."
bash <(curl -fsSL https://sing-box.app/install.sh)

# 6️⃣ 生成配置文件
cat > /etc/sing-box/config.json <<EOF
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "vless",
      "listen": "::",
      "listen_port": 443,
      "users": [
        {
          "uuid": "$uuid"
        }
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "/etc/ssl/certs/${domain}.crt",
        "key_path": "/etc/ssl/private/${domain}.key",
        "alpn": ["http/1.1"]
      },
      "transport": {
        "type": "ws",
        "path": "$path",
        "headers": {
          "Host": "$domain"
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF

# 7️⃣ 网络优化（BBR + FastOpen）
echo -e "\n启用网络优化..."
sysctl -w net.core.default_qdisc=fq
sysctl -w net.ipv4.tcp_congestion_control=bbr
sysctl -w net.ipv4.tcp_fastopen=3

if ! grep -q "tcp_bbr" /etc/modules-load.d/modules.conf 2>/dev/null; then
  echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
fi

# 8️⃣ 启动并设置开机自启
echo -e "\n启动 sing-box..."
systemctl enable sing-box
systemctl restart sing-box

sleep 2
if systemctl is-active --quiet sing-box; then
  echo -e "\033[1;32mSing-box 已成功运行！\033[0m"
else
  echo -e "\033[1;31mSing-box 启动失败，请检查配置！\033[0m"
  journalctl -u sing-box -n 20
  exit 1
fi

# 9️⃣ 输出节点信息
echo -e "\n========== 节点信息 =========="
echo "协议: VLESS"
echo "地址: $domain"
echo "端口: 443"
echo "UUID: $uuid"
echo "传输: ws"
echo "路径: $path"
echo "加密: none"
echo "SNI: $domain"
echo "ALPN: http/1.1"
echo "TLS: 启用"
echo "============================="

# 10️⃣ 输出 VLESS 链接
link="vless://${uuid}@${domain}:443?encryption=none&security=tls&sni=${domain}&alpn=http/1.1&type=ws&host=${domain}&path=${path}#${domain}-WS-TLS"
echo -e "\n✅ 你的 VLESS 节点链接："
echo "$link"
echo -e "\n已全部完成！请将此链接导入 v2rayN / Clash.Meta 使用。"
