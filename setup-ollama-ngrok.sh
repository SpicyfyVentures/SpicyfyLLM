#!/bin/bash

# SpicyfyLLM - Ollama ngrok Tunnel Setup
# Create external access to Ollama via ngrok tunnel
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

# Check if Ollama is running
check_ollama() {
    if ! curl -s http://localhost:11434/api/tags &> /dev/null; then
        print_error "Ollama is not running on localhost:11434"
        print_status "Please start Ollama first:"
        echo "  • brew services start ollama"
        echo "  • or run: ollama serve"
        return 1
    fi
    print_success "Ollama is running on localhost:11434"
    return 0
}

# Check if ngrok is installed and authenticated
check_ngrok() {
    if ! command -v ngrok &> /dev/null; then
        print_error "ngrok is not installed"
        print_status "Install ngrok:"
        echo "  • Visit: https://ngrok.com/download"
        echo "  • Or run: brew install ngrok/ngrok/ngrok"
        return 1
    fi
    
    if ! ngrok config check &> /dev/null; then
        print_warning "ngrok is not authenticated"
        print_status "Get your authtoken from https://dashboard.ngrok.com/get-started/your-authtoken"
        read -p "Enter your ngrok authtoken: " authtoken
        if [[ -n "$authtoken" ]]; then
            ngrok config add-authtoken "$authtoken"
            print_success "ngrok authenticated"
        else
            print_error "No authtoken provided"
            return 1
        fi
    fi
    
    print_success "ngrok is installed and authenticated"
    return 0
}

# Stop existing ngrok tunnel
stop_ngrok() {
    print_status "Stopping existing ngrok tunnels..."
    
    # Kill any existing ngrok processes
    pkill -f "ngrok http" 2>/dev/null || true
    
    # Clean up PID files
    rm -f .ollama_ngrok_pid ollama_ngrok.log
    
    sleep 2
    print_success "Existing ngrok tunnels stopped"
}

# Start ngrok tunnel for Ollama
start_ngrok_tunnel() {
    local custom_domain="$1"
    local use_custom_domain="$2"
    
    print_step "Starting ngrok tunnel for Ollama..."
    
    local ngrok_command="ngrok http 11434 --log=stdout"
    
    if [[ "$use_custom_domain" == "true" && -n "$custom_domain" ]]; then
        ngrok_command="ngrok http 11434 --domain=$custom_domain --log=stdout"
        print_status "Using custom domain: $custom_domain"
    else
        print_status "Using random ngrok subdomain"
    fi
    
    # Start ngrok in background
    nohup $ngrok_command > ollama_ngrok.log 2>&1 &
    NGROK_PID=$!
    echo "$NGROK_PID" > .ollama_ngrok_pid
    
    print_status "ngrok tunnel starting (PID: $NGROK_PID)..."
    sleep 8
    
    # Get the public URL
    local public_url=""
    local attempts=0
    local max_attempts=10
    
    while [[ $attempts -lt $max_attempts ]]; do
        public_url=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | python3 -c "
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
        
        if [[ -n "$public_url" ]]; then
            break
        fi
        
        attempts=$((attempts + 1))
        sleep 2
        echo -n "."
    done
    echo
    
    if [[ -n "$public_url" ]]; then
        print_success "🌐 Ollama ngrok tunnel is active!"
        print_success "Public URL: $public_url"
        
        # Save the URL for later reference
        echo "$public_url" > .ollama_ngrok_url
        
        echo ""
        echo "🧪 Test your Ollama endpoint:"
        echo "   curl $public_url/api/tags"
        echo ""
        echo "🔧 Tunnel Management:"
        echo "   • Status: $0 --status"
        echo "   • Stop: $0 --stop"
        echo "   • Logs: tail -f ollama_ngrok.log"
        echo "   • Dashboard: http://localhost:4040"
        
        return 0
    else
        print_error "Failed to get ngrok public URL"
        print_status "Check ngrok logs: tail ollama_ngrok.log"
        print_status "Check ngrok dashboard: http://localhost:4040"
        return 1
    fi
}

# Test the ngrok tunnel
test_tunnel() {
    if [[ ! -f ".ollama_ngrok_url" ]]; then
        print_error "No active ngrok tunnel found"
        return 1
    fi
    
    local public_url=$(cat .ollama_ngrok_url)
    print_step "Testing ngrok tunnel: $public_url"
    
    if curl -s --connect-timeout 10 "$public_url/api/tags" &> /dev/null; then
        print_success "✅ Ollama is accessible via ngrok tunnel"
        
        echo ""
        echo "📋 API Response:"
        curl -s "$public_url/api/tags" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(json.dumps(data, indent=2))
except:
    print('Could not parse JSON response')
" 2>/dev/null
        
        echo ""
        echo "🔗 Your external Ollama endpoint: $public_url"
        
    else
        print_error "❌ Ollama is not accessible via ngrok tunnel"
        print_status "Check tunnel status: $0 --status"
        return 1
    fi
}

