#!/bin/bash

# SpicyfyLLM - Domain Access Setup for Ollama
# Configure custom domain access to Ollama service
#
# Author: SpicyfyLLM Team
# License: MIT

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

# Get current public IP
get_public_ip() {
    local public_ip=""
    
    # Try multiple services to get public IP
    public_ip=$(curl -s https://ipv4.icanhazip.com/ 2>/dev/null || \
                curl -s https://api.ipify.org 2>/dev/null || \
                curl -s https://checkip.amazonaws.com 2>/dev/null || \
                dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null)
    
    echo "$public_ip"
}

# Check DNS configuration
check_dns() {
    local domain="$1"
    print_step "Checking DNS configuration for $domain..."
    
    local resolved_ip=$(dig +short "$domain" 2>/dev/null | tail -1)
    local public_ip=$(get_public_ip)
    
    if [[ -n "$resolved_ip" && -n "$public_ip" ]]; then
        if [[ "$resolved_ip" == "$public_ip" ]]; then
            print_success "✅ DNS correctly points to your public IP: $public_ip"
            return 0
        else
            print_warning "⚠️  DNS points to $resolved_ip but your public IP is $public_ip"
            return 1
        fi
    else
        print_error "❌ Could not resolve DNS or determine public IP"
        return 1
    fi
}

# Check port accessibility
check_port_access() {
    local domain="$1"
    local port="$2"
    
    print_step "Testing port $port accessibility on $domain..."
    
    if timeout 10 bash -c "</dev/tcp/$domain/$port" 2>/dev/null; then
        print_success "✅ Port $port is accessible on $domain"
        return 0
    else
        print_warning "❌ Port $port is not accessible on $domain"
        return 1
    fi
}

# Setup router port forwarding guide
show_port_forwarding_guide() {
    local port="$1"
    local local_ip="192.168.1.245"  # Your local IP from earlier
    
    print_step "Router Port Forwarding Setup Guide"
    echo ""
    echo "To access Ollama via chat.spicyfy.io:$port, you need to:"
    echo ""
    echo "1️⃣ Configure DNS (if not done already):"
    echo "   • Log into your domain registrar (GoDaddy, Namecheap, etc.)"
    echo "   • Create an A record: chat.spicyfy.io → $(get_public_ip)"
    echo ""
    echo "2️⃣ Configure Router Port Forwarding:"
    echo "   • Access your router admin panel (usually 192.168.1.1 or 192.168.0.1)"
    echo "   • Navigate to Port Forwarding / NAT settings"
    echo "   • Add rule: External Port $port → Internal IP $local_ip:$port"
    echo "   • Protocol: TCP"
    echo "   • Save and restart router if needed"
    echo ""
    echo "3️⃣ Configure Firewall (if enabled):"
    echo "   • macOS: System Preferences → Security & Privacy → Firewall"
    echo "   • Allow incoming connections on port $port"
    echo ""
    echo "4️⃣ Test Configuration:"
    echo "   • From external network: curl http://chat.spicyfy.io:$port/api/tags"
    echo "   • Or use online port checker tools"
    echo ""
}

# Setup reverse proxy with nginx
setup_nginx_proxy() {
    local domain="$1"
    local port="$2"
    local target_port="11434"
    
    print_step "Setting up nginx reverse proxy..."
    
    # Check if nginx is installed
    if ! command -v nginx &> /dev/null; then
        print_status "Installing nginx..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            if command -v brew &> /dev/null; then
                brew install nginx
            else
                print_error "Homebrew not found. Please install nginx manually."
                return 1
            fi
        else
            sudo apt update && sudo apt install -y nginx
        fi
    fi
    
    # Create nginx configuration
    local config_file="/usr/local/etc/nginx/servers/ollama.conf"
    if [[ "$OSTYPE" != "darwin"* ]]; then
        config_file="/etc/nginx/sites-available/ollama"
    fi
    
    print_status "Creating nginx configuration..."
    
    local nginx_config="server {
    listen $port;
    server_name $domain;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection \"1; mode=block\";
    
    # Proxy settings
    location / {
        proxy_pass http://127.0.0.1:$target_port;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support (if needed)
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \"upgrade\";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 \"healthy\";
        add_header Content-Type text/plain;
    }
}"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sudo mkdir -p "$(dirname "$config_file")"
        echo "$nginx_config" | sudo tee "$config_file" > /dev/null
        
        # Test and reload nginx
        sudo nginx -t && sudo brew services restart nginx
    else
        # Linux
        echo "$nginx_config" | sudo tee "$config_file" > /dev/null
        sudo ln -sf "$config_file" /etc/nginx/sites-enabled/
        sudo rm -f /etc/nginx/sites-enabled/default
        
        # Test and reload nginx
        sudo nginx -t && sudo systemctl restart nginx
    fi
    
    print_success "nginx reverse proxy configured for $domain:$port → localhost:$target_port"
}

