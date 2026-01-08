# ss2022

Xray 内核下的 Shadowsocks 2022 一键安装脚本。

## 同步到 GitHub

```bash
git init
git add .
git commit -m "Add ss2022 xray script"
git branch -M main
git remote add origin https://github.com/<your-username>/<your-repo>.git
git push -u origin main
```

已有远程仓库时，可直接执行：

```bash
git add .
git commit -m "Update ss2022 xray script"
git push
```

## 使用方式

```bash
sudo bash ss2022_xray.sh
```

脚本会提示自定义端口、名称、加密方式与密钥，并自动生成 Xray 配置与 systemd 服务。

## 在 VPS 上使用

1. 连接到 VPS：

```bash
ssh root@<your-vps-ip>
```

2. 安装依赖并运行脚本：

```bash
apt update && apt install -y curl unzip openssl
chmod +x ss2022_xray.sh
sudo bash ss2022_xray.sh
```

3. 查看服务状态：

```bash
systemctl status xray
```
