#!/usr/bin/env bash
# Komari Reverse Proxy Script (system repos only)
# Author: Komari
# Policy: NO third-party URLs/repos. Install Caddy ONLY via system package manager.
# Notes:
# - Supports Debian/Ubuntu (apt), RHEL/CentOS/Rocky/Alma/Fedora (dnf/yum),
#   Alpine (apk), Arch/Manjaro (pacman).
# - Minimal Caddyfile; WebSocket & X-Forwarded handled automatically by Caddy.
# - Robustness kept per request: ONLY port 80/443 occupancy check.

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# Defaults
DEFAULT_PORT=25774
LANG_CHOICE="en"
SVC_MGR="none"
OS=""; OS_VERSION=""

# i18n
declare -A MSG_EN=(
  ["welcome"]="Welcome to Komari Reverse Proxy Script"
  ["select_lang"]="Select language / 选择语言:"
  ["installing_deps"]="Installing dependencies..."
  ["detecting_os"]="Detecting operating system..."
  ["os_detected"]="Operating system detected:"
  ["installing_caddy"]="Installing Caddy from system repositories..."
  ["caddy_installed"]="Caddy installed successfully!"
  ["enter_domain"]="Please enter your domain name (e.g., sub.example.com):"
  ["enter_port"]="Please enter the port to reverse proxy (default: 25774):"
  ["invalid_domain"]="Invalid domain name format! Expect something like sub.example.com"
  ["invalid_port"]="Invalid port number! Please enter a number between 1-65535."
  ["config_caddy"]="Configuring Caddy..."
  ["starting_caddy"]="Starting Caddy service..."
  ["success"]="Configuration complete!"
  ["access_info"]="You can now access your service at:"
  ["service_status"]="Caddy service status:"
  ["error_occurred"]="An error occurred:"
  ["cleanup"]="Cleaning up..."
  ["caddy_already"]="Caddy is already installed. Reconfigure? (y/n):"
  ["exiting"]="Exiting..."
  ["yes"]="y"
  ["no"]="n"
  ["port_in_use"]="Port 80 or 443 is in use. Please free them and retry."
  ["config_location"]="Caddy configuration file location:"
  ["checking_config"]="Checking Caddy configuration..."
  ["config_valid"]="Configuration is valid!"
  ["reloading"]="Reloading Caddy..."
  ["reload_success"]="Caddy (re)started successfully!"
  ["pkg_missing"]="Caddy package not available in system repos; please enable official distro repo (e.g., Ubuntu 'universe', RHEL EPEL/AppStream) or install Caddy manually, then rerun."
)

declare -A MSG_ZH=(
  ["welcome"]="欢迎使用 Komari 反代脚本"
  ["select_lang"]="选择语言 / Select language:"
  ["installing_deps"]="正在安装依赖..."
  ["detecting_os"]="正在检测操作系统..."
  ["os_detected"]="检测到的操作系统："
  ["installing_caddy"]="正在通过系统仓库安装 Caddy..."
  ["caddy_installed"]="Caddy 安装成功！"
  ["enter_domain"]="请输入您的域名（例如：sub.example.com）："
  ["enter_port"]="请输入要反代的端口（默认：25774）："
  ["invalid_domain"]="域名格式无效！例如：sub.example.com"
  ["invalid_port"]="端口号无效！请输入 1-65535 之间的数字。"
  ["config_caddy"]="正在配置 Caddy..."
  ["starting_caddy"]="正在启动 Caddy 服务..."
  ["success"]="配置完成！"
  ["access_info"]="您现在可以通过以下地址访问您的服务："
  ["service_status"]="Caddy 服务状态："
  ["error_occurred"]="发生错误："
  ["cleanup"]="正在清理..."
  ["caddy_already"]="检测到已安装 Caddy。是否重新配置？(y/n)："
  ["exiting"]="正在退出..."
  ["yes"]="y"
  ["no"]="n"
  ["port_in_use"]="80 或 443 被占用，请释放后重试。"
  ["config_location"]="Caddy 配置文件位置："
  ["checking_config"]="正在检查 Caddy 配置..."
  ["config_valid"]="配置有效！"
  ["reloading"]="正在重载/启动 Caddy..."
  ["reload_success"]="Caddy 启动成功！"
  ["pkg_missing"]="系统仓库中未找到 Caddy 包；请启用发行版官方源（如 Ubuntu universe、RHEL 的 EPEL/AppStream）或手动安装 Caddy 后再运行本脚本。"
)