# Setup SSL with Let's Encrypt
setup_ssl() {
    local domain="$1"
    
    print_step "Setting up SSL certificate with Let's Encrypt..."
    
    if ! command -v certbot &> /dev/null; then
        print_status "Installing certbot..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            brew install certbot
        else
            sudo apt update && sudo apt install -y certbot python3-certbot-nginx
        fi
    fi
    
    # Get SSL certificate
    print_status "Obtaining SSL certificate for $domain..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sudo certbot --nginx -d "$domain" --non-interactive --agree-tos --email admin@spicyfy.io
    else
        sudo certbot --nginx -d "$domain" --non-interactive --agree-tos --email admin@spicyfy.io
    fi
    
    # Setup auto-renewal
    if [[ "$OSTYPE" != "darwin"* ]]; then
        sudo systemctl enable certbot.timer
        sudo systemctl start certbot.timer
    fi
    
    print_success "SSL certificate configured for $domain"
}

# Test domain access
test_domain_access() {
    local domain="$1"
    local port="$2"
    
    print_step "Testing domain access..."
    
    local url="http://$domain:$port/api/tags"
    print_status "Testing: $url"
    
    if curl -s --connect-timeout 10 "$url" &> /dev/null; then
        print_success "✅ Ollama is accessible via $domain:$port"
        
        # Show sample response
        echo ""
        echo "📋 Sample API response:"
        curl -s "$url" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(json.dumps(data, indent=2))
except:
    print('Could not parse JSON response')
" 2>/dev/null || echo "Raw response received"
        
    else
        print_error "❌ Ollama is not accessible via $domain:$port"
        echo ""
        echo "🔧 Troubleshooting steps:"
        echo "1. Verify DNS points to your public IP: $(get_public_ip)"
        echo "2. Check router port forwarding for port $port"
        echo "3. Verify firewall allows incoming connections on port $port"
        echo "4. Ensure Ollama is running and accessible locally"
        return 1
    fi
}

# Main setup function
setup_domain_access() {
    local domain="$1"
    local port="${2:-11434}"
    
    print_step "Setting up domain access for $domain:$port"
    
    # Check if Ollama is running locally
    if ! curl -s http://localhost:11434/api/tags &> /dev/null; then
        print_error "Ollama is not running locally. Please start Ollama first."
        return 1
    fi
    
    # Show current network info
    echo ""
    echo "🌐 Network Information:"
    echo "   Public IP: $(get_public_ip)"
    echo "   Local IP: 192.168.1.245"
    echo "   Target Domain: $domain"
    echo "   Target Port: $port"
    echo ""
    
    # Check DNS
    if ! check_dns "$domain"; then
        print_warning "DNS configuration may need attention"
    fi
    
    # Show setup options
    echo ""
    echo "🔧 Setup Options:"
    echo "1) Direct port forwarding (router configuration required)"
    echo "2) Reverse proxy with nginx (recommended)"
    echo "3) Show manual setup guide only"
    echo ""
    read -p "Choose option (1-3): " -n 1 -r
    echo
    
    case $REPLY in
        1)
            show_port_forwarding_guide "$port"
            echo ""
            read -p "Press Enter after configuring router port forwarding..."
            test_domain_access "$domain" "$port"
            ;;
        2)
            setup_nginx_proxy "$domain" "$port"
            echo ""
            print_info "After nginx setup, configure router to forward port $port to this machine"
            read -p "Press Enter after configuring router..."
            test_domain_access "$domain" "$port"
            
            # Offer SSL setup
            echo ""
            read -p "Setup SSL certificate for HTTPS access? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                setup_ssl "$domain"
            fi
            ;;
        3)
            show_port_forwarding_guide "$port"
            ;;
        *)
            print_error "Invalid option"
            return 1
            ;;
    esac
}

# Show help
show_help() {
    echo "🌐 Domain Access Setup for Ollama"
    echo ""
    echo "Configure custom domain access to Ollama service"
    echo ""
    echo "📋 Usage: $0 [OPTIONS] <domain> [port]"
    echo ""
    echo "🔧 Options:"
    echo "  --setup <domain> [port]    Setup domain access (default port: 11434)"
    echo "  --test <domain> [port]     Test domain accessibility"
    echo "  --dns-check <domain>       Check DNS configuration"
    echo "  --help                     Show this help message"
    echo ""
    echo "📝 Examples:"
    echo "  $0 --setup chat.spicyfy.io 11434"
    echo "  $0 --test chat.spicyfy.io"
    echo "  $0 --dns-check chat.spicyfy.io"
    echo ""
}

# Main execution
case "${1:-}" in
    --setup)
        if [[ -z "$2" ]]; then
            print_error "Domain required. Usage: $0 --setup <domain> [port]"
            exit 1
        fi
        setup_domain_access "$2" "${3:-11434}"
        ;;
    --test)
        if [[ -z "$2" ]]; then
            print_error "Domain required. Usage: $0 --test <domain> [port]"
            exit 1
        fi
        test_domain_access "$2" "${3:-11434}"
        ;;
    --dns-check)
        if [[ -z "$2" ]]; then
            print_error "Domain required. Usage: $0 --dns-check <domain>"
            exit 1
        fi
        check_dns "$2"
        ;;
    --help)
        show_help
        ;;
    *)
        if [[ -n "$1" ]]; then
            # Direct domain setup
            setup_domain_access "$1" "${2:-11434}"
        else
            show_help
        fi
        ;;
esac
