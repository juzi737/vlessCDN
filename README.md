✅ 方法一：使用 wget 下载（推荐）

在服务器上执行以下命令：
```bash
wget https://raw.githubusercontent.com/juzi737/vlessCDN/main/vlessCDN.sh
```

赋予执行权限：
```bash
chmod +x vlessCDN.sh


运行脚本：
```bash
sudo ./vlessCDN.sh


✅ 这是最常用、最稳定的方式。下载的就是原始 .sh 文件，无多余内容。

🌀 方法二：使用 curl 下载

如果系统没有 wget，可以用 curl：

curl -O https://raw.githubusercontent.com/juzi737/vlessCDN/main/vlessCDN.sh


赋予执行权限：

chmod +x vlessCDN.sh


执行脚本：

sudo ./vlessCDN.sh

🔄 一键更新 Sing-box UUID

执行下面命令即可 自动生成新 UUID、更新配置并重启 Sing-box：

NEW_UUID=$(cat /proc/sys/kernel/random/uuid) && sudo sed -i "s/\"uuid\": \".*\"/\"uuid\": \"$NEW_UUID\"/" /etc/sing-box/config.json && sudo systemctl restart sing-box && echo -e "\n✅ UUID 已更新成功！\n🔑 新的 UUID：$NEW_UUID\n"


该命令会自动：

生成随机 UUID

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

curl -Ls https://raw.githubusercontent.com/juzi737/vlessCDN/main/vlessCDN.sh | less


⭐ 如果这个项目对你有帮助，请在 GitHub
 上点个 Star 支持！
