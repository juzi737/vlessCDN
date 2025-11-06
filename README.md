✅ 被墙vps或者NAT小鸡套cdn

在服务器上执行以下命令：
```bash
wget https://raw.githubusercontent.com/juzi737/vlessCDN/main/vlessCDN.sh
chmod +x vlessCDN.sh
sudo ./vlessCDN.sh
```

✅ 常规vps套cdn

在服务器上执行以下命令：
```bash
wget https://raw.githubusercontent.com/juzi737/vlessCDN/main/nogwfipvless.sh
chmod +x nogwfipvless.sh
sudo ./nogwfipvless.sh
```

🔄 一键更新 Sing-box UUID

执行下面命令即可 自动生成新 UUID、更新配置并重启 Sing-box：
```bash
NEW_UUID=$(cat /proc/sys/kernel/random/uuid) && sudo sed -i "s/\"uuid\": \".*\"/\"uuid\": \"$NEW_UUID\"/" /etc/sing-box/config.json && sudo systemctl restart sing-box && echo -e "\n✅ UUID 已更新成功！\n🔑 新的 UUID：$NEW_UUID\n"
```

该命令会自动：生成随机 UUID

替换 /etc/sing-box/config.json 中的旧 UUID

重启 Sing-box 服务

打印新的 UUID 供客户端使用

⚙️ 功能简介

🧩 一键安装 Sing-box + VLESS + WS + TLS

⚡ 自动生成 SSL 证书（支持 ACME）

☁️ 可选 Cloudflare CDN 加速

🔒 支持多用户 / 多端口

🧠 自动检测依赖与系统环境

🧠 常见问题
❓重新安装

可以直接再次执行安装命令，脚本会自动检测并覆盖旧配置。

❓配置文件位置

默认路径：

/etc/sing-box/config.json

❓查看运行状态
sudo systemctl status sing-box

🌟 项目信息

🏠 GitHub 项目地址： juzi737/vlessCDN

🧑‍💻 作者：juzi737

📜 License: MIT

❤️ 特别感谢

Xray-core

Sing-box

💬 小贴士

建议使用最新系统环境执行脚本

如果使用 Cloudflare，请先在 DNS 面板中添加你的域名解析

可在执行前查看脚本源码确保安全性：
```bash
curl -Ls https://raw.githubusercontent.com/juzi737/vlessCDN/main/vlessCDN.sh | less
```

⭐ 如果这个项目对你有帮助，请在 GitHub
 上点个 Star 支持！