# Show tunnel status
show_status() {
    print_step "ngrok Tunnel Status"
    
    # Check if PID file exists and process is running
    if [[ -f ".ollama_ngrok_pid" ]]; then
        local ngrok_pid=$(cat .ollama_ngrok_pid)
        if kill -0 "$ngrok_pid" 2>/dev/null; then
            print_success "✅ ngrok tunnel is running (PID: $ngrok_pid)"
            
            if [[ -f ".ollama_ngrok_url" ]]; then
                local public_url=$(cat .ollama_ngrok_url)
                echo "   🌐 Public URL: $public_url"
                
                # Test if accessible
                if curl -s --connect-timeout 5 "$public_url/api/tags" &> /dev/null; then
                    print_success "   ✅ Tunnel is accessible"
                else
                    print_warning "   ⚠️  Tunnel may not be accessible"
                fi
            fi
        else
            print_warning "⚠️  ngrok PID file exists but process is not running"
            rm -f .ollama_ngrok_pid .ollama_ngrok_url
        fi
    else
        print_warning "❌ No active ngrok tunnel found"
    fi
    
    # Check Ollama status
    echo ""
    if curl -s http://localhost:11434/api/tags &> /dev/null; then
        print_success "✅ Ollama is running locally"
    else
        print_error "❌ Ollama is not running locally"
    fi
    
    # Show ngrok dashboard info
    echo ""
    echo "🔧 Management:"
    echo "   • ngrok Dashboard: http://localhost:4040"
    echo "   • Logs: tail -f ollama_ngrok.log"
    echo "   • Start tunnel: $0 --start"
    echo "   • Stop tunnel: $0 --stop"
}

# Setup with custom domain
setup_custom_domain() {
    print_step "Setting up ngrok tunnel with custom domain"
    
    echo ""
    echo "📝 Custom Domain Setup:"
    echo "1. You need an ngrok paid plan for custom domains"
    echo "2. Add your domain in ngrok dashboard: https://dashboard.ngrok.com/domains"
    echo "3. Create a CNAME record: your-subdomain.yourdomain.com → tunnel.us.ngrok.com"
    echo ""
    
    read -p "Enter your custom domain (e.g., ollama.spicyfy.io): " custom_domain
    
    if [[ -z "$custom_domain" ]]; then
        print_error "No domain provided"
        return 1
    fi
    
    print_status "Setting up tunnel with custom domain: $custom_domain"
    
    # Check prerequisites
    if ! check_ollama || ! check_ngrok; then
        return 1
    fi
    
    # Stop existing tunnels
    stop_ngrok
    
    # Start tunnel with custom domain
    start_ngrok_tunnel "$custom_domain" "true"
}

# Setup with random domain
setup_random_domain() {
    print_step "Setting up ngrok tunnel with random subdomain"
    
    # Check prerequisites
    if ! check_ollama || ! check_ngrok; then
        return 1
    fi
    
    # Stop existing tunnels
    stop_ngrok
    
    # Start tunnel with random domain
    start_ngrok_tunnel "" "false"
}

# Show help
show_help() {
    echo "🚀 Ollama ngrok Tunnel Setup"
    echo ""
    echo "Create external access to your local Ollama via ngrok tunnel"
    echo ""
    echo "📋 Usage: $0 [OPTIONS]"
    echo ""
    echo "🔧 Options:"
    echo "  --start          Start ngrok tunnel (random subdomain)"
    echo "  --custom         Start tunnel with custom domain"
    echo "  --stop           Stop ngrok tunnel"
    echo "  --status         Show tunnel status"
    echo "  --test           Test tunnel accessibility"
    echo "  --restart        Restart tunnel"
    echo "  --help           Show this help message"
    echo ""
    echo "📝 Examples:"
    echo "  $0 --start       # Quick start with random domain"
    echo "  $0 --custom      # Setup with custom domain"
    echo "  $0 --status      # Check if tunnel is running"
    echo ""
    echo "💡 Notes:"
    echo "  • Ollama must be running on localhost:11434"
    echo "  • Custom domains require ngrok paid plan"
    echo "  • Free plan provides HTTPS random subdomains"
    echo ""
}

# Main execution
case "${1:-}" in
    --start)
        setup_random_domain
        ;;
    --custom)
        setup_custom_domain
        ;;
    --stop)
        stop_ngrok
        ;;
    --status)
        show_status
        ;;
    --test)
        test_tunnel
        ;;
    --restart)
        stop_ngrok
        sleep 2
        setup_random_domain
        ;;
    --help)
        show_help
        ;;
    *)
        echo "🤖 Ollama ngrok Tunnel Setup"
        echo ""
        echo "Choose setup option:"
        echo "1) Quick start with random subdomain (free)"
        echo "2) Setup with custom domain (paid plan required)"
        echo "3) Show current status"
        echo "4) Stop existing tunnel"
        echo ""
        read -p "Choose option (1-4): " -n 1 -r
        echo
        
        case $REPLY in
            1)
                setup_random_domain
                ;;
            2)
                setup_custom_domain
                ;;
            3)
                show_status
                ;;
            4)
                stop_ngrok
                ;;
            *)
                print_error "Invalid option"
                show_help
                ;;
        esac
        ;;
esac
