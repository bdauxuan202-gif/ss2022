#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "请使用 root 权限运行此脚本。"
  exit 1
fi


    if ! command -v "${cmd}" >/dev/null 2>&1; then
      missing+=("${cmd}")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "缺少组件: ${missing[*]}，请先安装。"
    exit 1
  fi


  if [[ $(uname -m) != "x86_64" ]]; then
    echo "当前系统架构为 $(uname -m)，此脚本仅支持 x86_64。"
    exit 1
  fi
}



  cat > /etc/sysctl.d/99-ss2022.conf <<'SYSCTL'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

  cat > /etc/security/limits.d/99-ss2022.conf <<'LIMITS'
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
LIMITS
}

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

ACTION="${1:-}"
if [[ -z "${ACTION}" ]]; then
  show_menu
  read -r -p "请输入选项 [1-4]: " ACTION
fi

case "${ACTION}" in
  1|install)
    preflight_check
    enable_bbr_and_optimize
    ;;
  2|update)
    update_script
    ;;
  3|uninstall)
    uninstall_all
    ;;
  4|exit)
    exit 0
    ;;
  *)
    echo "无效选项。"
    exit 1
    ;;
esac

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

if ! curl -fsSL "${XRAY_URL}" -o "${TMP_DIR}/xray.zip"; then
  echo "下载 Xray 失败，请检查网络连接或稍后重试。"
  rm -rf "${TMP_DIR}"
  exit 1
fi

if ! unzip -q "${TMP_DIR}/xray.zip" -d "${TMP_DIR}"; then
  echo "解压 Xray 失败，请确认 unzip 可用且下载文件完整。"
  rm -rf "${TMP_DIR}"
  exit 1
fi

if [[ ! -f "${TMP_DIR}/xray" ]]; then
  echo "未找到 Xray 二进制文件，可能下载了不匹配的架构版本。"
  rm -rf "${TMP_DIR}"
  exit 1
fi

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

SERVER_HOST_DEFAULT=$(curl -fsSL https://api.ipify.org || true)
if [[ -z "${SERVER_HOST_DEFAULT}" ]]; then
  SERVER_HOST_DEFAULT="your-server-ip"
fi
SERVER_HOST=$(prompt_default "请输入服务器 IP 或域名(用于生成分享链接)" "${SERVER_HOST_DEFAULT}")
SS_USERINFO=$(printf "%s:%s" "${METHOD}" "${PASSWORD}" | openssl base64 -A)
SS_LINK="ss://${SS_USERINFO}@${SERVER_HOST}:${PORT}#${NAME}"

echo ""
echo "SS2022 已配置完成："
echo "端口: ${PORT}"
echo "名称: ${NAME}"
echo "加密: ${METHOD}"
echo "密钥: ${PASSWORD}"
echo "分享链接: ${SS_LINK}"
