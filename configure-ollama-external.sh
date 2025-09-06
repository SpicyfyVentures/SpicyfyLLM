#!/bin/bash

# SpicyfyLLM - Ollama External Access Configuration Script
# Configure Ollama to be accessible from external sites
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

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    elif [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS="linux"
        DISTRO="$ID"
    else
        OS="unknown"
    fi
}

# Check if Ollama is installed
check_ollama() {
    if ! command -v ollama &> /dev/null; then
        print_error "Ollama is not installed. Please install Ollama first."
        echo "Visit: https://ollama.com/download"
        exit 1
    fi
    print_success "Ollama is installed"
}

# Stop Ollama service
stop_ollama() {
    print_status "Stopping Ollama service..."
    
    if [[ "$OS" == "macos" ]]; then
        # macOS - stop via brew services or kill process
        if command -v brew &> /dev/null && brew services list | grep -q ollama; then
            brew services stop ollama 2>/dev/null || true
        fi
        # Kill any running ollama processes
        pkill -f "ollama serve" 2>/dev/null || true
    else
        # Linux - stop systemd service
        if systemctl is-active --quiet ollama 2>/dev/null; then
            sudo systemctl stop ollama
        fi
        # Kill any running ollama processes
        pkill -f "ollama serve" 2>/dev/null || true
    fi
    
    sleep 2
    print_success "Ollama service stopped"
}

# Configure Ollama for external access on macOS
configure_macos() {
    print_step "Configuring Ollama for external access on macOS..."
    
    # Create or update the environment file
    local env_file="$HOME/.ollama_env"
    echo "export OLLAMA_HOST=0.0.0.0:11434" > "$env_file"
    
    # Add to shell profile
    local shell_profile=""
    if [[ "$SHELL" == *"zsh"* ]]; then
        shell_profile="$HOME/.zshrc"
    elif [[ "$SHELL" == *"bash"* ]]; then
        shell_profile="$HOME/.bash_profile"
    fi
    
    if [[ -n "$shell_profile" ]]; then
        if ! grep -q "source $env_file" "$shell_profile" 2>/dev/null; then
            echo "source $env_file" >> "$shell_profile"
            print_success "Added Ollama environment to $shell_profile"
        fi
    fi
    
    # Create a LaunchAgent for persistent service
    local plist_file="$HOME/Library/LaunchAgents/com.ollama.serve.plist"
    mkdir -p "$HOME/Library/LaunchAgents"
    
    cat > "$plist_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ollama.serve</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(which ollama)</string>
        <string>serve</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>OLLAMA_HOST</key>
        <string>0.0.0.0:11434</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/ollama.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/ollama.error.log</string>
</dict>
</plist>
EOF
    
    # Load the LaunchAgent
    launchctl unload "$plist_file" 2>/dev/null || true
    launchctl load "$plist_file"
    
    print_success "Ollama LaunchAgent configured for external access"
}

# Configure Ollama for external access on Linux
configure_linux() {
    print_step "Configuring Ollama for external access on Linux..."
    
    # Create systemd service override
    local override_dir="/etc/systemd/system/ollama.service.d"
    sudo mkdir -p "$override_dir"
    
    cat << EOF | sudo tee "$override_dir/override.conf" > /dev/null
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOF
    
    # Reload systemd and restart service
    sudo systemctl daemon-reload
    sudo systemctl enable ollama
    sudo systemctl start ollama
    
    print_success "Ollama systemd service configured for external access"
}

# Start Ollama with external access
start_ollama() {
    print_status "Starting Ollama with external access..."
    
    if [[ "$OS" == "macos" ]]; then
        # macOS - service should start automatically via LaunchAgent
        sleep 3
    else
        # Linux - service should be running via systemd
        sleep 3
    fi
    
    # Verify Ollama is accessible externally
    local max_wait=30
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        if curl -s http://0.0.0.0:11434/api/tags &> /dev/null; then
            print_success "Ollama is running and accessible externally on port 11434"
            return 0
        fi
        sleep 2
        wait_time=$((wait_time + 2))
        echo -n "."
    done
    echo
    
    print_error "Ollama is not responding on external interface"
    return 1
}