get_msg() { if [[ "$LANG_CHOICE" == "zh" ]]; then echo "${MSG_ZH[$1]}"; else echo "${MSG_EN[$1]}"; fi; }
print_msg() { local color=$1; shift; echo -e "${color}$(get_msg "$@")${NC}"; }
error_exit() { print_msg "$RED" "error_occurred"; echo -e "${RED}$*${NC}"; exit 1; }

# Detect OS
detect_os() {
  print_msg "$BLUE" "detecting_os"
  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    OS="${ID:-}"; OS_VERSION="${VERSION_ID:-}"
  elif command -v lsb_release >/dev/null 2>&1; then
    OS="$(lsb_release -si | tr '[:upper:]' '[:lower:]')"
    OS_VERSION="$(lsb_release -sr)"
  else
    error_exit "Cannot detect operating system!"
  fi
  print_msg "$GREEN" "os_detected"; echo "$OS $OS_VERSION"
}

# Detect service manager
detect_service_mgr() {
  if command -v systemctl >/dev/null 2>&1; then
    SVC_MGR="systemd"
  elif command -v rc-service >/dev/null 2>&1; then
    SVC_MGR="openrc"
  else
    SVC_MGR="none"
  fi
}

# Validators
validate_domain() {
  local domain=$1
  [[ "$domain" =~ ^([A-Za-z0-9-]+\.)+[A-Za-z]{2,}$ ]]
}
validate_port() { local p=$1; [[ "$p" =~ ^[0-9]+$ ]] && (( p>=1 && p<=65535 )); }

# Port occupancy check (only robustness we keep)
is_listening() {
  local port=$1
  if command -v ss >/dev/null 2>&1; then
    ss -ltn | awk -v p=":${port}$" '$4 ~ p {found=1} END{exit !found}'
  elif command -v netstat >/dev/null 2>&1; then
    netstat -ltn | awk -v p=":'"$port"'$" '$4 ~ p {found=1} END{exit !found}'
  else
    # If neither tool exists, assume free (best effort)
    return 1
  fi
}
port_free_or_die() {
  local busy=0
  if is_listening 80;  then busy=1; fi
  if is_listening 443; then busy=1; fi
  if [[ $busy -eq 1 ]]; then print_msg "$YELLOW" "port_in_use"; exit 1; fi
}

# Base deps (no third-party setup)
install_dependencies() {
  print_msg "$BLUE" "installing_deps"
  case "$OS" in
    ubuntu|debian)
      apt-get update
      apt-get install -y curl wget ca-certificates
      ;;
    centos|rhel|rocky|almalinux|fedora)
      (dnf install -y curl wget ca-certificates || yum install -y curl wget ca-certificates)
      ;;
    alpine)
      apk update
      apk add --no-cache curl wget ca-certificates
      ;;
    arch|manjaro)
      pacman -Sy --noconfirm curl wget ca-certificates
      ;;
    *) : ;;
  esac
}

# Install Caddy strictly via system repos
install_caddy() {
  print_msg "$BLUE" "installing_caddy"
  if command -v caddy >/dev/null 2>&1; then
    print_msg "$YELLOW" "caddy_already"; read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then print_msg "$BLUE" "exiting"; exit 0; fi
    return
  fi

  case "$OS" in
    ubuntu)
      # Ensure 'universe' (Caddy is in Ubuntu repo)
      if command -v add-apt-repository >/dev/null 2>&1; then
        add-apt-repository -y universe >/dev/null 2>&1 || true
      else
        apt-get install -y software-properties-common >/dev/null 2>&1 || true
        add-apt-repository -y universe >/dev/null 2>&1 || true
      fi
      apt-get update
      if ! apt-get install -y caddy; then
        error_exit "$(get_msg "pkg_missing")"
      fi
      ;;
    debian)
      apt-get update
      if ! apt-get install -y caddy; then
        error_exit "$(get_msg "pkg_missing")"
      fi
      ;;
    fedora)
      if ! dnf install -y caddy; then
        error_exit "$(get_msg "pkg_missing")"
      fi
      ;;
    centos|rhel|rocky|almalinux)
      # Try dnf first, fallback to yum; no external repos added.
      if command -v dnf >/dev/null 2>&1; then
        if ! dnf install -y caddy; then
          error_exit "$(get_msg "pkg_missing")"
        fi
      else
        if ! yum install -y caddy; then
          error_exit "$(get_msg "pkg_missing")"
        fi
      fi
      ;;
    alpine)
      # In Alpine community repo
      if ! apk add --no-cache caddy; then
        error_exit "$(get_msg "pkg_missing")"
      fi
      ;;
    arch|manjaro)
      if ! pacman -Sy --noconfirm caddy; then
        error_exit "$(get_msg "pkg_missing")"
      fi
      ;;
    *)
      error_exit "Unsupported/unknown OS for automatic install. Please install 'caddy' from your distro's official repos, then rerun."
      ;;
  esac

  print_msg "$GREEN" "caddy_installed"
}

