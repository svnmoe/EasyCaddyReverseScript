#!/bin/bash

# Komari Reverse Proxy Script
# Author: Komari
# Description: Auto install Caddy and setup reverse proxy with WebSocket support

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_PORT=25774
LANG_CHOICE="en"

# Language strings
declare -A MSG_EN=(
    ["welcome"]="Welcome to Komari Reverse Proxy Script"
    ["select_lang"]="Select language / 选择语言:"
    ["installing_deps"]="Installing dependencies..."
    ["detecting_os"]="Detecting operating system..."
    ["os_detected"]="Operating system detected:"
    ["installing_caddy"]="Installing Caddy..."
    ["caddy_installed"]="Caddy installed successfully!"
    ["enter_domain"]="Please enter your domain name (e.g., example.com):"
    ["enter_port"]="Please enter the port to reverse proxy (default: 25774):"
    ["invalid_domain"]="Invalid domain name format!"
    ["invalid_port"]="Invalid port number! Please enter a number between 1-65535."
    ["config_caddy"]="Configuring Caddy..."
    ["starting_caddy"]="Starting Caddy service..."
    ["success"]="Configuration complete!"
    ["access_info"]="You can now access your service at:"
    ["service_status"]="Caddy service status:"
    ["error_occurred"]="An error occurred:"
    ["cleanup"]="Cleaning up..."
    ["caddy_already"]="Caddy is already installed. Do you want to reconfigure? (y/n):"
    ["exiting"]="Exiting..."
    ["yes"]="y"
    ["no"]="n"
    ["port_in_use"]="Port 80 or 443 might be in use. Please check and try again."
    ["config_location"]="Caddy configuration file location:"
    ["checking_config"]="Checking Caddy configuration..."
    ["config_valid"]="Configuration is valid!"
    ["reloading"]="Reloading Caddy..."
    ["reload_success"]="Caddy reloaded successfully!"
)

declare -A MSG_ZH=(
    ["welcome"]="欢迎使用 Komari 反代脚本"
    ["select_lang"]="选择语言 / Select language:"
    ["installing_deps"]="正在安装依赖..."
    ["detecting_os"]="正在检测操作系统..."
    ["os_detected"]="检测到的操作系统："
    ["installing_caddy"]="正在安装 Caddy..."
    ["caddy_installed"]="Caddy 安装成功！"
    ["enter_domain"]="请输入您的域名（例如：example.com）："
    ["enter_port"]="请输入要反代的端口（默认：25774）："
    ["invalid_domain"]="域名格式无效！"
    ["invalid_port"]="端口号无效！请输入 1-65535 之间的数字。"
    ["config_caddy"]="正在配置 Caddy..."
    ["starting_caddy"]="正在启动 Caddy 服务..."
    ["success"]="配置完成！"
    ["access_info"]="您现在可以通过以下地址访问您的服务："
    ["service_status"]="Caddy 服务状态："
    ["error_occurred"]="发生错误："
    ["cleanup"]="正在清理..."
    ["caddy_already"]="Caddy 已经安装。是否要重新配置？(y/n)："
    ["exiting"]="正在退出..."
    ["yes"]="y"
    ["no"]="n"
    ["port_in_use"]="端口 80 或 443 可能被占用。请检查后重试。"
    ["config_location"]="Caddy 配置文件位置："
    ["checking_config"]="正在检查 Caddy 配置..."
    ["config_valid"]="配置有效！"
    ["reloading"]="正在重载 Caddy..."
    ["reload_success"]="Caddy 重载成功！"
)

# Function to get message based on language
get_msg() {
    if [ "$LANG_CHOICE" = "zh" ]; then
        echo "${MSG_ZH[$1]}"
    else
        echo "${MSG_EN[$1]}"
    fi
}

# Function to print colored message
print_msg() {
    color=$1
    shift
    echo -e "${color}$(get_msg "$@")${NC}"
}

# Function to print error and exit
error_exit() {
    print_msg "$RED" "error_occurred"
    echo -e "${RED}$1${NC}"
    exit 1
}

# Function to detect OS
detect_os() {
    print_msg "$BLUE" "detecting_os"
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
        OS_VERSION=$(lsb_release -sr)
    else
        error_exit "Cannot detect operating system!"
    fi
    
    print_msg "$GREEN" "os_detected" 
    echo "$OS $OS_VERSION"
}

# Function to install dependencies
install_dependencies() {
    print_msg "$BLUE" "installing_deps"
    
    case $OS in
        ubuntu|debian)
            apt-get update
            apt-get install -y curl wget sudo systemctl
            ;;
        centos|rhel|fedora|rocky|almalinux)
            yum install -y curl wget sudo systemctl || dnf install -y curl wget sudo systemctl
            ;;
        arch|manjaro)
            pacman -Syu --noconfirm curl wget sudo
            ;;
        alpine)
            apk update
            apk add curl wget sudo
            ;;
        *)
            error_exit "Unsupported operating system: $OS"
            ;;
    esac
}