# Configure firewall (optional)
configure_firewall() {
    print_step "Configuring firewall for Ollama access..."
    
    if [[ "$OS" == "macos" ]]; then
        print_warning "macOS firewall configuration:"
        echo "1. Go to System Preferences > Security & Privacy > Firewall"
        echo "2. Click 'Firewall Options'"
        echo "3. Add Ollama to allowed applications or allow incoming connections on port 11434"
        echo ""
        read -p "Press Enter after configuring firewall (or skip if not needed)..."
        
    elif [[ "$OS" == "linux" ]]; then
        if command -v ufw &> /dev/null; then
            print_status "Configuring UFW firewall..."
            read -p "Allow Ollama port 11434 through firewall? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                sudo ufw allow 11434/tcp
                print_success "UFW rule added for port 11434"
            fi
        elif command -v firewall-cmd &> /dev/null; then
            print_status "Configuring firewalld..."
            read -p "Allow Ollama port 11434 through firewall? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                sudo firewall-cmd --permanent --add-port=11434/tcp
                sudo firewall-cmd --reload
                print_success "Firewalld rule added for port 11434"
            fi
        else
            print_warning "No supported firewall found. You may need to manually configure firewall rules."
        fi
    fi
}

# Show security warning
show_security_warning() {
    print_warning "SECURITY CONSIDERATIONS:"
    echo ""
    echo "⚠️  Ollama has NO built-in authentication!"
    echo "⚠️  Anyone with network access can use your Ollama instance"
    echo "⚠️  This includes downloading/running models and accessing your data"
    echo ""
    echo "🔒 Security recommendations:"
    echo "   • Use a reverse proxy with authentication (nginx, Caddy, etc.)"
    echo "   • Configure firewall rules to limit access"
    echo "   • Use VPN for secure remote access"
    echo "   • Monitor Ollama logs for suspicious activity"
    echo "   • Consider using ngrok for temporary external access instead"
    echo ""
    read -p "Do you understand the security implications? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Configuration cancelled for security reasons"
        exit 1
    fi
}

# Test external access
test_external_access() {
    print_step "Testing external access..."
    
    # Get local IP address
    local local_ip=""
    if [[ "$OS" == "macos" ]]; then
        local_ip=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | head -1 | awk '{print $2}')
    else
        local_ip=$(ip route get 1 | awk '{print $7; exit}' 2>/dev/null || hostname -I | awk '{print $1}')
    fi
    
    if [[ -n "$local_ip" ]]; then
        print_status "Testing access from local network..."
        if curl -s "http://$local_ip:11434/api/tags" &> /dev/null; then
            print_success "✅ Ollama is accessible from local network at: http://$local_ip:11434"
        else
            print_warning "❌ Ollama is not accessible from local network"
        fi
        
        echo ""
        echo "🌐 External access URLs:"
        echo "   Local network: http://$local_ip:11434"
        echo "   Localhost: http://localhost:11434"
        echo ""
        echo "🧪 Test with: curl http://$local_ip:11434/api/tags"
    else
        print_warning "Could not determine local IP address"
    fi
}