# Generate minimal, correct Caddyfile (no manual headers)
generate_caddyfile() {
  local domain=$1 port=$2
  print_msg "$BLUE" "config_caddy"

  install -d -m 0755 /etc/caddy /var/log/caddy
  chown caddy:caddy /var/log/caddy >/dev/null 2>&1 || true

  cat > /etc/caddy/Caddyfile <<EOF
$domain {
    reverse_proxy http://127.0.0.1:$port
    encode gzip
    log {
        output file /var/log/caddy/access.log
        format json
    }
    tls {
        protocols tls1.2 tls1.3
    }
}
EOF
  print_msg "$GREEN" "config_location"; echo "/etc/caddy/Caddyfile"
}

# Start service per manager
start_caddy() {
  print_msg "$BLUE" "checking_config"
  caddy validate --config /etc/caddy/Caddyfile >/dev/null
  print_msg "$GREEN" "config_valid"

  print_msg "$BLUE" "reloading"
  case "$SVC_MGR" in
    systemd)
      systemctl enable caddy >/dev/null 2>&1 || true
      systemctl restart caddy
      ;;
    openrc)
      rc-update add caddy default >/dev/null 2>&1 || true
      rc-service caddy restart
      ;;
    none)
      echo "No service manager detected. Start manually:"
      echo "  caddy run --config /etc/caddy/Caddyfile --watch"
      ;;
  esac

  sleep 1
  print_msg "$GREEN" "reload_success"
  case "$SVC_MGR" in
    systemd) systemctl --no-pager -l status caddy | head -n 20 || true ;;
    openrc)  rc-service caddy status || true ;;
  esac
}

# Summary
show_summary() {
  local domain=$1 port=$2
  echo ""
  print_msg "$GREEN" "success"
  echo "=========================================="
  print_msg "$BLUE" "access_info"; echo -e "${GREEN}https://$domain${NC}"
  echo ""
  echo -e "${BLUE}Reverse Proxy:${NC} 127.0.0.1:$port  ->  https://$domain"
  echo -e "${BLUE}WebSocket:${NC} Auto (handled by Caddy)"
  echo -e "${BLUE}Config:${NC} /etc/caddy/Caddyfile"
  echo "=========================================="
}

main() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    error_exit "Please run this script as root (use sudo)."
  fi

  clear
  echo -e "${BLUE}"
  cat << "EOF"
    _  __                          _
   | |/ /___  _ __ ___   __ _ _ __(_)
   | ' // _ \| '_ ` _ \ / _` | '__| |
   | . \ (_) | | | | | | (_| | |  | |
   |_|\_\___/|_| |_| |_|\__,_|_|  |_|

        Reverse Proxy Script v1.3 (system repos only)
EOF
  echo -e "${NC}"

  echo -e "${YELLOW}$(get_msg "select_lang")${NC}"
  echo "1) English"
  echo "2) 中文"
  read -r -p "Choice/选择 [1]: " lang_choice
  case "${lang_choice:-1}" in 2) LANG_CHOICE="zh" ;; *) LANG_CHOICE="en" ;; esac

  print_msg "$GREEN" "welcome"; echo ""

  detect_os
  detect_service_mgr
  install_dependencies

  echo ""
  print_msg "$YELLOW" "enter_domain"; read -r domain
  domain="${domain//[[:space:]]/}"
  validate_domain "$domain" || error_exit "$(get_msg "invalid_domain")"

  print_msg "$YELLOW" "enter_port"; read -r port
  port="${port//[[:space:]]/}"
  if [[ -z "${port:-}" ]]; then port=$DEFAULT_PORT; fi
  validate_port "$port" || error_exit "$(get_msg "invalid_port")"

  # ONLY keep: port 80/443 occupancy check
  port_free_or_die

  install_caddy
  generate_caddyfile "$domain" "$port"
  start_caddy
  show_summary "$domain" "$port"
}

trap 'error_exit "Script interrupted"' INT TERM
main "$@"