# Function to install Caddy
install_caddy() {
    print_msg "$BLUE" "installing_caddy"
    
    # Check if Caddy is already installed
    if command -v caddy &> /dev/null; then
        print_msg "$YELLOW" "caddy_already"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_msg "$BLUE" "exiting"
            exit 0
        fi
    fi
    
    case $OS in
        ubuntu|debian)
            # Install from official Caddy repository
            apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
            apt-get update
            apt-get install -y caddy
            ;;
        centos|rhel|fedora|rocky|almalinux)
            # Install from COPR repository
            if command -v dnf &> /dev/null; then
                dnf install -y 'dnf-command(copr)'
                dnf copr enable -y @caddy/caddy
                dnf install -y caddy
            else
                yum install -y yum-plugin-copr
                yum copr enable -y @caddy/caddy
                yum install -y caddy
            fi
            ;;
        arch|manjaro)
            pacman -S --noconfirm caddy
            ;;
        alpine)
            apk add caddy
            ;;
        *)
            # Generic installation using official script
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/install.sh' | bash
            ;;
    esac
    
    print_msg "$GREEN" "caddy_installed"
}

# Function to validate domain
validate_domain() {
    local domain=$1
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi
    return 0
}

# Function to validate port
validate_port() {
    local port=$1
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi
    return 0
}

# Function to configure Caddy
configure_caddy() {
    local domain=$1
    local port=$2
    
    print_msg "$BLUE" "config_caddy"
    
    # Create Caddy configuration
    cat > /etc/caddy/Caddyfile << EOF
$domain {
    # Enable automatic HTTPS
    tls {
        protocols tls1.2 tls1.3
    }
    
    # Set up reverse proxy
    reverse_proxy localhost:$port {
        # WebSocket support
        header_up Host {host}
        header_up X-Real-IP {remote}
        header_up X-Forwarded-For {remote}
        header_up X-Forwarded-Proto {scheme}
        
        # WebSocket specific headers
        header_up Connection {>Connection}
        header_up Upgrade {>Upgrade}
    }
    
    # File upload size limit (100MB)
    request_body {
        max_size 100MB
    }
    
    # Encoding
    encode gzip
    
    # Logging
    log {
        output file /var/log/caddy/access.log
        format json
    }
}
EOF
    
    # Create log directory if it doesn't exist
    mkdir -p /var/log/caddy
    chown caddy:caddy /var/log/caddy
    
    print_msg "$GREEN" "config_location"
    echo "/etc/caddy/Caddyfile"
}

# Function to start and enable Caddy
start_caddy() {
    print_msg "$BLUE" "checking_config"
    
    # Test configuration
    if caddy validate --config /etc/caddy/Caddyfile &>/dev/null; then
        print_msg "$GREEN" "config_valid"
    else
        error_exit "Caddy configuration validation failed!"
    fi
    
    print_msg "$BLUE" "starting_caddy"
    
    # Enable and start Caddy service
    systemctl enable caddy &>/dev/null || true
    systemctl restart caddy
    
    # Check if service started successfully
    sleep 2
    if systemctl is-active --quiet caddy; then
        print_msg "$GREEN" "reload_success"
    else
        print_msg "$YELLOW" "port_in_use"
        systemctl status caddy --no-pager
        error_exit "Failed to start Caddy service"
    fi
}

# Function to show summary
show_summary() {
    local domain=$1
    local port=$2
    
    echo ""
    print_msg "$GREEN" "success"
    echo "=========================================="
    print_msg "$BLUE" "access_info"
    echo -e "${GREEN}https://$domain${NC}"
    echo ""
    echo -e "${BLUE}Reverse Proxy:${NC} localhost:$port -> https://$domain"
    echo -e "${BLUE}WebSocket:${NC} Enabled"
    echo -e "${BLUE}Max Upload Size:${NC} 100MB"
    echo ""
    print_msg "$BLUE" "service_status"
    systemctl status caddy --no-pager | head -n 5
    echo "=========================================="
}

# Main function
main() {
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        error_exit "Please run this script as root (use sudo)"
    fi
    
    clear
    
    # ASCII Art Banner
    echo -e "${BLUE}"
    cat << "EOF"
    _  __                          _ 
   | |/ /___  _ __ ___   __ _ _ __(_)
   | ' // _ \| '_ ` _ \ / _` | '__| |
   | . \ (_) | | | | | | (_| | |  | |
   |_|\_\___/|_| |_| |_|\__,_|_|  |_|
                                     
        Reverse Proxy Script v1.0
EOF
    echo -e "${NC}"
    
    # Language selection
    echo -e "${YELLOW}$(get_msg "select_lang")${NC}"
    echo "1) English"
    echo "2) 中文"
    read -r -p "Choice/选择 [1]: " lang_choice
    
    case $lang_choice in
        2)
            LANG_CHOICE="zh"
            ;;
        *)
            LANG_CHOICE="en"
            ;;
    esac
    
    print_msg "$GREEN" "welcome"
    echo ""
    
    # Detect OS
    detect_os
    
    # Install dependencies
    install_dependencies
    
    # Install Caddy
    install_caddy
    
    # Get domain name
    echo ""
    print_msg "$YELLOW" "enter_domain"
    read -r domain
    
    # Validate domain
    if ! validate_domain "$domain"; then
        error_exit "$(get_msg "invalid_domain")"
    fi
    
    # Get port
    print_msg "$YELLOW" "enter_port"
    read -r port
    
    # Use default port if empty
    if [ -z "$port" ]; then
        port=$DEFAULT_PORT
    fi
    
    # Validate port
    if ! validate_port "$port"; then
        error_exit "$(get_msg "invalid_port")"
    fi
    
    # Configure Caddy
    configure_caddy "$domain" "$port"
    
    # Start Caddy
    start_caddy
    
    # Show summary
    show_summary "$domain" "$port"
}

# Trap errors
trap 'error_exit "Script interrupted"' INT TERM

# Run main function
main "$@"