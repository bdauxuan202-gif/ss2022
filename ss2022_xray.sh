#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "请使用 root 权限运行此脚本。"
  exit 1
fi

show_menu() {
  echo "SS2022 Xray 脚本"
  echo "1) 安装"
  echo "2) 更新脚本"
  echo "3) 卸载"
  echo "4) 退出"
}

preflight_check() {
  local required=(curl unzip openssl ip)
  local missing=()
  local cmd
  local pkg_manager

  for cmd in "${required[@]}"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      missing+=("${cmd}")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    if command -v apt-get >/dev/null 2>&1; then
      pkg_manager="apt-get"
    elif command -v dnf >/dev/null 2>&1; then
      pkg_manager="dnf"
    elif command -v yum >/dev/null 2>&1; then
      pkg_manager="yum"
    else
      echo "缺少组件: ${missing[*]}，且未检测到包管理器，请先安装。"
      exit 1
    fi

    echo "缺少组件: ${missing[*]}，尝试自动安装..."
    case "${pkg_manager}" in
      apt-get)
        apt-get update -y
        apt-get install -y "${missing[@]}"
        ;;
      dnf)
        dnf install -y "${missing[@]}"
        ;;
      yum)
        yum install -y "${missing[@]}"
        ;;
    esac
  fi

  if [[ $(uname -m) != "x86_64" ]]; then
    echo "当前系统架构为 $(uname -m)，此脚本仅支持 x86_64。"
    exit 1
  fi
}

detect_primary_iface() {
  local iface
  iface=$(ip route show default 2>/dev/null | awk 'NR==1 {print $5}')
  if [[ -n "${iface}" ]]; then
    echo "${iface}"
    return
  fi
  iface=$(ip -o link show | awk -F': ' '{print $2}' | awk '$1 != "lo" {print $1; exit}')
  echo "${iface}"
}

detect_link_speed_mbps() {
  local iface="$1"
  local speed=""
  if [[ -n "${iface}" && -f "/sys/class/net/${iface}/speed" ]]; then
    speed=$(cat "/sys/class/net/${iface}/speed" 2>/dev/null || true)
  fi
  if [[ -z "${speed}" && -n "${iface}" && $(command -v ethtool >/dev/null 2>&1; echo $?) -eq 0 ]]; then
    speed=$(ethtool "${iface}" 2>/dev/null | awk -F': ' '/Speed:/ {print $2}' | sed 's/Mb\/s//')
  fi
  if [[ -z "${speed}" || ! "${speed}" =~ ^[0-9]+$ ]]; then
    echo "1000"
  else
    echo "${speed}"
  fi
}

enable_bbr_and_optimize() {
  local iface
  local speed_mbps
  local cpu_cores
  local rmem_max
  local wmem_max
  local tcp_rmem_max
  local tcp_wmem_max
  local backlog_base
  local somaxconn
  local backlog

  iface=$(detect_primary_iface)
  speed_mbps=$(detect_link_speed_mbps "${iface}")
  cpu_cores=$(nproc)

  if (( speed_mbps <= 100 )); then
    rmem_max=$((16 * 1024 * 1024))
    wmem_max=$((16 * 1024 * 1024))
    tcp_rmem_max=$((16 * 1024 * 1024))
    tcp_wmem_max=$((16 * 1024 * 1024))
    backlog_base=4096
    somaxconn=1024
  elif (( speed_mbps <= 1000 )); then
    rmem_max=$((64 * 1024 * 1024))
    wmem_max=$((64 * 1024 * 1024))
    tcp_rmem_max=$((64 * 1024 * 1024))
    tcp_wmem_max=$((64 * 1024 * 1024))
    backlog_base=8192
    somaxconn=4096
  else
    rmem_max=$((256 * 1024 * 1024))
    wmem_max=$((256 * 1024 * 1024))
    tcp_rmem_max=$((256 * 1024 * 1024))
    tcp_wmem_max=$((256 * 1024 * 1024))
    backlog_base=16384
    somaxconn=8192
  fi

  backlog=$((backlog_base * cpu_cores))
  if (( backlog > 262144 )); then
    backlog=262144
  fi

  cat > /etc/sysctl.d/99-ss2022.conf <<SYSCTL
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=${rmem_max}
net.core.wmem_max=${wmem_max}
net.ipv4.tcp_rmem=4096 87380 ${tcp_rmem_max}
net.ipv4.tcp_wmem=4096 65536 ${tcp_wmem_max}
net.core.netdev_max_backlog=${backlog}
net.core.somaxconn=${somaxconn}
net.ipv4.tcp_max_syn_backlog=$((somaxconn * 2))
net.ipv4.tcp_mtu_probing=1
fs.file-max=1048576
SYSCTL

  cat > /etc/security/limits.d/99-ss2022.conf <<'LIMITS'
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
LIMITS

  sysctl --system >/dev/null 2>&1 || true
  echo "已根据网卡(${iface:-未知}) ${speed_mbps}Mbps 与 CPU 核心数 ${cpu_cores} 自动优化 BBR/系统参数。"
}

install_xray() {
  if command -v xray >/dev/null 2>&1; then
    echo "已检测到 Xray，可跳过下载。"
    return
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

  rm -rf "${TMP_DIR}"
}

update_script() {
  echo "请手动从仓库更新脚本。"
}

uninstall_all() {
  systemctl disable --now xray >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/xray.service
  rm -f /etc/xray/config.json
  rm -rf /etc/xray
  rm -f /usr/local/bin/xray
  rm -f /etc/sysctl.d/99-ss2022.conf
  rm -f /etc/security/limits.d/99-ss2022.conf
  sysctl --system >/dev/null 2>&1 || true
  echo "已卸载 Xray 与相关配置。"
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
    exit 0
    ;;
  3|uninstall)
    uninstall_all
    exit 0
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

install_xray

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