# Setup ngrok tunnel as alternative
setup_ngrok_tunnel() {
    print_step "Setting up ngrok tunnel for secure external access..."
    
    if ! command -v ngrok &> /dev/null; then
        print_error "ngrok is not installed. Install it first:"
        echo "Visit: https://ngrok.com/download"
        return 1
    fi
    
    # Check if ngrok is authenticated
    if ! ngrok config check &> /dev/null; then
        print_warning "ngrok is not authenticated"
        echo "Please sign up at https://ngrok.com and get your authtoken"
        read -p "Enter your ngrok authtoken: " authtoken
        ngrok config add-authtoken "$authtoken"
    fi
    
    print_status "Starting ngrok tunnel for Ollama..."
    nohup ngrok http 11434 --log=stdout > ollama_ngrok.log 2>&1 &
    NGROK_PID=$!
    echo "$NGROK_PID" > .ollama_ngrok_pid
    
    sleep 5
    
    # Get the public URL
    PUBLIC_URL=$(curl -s http://localhost:4040/api/tunnels | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for tunnel in data['tunnels']:
        if tunnel['proto'] == 'https':
            print(tunnel['public_url'])
            break
except:
    pass
" 2>/dev/null)
    
    if [[ -n "$PUBLIC_URL" ]]; then
        print_success "🌐 Ollama ngrok tunnel active!"
        print_success "Public URL: $PUBLIC_URL"
        echo ""
        echo "🧪 Test with: curl $PUBLIC_URL/api/tags"
        echo "🔧 Stop tunnel: kill \$(cat .ollama_ngrok_pid)"
    else
        print_error "Failed to get ngrok public URL"
        print_status "Check ngrok status at: http://localhost:4040"
    fi
}

# Revert configuration
revert_configuration() {
    print_step "Reverting Ollama to localhost-only access..."
    
    stop_ollama
    
    if [[ "$OS" == "macos" ]]; then
        # Remove LaunchAgent
        local plist_file="$HOME/Library/LaunchAgents/com.ollama.serve.plist"
        if [[ -f "$plist_file" ]]; then
            launchctl unload "$plist_file" 2>/dev/null || true
            rm "$plist_file"
        fi
        
        # Remove environment file
        rm -f "$HOME/.ollama_env"
        
        # Start Ollama normally
        if command -v brew &> /dev/null; then
            brew services start ollama
        else
            nohup ollama serve > /dev/null 2>&1 &
        fi
        
    else
        # Remove systemd override
        if [[ -d "/etc/systemd/system/ollama.service.d" ]]; then
            sudo rm -rf "/etc/systemd/system/ollama.service.d"
            sudo systemctl daemon-reload
        fi
        
        # Restart service normally
        sudo systemctl restart ollama
    fi
    
    print_success "Ollama reverted to localhost-only access"
}

# Show help
show_help() {
    echo "🚀 Ollama External Access Configuration"
    echo ""
    echo "Configure Ollama to be accessible from external sites"
    echo ""
    echo "📋 Usage: $0 [OPTIONS]"
    echo ""
    echo "🔧 Options:"
    echo "  --configure      Configure Ollama for external access"
    echo "  --ngrok          Setup ngrok tunnel (secure alternative)"
    echo "  --test           Test external access"
    echo "  --revert         Revert to localhost-only access"
    echo "  --status         Show current Ollama status"
    echo "  --help           Show this help message"
    echo ""
    echo "⚠️  Security Warning:"
    echo "  Ollama has no built-in authentication. External access"
    echo "  allows anyone to use your AI models and data."
    echo ""
}

# Show status
show_status() {
    print_step "Ollama Status Check"
    
    if ! command -v ollama &> /dev/null; then
        print_error "Ollama is not installed"
        return 1
    fi
    
    # Check if Ollama is running
    if curl -s http://localhost:11434/api/tags &> /dev/null; then
        print_success "✅ Ollama is running on localhost:11434"
        
        # Check external access
        if curl -s http://0.0.0.0:11434/api/tags &> /dev/null; then
            print_success "✅ Ollama is accessible externally"
            
            # Get local IP
            local local_ip=""
            if [[ "$OS" == "macos" ]]; then
                local_ip=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | head -1 | awk '{print $2}')
            else
                local_ip=$(ip route get 1 | awk '{print $7; exit}' 2>/dev/null || hostname -I | awk '{print $1}')
            fi
            
            if [[ -n "$local_ip" ]]; then
                echo "   🌐 External URL: http://$local_ip:11434"
            fi
        else
            print_warning "⚠️  Ollama is localhost-only"
        fi
        
        # Ask user for custom domain preference
        echo ""
        echo "ngrok tunnel options:"
        echo "1) Random subdomain (free) - e.g., https://abc123-def456.ngrok.io"
        echo "2) Custom domain (paid plan required) - e.g., https://chat.spicyfy.io"
        echo ""
        read -p "Choose option (1/2): " -n 1 -r
        echo
        
        local ngrok_command="ngrok http 11434 --log=stdout"
        
        if [[ $REPLY == "2" ]]; then
            echo ""
            read -p "Enter your custom domain (e.g., chat.spicyfy.io): " custom_domain
            if [ -n "$custom_domain" ]; then
                ngrok_command="ngrok http 11434 --domain=$custom_domain --log=stdout"
                print_status "Starting ngrok tunnel with custom domain: $custom_domain"
            else
                print_warning "No domain provided, using random subdomain"
                print_status "Starting ngrok tunnel with random subdomain..."
            fi
        else
            print_status "Starting ngrok tunnel with random subdomain..."
        fi
        
        # Setup ngrok tunnel as alternative
        setup_ngrok_tunnel() {
            print_step "Setting up ngrok tunnel for secure external access..."
            
            if ! command -v ngrok &> /dev/null; then
                print_error "ngrok is not installed. Install it first:"
                echo "Visit: https://ngrok.com/download"
                return 1
            fi
            
            # Check if ngrok is authenticated
            if ! ngrok config check &> /dev/null; then
                print_warning "ngrok is not authenticated"
                echo "Please sign up at https://ngrok.com and get your authtoken"
                read -p "Enter your ngrok authtoken: " authtoken
                ngrok config add-authtoken "$authtoken"
            fi
            
            print_status "Starting ngrok tunnel for Ollama..."
            nohup $ngrok_command > ollama_ngrok.log 2>&1 &
            NGROK_PID=$!
            echo "$NGROK_PID" > .ollama_ngrok_pid
            
            sleep 5
            
            # Get the public URL
            PUBLIC_URL=$(curl -s http://localhost:4040/api/tunnels | python3 -c "
            import sys, json
            try:
                data = json.load(sys.stdin)
                for tunnel in data['tunnels']:
                    if tunnel['proto'] == 'https':
                        print(tunnel['public_url'])
                        break
            except:
                pass
            " 2>/dev/null)
            
            if [[ -n "$PUBLIC_URL" ]]; then
                print_success "🌐 Ollama ngrok tunnel active!"
                print_success "Public URL: $PUBLIC_URL"
                echo ""
                echo "🧪 Test with: curl $PUBLIC_URL/api/tags"
                echo "🔧 Stop tunnel: kill \$(cat .ollama_ngrok_pid)"
            else
                print_error "Failed to get ngrok public URL"
                print_status "Check ngrok status at: http://localhost:4040"
            fi
        }

# Main execution
detect_os

case "${1:-}" in
    --configure)
        check_ollama
        show_security_warning
        stop_ollama
        
        if [[ "$OS" == "macos" ]]; then
            configure_macos
        else
            configure_linux
        fi
        
        start_ollama
        configure_firewall
        test_external_access
        
        print_success "🎉 Ollama is now configured for external access!"
        echo ""
        echo "🔧 Management commands:"
        echo "   • Check status: $0 --status"
        echo "   • Test access: $0 --test"
        echo "   • Revert config: $0 --revert"
        ;;
    --ngrok)
        check_ollama
        setup_ngrok_tunnel
        ;;
    --test)
        test_external_access
        ;;
    --revert)
        revert_configuration
        ;;
    --status)
        show_status
        ;;
    --help)
        show_help
        ;;
    *)
        echo "🤖 Ollama External Access Configuration"
        echo ""
        echo "Choose configuration method:"
        echo "1) Configure for direct external access (requires firewall setup)"
        echo "2) Setup ngrok tunnel (secure, temporary access)"
        echo "3) Show current status"
        echo "4) Show help"
        echo ""
        read -p "Choose option (1-4): " -n 1 -r
        echo
        
        case $REPLY in
            1)
                $0 --configure
                ;;
            2)
                $0 --ngrok
                ;;
            3)
                $0 --status
                ;;
            4)
                $0 --help
                ;;
            *)
                print_error "Invalid option"
                $0 --help
                ;;
        esac
        ;;
esac
