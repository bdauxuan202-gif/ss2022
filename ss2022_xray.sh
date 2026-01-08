#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "请使用 root 权限运行此脚本。"
  exit 1
fi

command -v curl >/dev/null 2>&1 || { echo "缺少 curl，请先安装。"; exit 1; }
command -v unzip >/dev/null 2>&1 || { echo "缺少 unzip，请先安装。"; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "缺少 openssl，请先安装。"; exit 1; }

prompt_default() {
  local prompt="$1"
  local default="$2"
  local input
  read -r -p "${prompt} [${default}]: " input
  if [[ -z "${input}" ]]; then
    echo "${default}"
  else
    echo "${input}"
  fi
}

PORT=$(prompt_default "请输入监听端口" "4433")
NAME=$(prompt_default "请输入配置名称(用于标识)" "ss2022")

echo "请选择加密方式："
select METHOD in "2022-blake3-aes-256-gcm" "2022-blake3-aes-128-gcm"; do
  if [[ -n "${METHOD}" ]]; then
    break
  fi
  echo "无效选择，请重试。"
done

KEY_HINT=""
KEY_SIZE=32
if [[ "${METHOD}" == "2022-blake3-aes-128-gcm" ]]; then
  KEY_SIZE=16
fi
KEY_HINT="建议使用 base64 编码的 ${KEY_SIZE} 字节密钥。"

echo "请输入密钥（留空则自动生成）。${KEY_HINT}"
read -r -p "密钥: " PASSWORD
if [[ -z "${PASSWORD}" ]]; then
  PASSWORD=$(openssl rand -base64 "${KEY_SIZE}")
  echo "已生成密钥: ${PASSWORD}"
fi

XRAY_VERSION="latest"
XRAY_URL="https://github.com/XTLS/Xray-core/releases/${XRAY_VERSION}/download/Xray-linux-64.zip"
TMP_DIR=$(mktemp -d)

curl -fsSL "${XRAY_URL}" -o "${TMP_DIR}/xray.zip"
unzip -q "${TMP_DIR}/xray.zip" -d "${TMP_DIR}"

install -m 755 "${TMP_DIR}/xray" /usr/local/bin/xray
install -d /usr/local/share/xray
if [[ -f "${TMP_DIR}/geoip.dat" ]]; then
  install -m 644 "${TMP_DIR}/geoip.dat" /usr/local/share/xray/geoip.dat
fi
if [[ -f "${TMP_DIR}/geosite.dat" ]]; then
  install -m 644 "${TMP_DIR}/geosite.dat" /usr/local/share/xray/geosite.dat
fi

install -d /etc/xray
cat > /etc/xray/config.json <<CONFIG
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "${NAME}",
      "port": ${PORT},
      "protocol": "shadowsocks",
      "settings": {
        "method": "${METHOD}",
        "password": "${PASSWORD}",
        "network": "tcp,udp"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
CONFIG

cat > /etc/systemd/system/xray.service <<'SERVICE'
[Unit]
Description=Xray Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable xray
systemctl restart xray

rm -rf "${TMP_DIR}"

echo ""
echo "SS2022 已配置完成："
echo "端口: ${PORT}"
echo "名称: ${NAME}"
echo "加密: ${METHOD}"
echo "密钥: ${PASSWORD}"
