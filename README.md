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
安装完成后会输出可直接使用的 SS2022 分享链接。
脚本会尝试检测网卡速率并自动调整 BBR/系统参数。

更新脚本可执行：

```bash
sudo bash ss2022_xray.sh update
```

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

## 从 Git 下载到 VPS

如果仓库已托管在 GitHub/GitLab 等平台，可直接在 VPS 上执行：

```bash
git clone https://github.com/<your-username>/<your-repo>.git
cd <your-repo>
```

只想下载单个文件时，可以使用 `curl`：

```bash
curl -LO https://raw.githubusercontent.com/<your-username>/<your-repo>/main/ss2022_xray.sh
```

## Git 同步失败/提示重复的处理

当提示无法同步或“有重复/非快进”时，可以按下面方式处理：

```bash
git pull --rebase
```

如果本地历史与远端完全不同，先拉取再允许合并历史：

```bash
git pull --rebase --allow-unrelated-histories
```

仍无法同步时，建议新建目录重新克隆后再复制脚本文件：

```bash
git clone https://github.com/<your-username>/<your-repo>.git
```
