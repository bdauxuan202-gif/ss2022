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

## 使用 curl 一键脚本

如果你想通过类似 `bash <(curl -Ls ...)` 的方式运行脚本，可以按照以下步骤实现：

1. 将脚本上传到 GitHub，并确保文件可通过 raw 地址访问，例如：

```
https://raw.githubusercontent.com/<your-username>/<your-repo>/main/ss2022_xray.sh
```

2. 在 VPS 上执行：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/<your-username>/<your-repo>/main/ss2022_xray.sh)
```

这种方式会直接下载并执行脚本，适合临时部署或快速测试场景。
