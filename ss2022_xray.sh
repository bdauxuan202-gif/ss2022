#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "请使用 root 权限运行此脚本。"
  exit 1
fi

show_menu() {
  echo "请选择操作："
  echo "1) 安装/配置 SS2022"
  echo "2) 更新脚本"
  echo "3) 一键卸载"
  echo "4) 退出"
}

check_commands() {
  local missing=()
  local cmd

  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      missing+=("${cmd}")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "缺少组件: ${missing[*]}，请先安装。"
    exit 1
  fi
}

preflight_check() {
  check_commands curl unzip openssl systemctl sysctl ip

  if [[ $(uname -m) != "x86_64" ]]; then
    echo "当前系统架构为 $(uname -m)，此脚本仅支持 x86_64。"
    exit 1
  fi
}

update_script() {
  local default_url="https://raw.githubusercontent.com/<your-username>/<your-repo>/main/ss2022_xray.sh"
  local script_url
  local tmp_script

  check_commands curl
  script_url=$(prompt_default "请输入更新脚本的地址" "${default_url}")
  tmp_script=$(mktemp)

  if ! curl -fsSL "${script_url}" -o "${tmp_script}"; then
    echo "下载更新脚本失败，请检查地址或网络。"
    rm -f "${tmp_script}"
    exit 1
  fi

  if ! head -n 1 "${tmp_script}" | grep -q "bash"; then
    echo "下载内容不是脚本，已取消更新。"
    rm -f "${tmp_script}"
    exit 1
  fi

  install -m 755 "${tmp_script}" "$0"
  rm -f "${tmp_script}"
  echo "脚本已更新，请重新运行。"
  exit 0
}

uninstall_all() {
  echo "正在卸载 SS2022/Xray..."

  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop xray >/dev/null 2>&1 || true
    systemctl disable xray >/dev/null 2>&1 || true
  fi

  rm -f /etc/systemd/system/xray.service
  rm -rf /etc/xray
  rm -f /usr/local/bin/xray
  rm -rf /usr/local/share/xray
  rm -f /etc/sysctl.d/99-ss2022.conf
  rm -f /etc/security/limits.d/99-ss2022.conf

  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi

  echo "卸载完成。"
  exit 0
}

get_default_iface() {
  ip route show default 2>/dev/null | awk '{print $5; exit}'
}

get_link_speed_mbps() {
  local iface="$1"
  local speed_path="/sys/class/net/${iface}/speed"
  if [[ -n "${iface}" && -r "${speed_path}" ]]; then
    cat "${speed_path}"
  else
    echo ""
  fi
}

enable_bbr_and_optimize() {
  echo "正在开启 BBR+FQ 并进行系统优化..."

  local iface
  local link_speed
  local rmem_max
  local wmem_max
  local tcp_rmem
  local tcp_wmem
  local file_max

  iface=$(get_default_iface)
  link_speed=$(get_link_speed_mbps "${iface}")

  if [[ "${link_speed}" =~ ^[0-9]+$ ]]; then
    if (( link_speed <= 100 )); then
      rmem_max=16777216
      wmem_max=16777216
      tcp_rmem="4096 87380 16777216"
      tcp_wmem="4096 65536 16777216"
      file_max=262144
    elif (( link_speed <= 1000 )); then
      rmem_max=33554432
      wmem_max=33554432
      tcp_rmem="4096 87380 33554432"
      tcp_wmem="4096 65536 33554432"
      file_max=524288
    else
      rmem_max=67108864
      wmem_max=67108864
      tcp_rmem="4096 87380 67108864"
      tcp_wmem="4096 65536 67108864"
      file_max=1048576
    fi
    echo "检测到网卡 ${iface:-unknown} 速率 ${link_speed}Mbps，已按带宽自动优化。"
  else
    rmem_max=67108864
    wmem_max=67108864
    tcp_rmem="4096 87380 67108864"
    tcp_wmem="4096 65536 67108864"
    file_max=1048576
    echo "未检测到带宽速率，使用默认优化参数。"
  fi

  cat > /etc/sysctl.d/99-ss2022.conf <<'SYSCTL'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_syncookies=1
SYSCTL

  {
    echo "net.core.rmem_max=${rmem_max}"
    echo "net.core.wmem_max=${wmem_max}"
    echo "net.ipv4.tcp_rmem=${tcp_rmem}"
    echo "net.ipv4.tcp_wmem=${tcp_wmem}"
    echo "fs.file-max=${file_max}"
  } >> /etc/sysctl.d/99-ss2022.conf

  sysctl --system >/dev/null

  if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q "bbr"; then
    echo "BBR 已启用。"
  else
    echo "BBR 未启用，请检查内核是否支持。"
  fi

  if sysctl net.core.default_qdisc 2>/dev/null | grep -q "fq"; then
    echo "FQ 已启用。"
  else
    echo "FQ 未启用，请检查内核是否支持。"
  fi

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
