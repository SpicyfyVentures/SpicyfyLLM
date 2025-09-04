#!/bin/bash

# SpicyfyLLM - OpenWebUI Complete Setup Script
# A foolproof, one-command setup for OpenWebUI with all dependencies
# 
# Author: SpicyfyLLM Team
# License: MIT
# Repository: https://github.com/vamsikandikonda/SpicyfyLLM
#
# Supports: macOS, Ubuntu, Debian, CentOS, RHEL, Fedora
# Features: Docker, ngrok, Ollama installation with version checking and upgrades

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
OPENWEBUI_PORT=3000
SEARXNG_PORT=8081
CONTAINER_NAME="open-webui"
SEARXNG_CONTAINER="searxng"
VOLUME_NAME="open-webui"
SEARXNG_VOLUME="searxng-config"

# Version requirements
DOCKER_MIN_VERSION="20.10.0"
NGROK_MIN_VERSION="3.0.0"
OLLAMA_MIN_VERSION="0.1.0"

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

print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

print_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

# Detect OS and distribution
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        DISTRO="macos"
    elif [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS="linux"
        DISTRO="$ID"
    else
        OS="unknown"
        DISTRO="unknown"
    fi
    
    print_info "Detected OS: $OS ($DISTRO)"
}

# Simplified version check - just check if Docker exists and is accessible
check_docker_version() {
    local current_version=$1
    local min_version=$2
    
    # For simplicity, assume any Docker version 20+ is sufficient
    local major_version=$(echo "$current_version" | cut -d. -f1)
    
    if (( major_version >= 20 )); then
        return 0  # sufficient
    else
        return 1  # insufficient
    fi
}

# Check if running as root (needed for some installations)
check_sudo() {
    if [[ $EUID -eq 0 ]]; then
        print_warning "Running as root. This is not recommended for security reasons."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "Exiting. Please run as a regular user with sudo privileges."
            exit 1
        fi
    fi
    
    # Check if user has sudo privileges
    if ! sudo -n true 2>/dev/null; then
        print_info "This script requires sudo privileges for system package installation."
        print_info "You may be prompted for your password."
    fi
}

# Install system dependencies
install_system_deps() {
    print_step "Installing system dependencies..."
    
    case $DISTRO in
        "macos")
            # Check if Homebrew is installed
            if ! command -v brew &> /dev/null; then
                print_status "Installing Homebrew..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                
                # Add Homebrew to PATH for current session
                if [[ -f "/opt/homebrew/bin/brew" ]]; then
                    eval "$(/opt/homebrew/bin/brew shellenv)"
                elif [[ -f "/usr/local/bin/brew" ]]; then
                    eval "$(/usr/local/bin/brew shellenv)"
                fi
            else
                print_success "Homebrew is already installed"
                # Update Homebrew
                print_status "Updating Homebrew..."
                brew update
            fi
            
            # Install basic tools
            brew install curl wget openssl
            ;;
        "ubuntu"|"debian")
            print_status "Updating package lists..."
            sudo apt update
            
            print_status "Installing basic dependencies..."
            sudo apt install -y curl wget apt-transport-https ca-certificates gnupg lsb-release openssl
            ;;
        "centos"|"rhel"|"fedora")
            if command -v dnf &> /dev/null; then
                PKG_MANAGER="dnf"
            else
                PKG_MANAGER="yum"
            fi
            
            print_status "Installing basic dependencies..."
            sudo $PKG_MANAGER install -y curl wget openssl
            ;;
        *)
            print_warning "Unsupported distribution: $DISTRO"
            print_info "Please install curl, wget, and openssl manually"
            ;;
    esac
}

# Install or upgrade Docker
install_docker() {
    print_step "Checking Docker installation..."
    
    local current_version=""
    local needs_install=true
    
    if command -v docker &> /dev/null; then
        current_version=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        print_info "Found Docker version: $current_version"
        
        if check_docker_version "$current_version" "$DOCKER_MIN_VERSION"; then
            print_success "Docker version is sufficient"
            needs_install=false
        else
            print_warning "Docker version $current_version is below minimum required $DOCKER_MIN_VERSION"
            read -p "Upgrade Docker? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                needs_install=false
            fi
        fi
    fi
    
    if [[ "$needs_install" == "true" ]]; then
        print_status "Installing Docker..."
        
        case $DISTRO in
            "macos")
                if command -v brew &> /dev/null; then
                    brew install --cask docker
                    print_info "Docker Desktop installed. Please start Docker Desktop manually."
                    print_info "Waiting for Docker Desktop to start..."
                    
                    # Wait for Docker to be available
                    local max_wait=60
                    local wait_time=0
                    while ! docker info &> /dev/null && [ $wait_time -lt $max_wait ]; do
                        sleep 2
                        wait_time=$((wait_time + 2))
                        echo -n "."
                    done
                    echo
                    
                    if ! docker info &> /dev/null; then
                        print_error "Docker Desktop is not running. Please start it manually and run this script again."
                        exit 1
                    fi
                else
                    print_error "Homebrew not found. Please install Docker Desktop manually from https://docker.com"
                    exit 1
                fi
                ;;
            "ubuntu"|"debian")
                # Remove old versions
                sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
                
                # Add Docker's official GPG key
                curl -fsSL https://download.docker.com/linux/$DISTRO/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
                
                # Add Docker repository
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$DISTRO $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
                
                # Install Docker
                sudo apt update
                sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
                
                # Add user to docker group
                sudo usermod -aG docker $USER
                
                # Start and enable Docker
                sudo systemctl start docker
                sudo systemctl enable docker
                ;;
            "centos"|"rhel"|"fedora")
                # Remove old versions
                sudo $PKG_MANAGER remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true
                
                # Add Docker repository
                sudo $PKG_MANAGER install -y yum-utils
                sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                
                # Install Docker
                sudo $PKG_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
                
                # Add user to docker group
                sudo usermod -aG docker $USER
                
                # Start and enable Docker
                sudo systemctl start docker
                sudo systemctl enable docker
                ;;
            *)
                print_error "Automatic Docker installation not supported for $DISTRO"
                print_info "Please install Docker manually from https://docs.docker.com/get-docker/"
                exit 1
                ;;
        esac
        
        print_success "Docker installed successfully"
        
        # Verify installation
        if ! docker info &> /dev/null; then
            if [[ "$DISTRO" != "macos" ]]; then
                print_warning "Docker installed but not accessible. You may need to log out and back in."
                print_info "Trying to start Docker service..."
                sudo systemctl start docker 2>/dev/null || true
                
                # Try with newgrp
                if ! docker info &> /dev/null; then
                    print_info "Attempting to refresh group membership..."
                    exec sg docker "$0 $*"
                fi
            fi
        fi
    fi
    
    # Final Docker check with cross-platform timeout
    print_status "Verifying Docker is accessible..."
    
    # Cross-platform timeout implementation
    if command -v timeout &> /dev/null; then
        # Linux/GNU timeout
        timeout_cmd="timeout 10"
    elif command -v gtimeout &> /dev/null; then
        # macOS with coreutils installed
        timeout_cmd="gtimeout 10"
    else
        # Fallback for macOS without timeout
        timeout_cmd=""
    fi
    
    if [[ -n "$timeout_cmd" ]]; then
        if $timeout_cmd docker info &> /dev/null; then
            print_success "Docker is ready"
        else
            print_error "Docker is not running or accessible"
            if [[ "$DISTRO" == "macos" ]]; then
                print_info "Please start Docker Desktop and run this script again"
            else
                print_info "Please log out and back in, then run this script again"
            fi
            exit 1
        fi
    else
        # Simple check without timeout on macOS
        if docker info &> /dev/null; then
            print_success "Docker is ready"
        else
            print_error "Docker is not running or accessible"
            print_info "Please start Docker Desktop and run this script again"
            exit 1
        fi
    fi
}

# Install or upgrade ngrok
install_ngrok() {
    print_step "Checking ngrok installation..."
    
    local current_version=""
    local needs_install=true
    
    if command -v ngrok &> /dev/null; then
        current_version=$(ngrok version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        print_info "Found ngrok version: $current_version"
        
        version_compare "$current_version" "$NGROK_MIN_VERSION"
        case $? in
            0|1)
                print_success "ngrok version is sufficient"
                needs_install=false
                ;;
            2)
                print_warning "ngrok version $current_version is below minimum required $NGROK_MIN_VERSION"
                read -p "Upgrade ngrok? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    needs_install=false
                fi
                ;;
        esac
    fi
    
    if [[ "$needs_install" == "true" ]]; then
        print_status "Installing ngrok..."
        
        case $DISTRO in
            "macos")
                if command -v brew &> /dev/null; then
                    brew install ngrok/ngrok/ngrok
                else
                    print_error "Homebrew not found. Please install ngrok manually from https://ngrok.com/download"
                    return 1
                fi
                ;;
            "ubuntu"|"debian")
                curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
                echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list
                sudo apt update && sudo apt install -y ngrok
                ;;
            "centos"|"rhel"|"fedora")
                # Download and install ngrok manually for RHEL-based systems
                local arch=$(uname -m)
                case $arch in
                    x86_64) arch="amd64" ;;
                    aarch64) arch="arm64" ;;
                    *) print_error "Unsupported architecture: $arch"; return 1 ;;
                esac
                
                wget -O ngrok.tgz "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-${arch}.tgz"
                sudo tar xzf ngrok.tgz -C /usr/local/bin
                rm ngrok.tgz
                ;;
            *)
                print_error "Automatic ngrok installation not supported for $DISTRO"
                print_info "Please install ngrok manually from https://ngrok.com/download"
                return 1
                ;;
        esac
        
        print_success "ngrok installed successfully"
    fi
    
    return 0
}

# Install or upgrade Ollama
install_ollama() {
    print_step "Checking Ollama installation..."
    
    local current_version=""
    local needs_install=true
    
    if command -v ollama &> /dev/null; then
        current_version=$(ollama --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
        print_info "Found Ollama version: $current_version"
        
        if [[ "$current_version" != "unknown" ]]; then
            version_compare "$current_version" "$OLLAMA_MIN_VERSION"
            case $? in
                0|1)
                    print_success "Ollama version is sufficient"
                    needs_install=false
                    ;;
                2)
                    print_warning "Ollama version $current_version is below minimum required $OLLAMA_MIN_VERSION"
                    read -p "Upgrade Ollama? (y/N): " -n 1 -r
                    echo
                    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                        needs_install=false
                    fi
                    ;;
            esac
        fi
    fi
    
    if [[ "$needs_install" == "true" ]]; then
        print_status "Installing Ollama..."
        
        case $DISTRO in
            "macos")
                if command -v brew &> /dev/null; then
                    brew install ollama
                    
                    # Start Ollama service
                    print_status "Starting Ollama service..."
                    brew services start ollama
                else
                    # Manual installation for macOS
                    curl -fsSL https://ollama.com/install.sh | sh
                fi
                ;;
            *)
                # Universal installation script
                curl -fsSL https://ollama.com/install.sh | sh
                
                # Start Ollama service on Linux
                if command -v systemctl &> /dev/null; then
                    sudo systemctl start ollama 2>/dev/null || true
                    sudo systemctl enable ollama 2>/dev/null || true
                fi
                ;;
        esac
        
        print_success "Ollama installed successfully"
    fi
    
    # Verify Ollama is accessible
    local max_wait=30
    local wait_time=0
    print_status "Waiting for Ollama to be ready..."
    
    while ! curl -s http://localhost:11434/api/tags &> /dev/null && [ $wait_time -lt $max_wait ]; do
        sleep 2
        wait_time=$((wait_time + 2))
        echo -n "."
    done
    echo
    
    if curl -s http://localhost:11434/api/tags &> /dev/null; then
        print_success "Ollama is running and accessible"
        
        # Suggest installing a model
        print_info "Ollama is ready. You may want to install a model:"
        print_info "  ollama pull llama2"
        print_info "  ollama pull codellama"
        print_info "  ollama pull mistral"
    else
        print_warning "Ollama installed but not responding. You may need to start it manually:"
        if [[ "$DISTRO" == "macos" ]]; then
            print_info "  brew services start ollama"
        else
            print_info "  sudo systemctl start ollama"
        fi
        print_info "  or run: ollama serve"
    fi
}

# System requirements check
check_system_requirements() {
    print_step "Checking system requirements..."
    
    # Check available disk space (need at least 5GB)
    local available_space
    if [[ "$OS" == "macos" ]]; then
        available_space=$(df -g . | awk 'NR==2 {print $4}')
    else
        available_space=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
    fi
    
    if [[ $available_space -lt 5 ]]; then
        print_error "Insufficient disk space. Need at least 5GB, found ${available_space}GB"
        exit 1
    fi
    
    print_success "System requirements check passed"
}

# Complete system setup
setup_system() {
    print_step "Setting up system dependencies..."
    
    detect_os
    check_sudo
    check_system_requirements
    install_system_deps
    install_docker
    
    # Ask about optional components
    echo
    print_info "Optional components:"
    
    read -p "Install ngrok for public access? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_ngrok
    fi
    
    read -p "Install Ollama for local AI models? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_ollama
    fi
    
    print_success "System setup completed!"
}

check_docker() {
    print_status "Checking Docker installation..."
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        echo "Visit: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        print_error "Docker is not running. Please start Docker."
        exit 1
    fi
    
    print_success "Docker is installed and running"
}

check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        return 0  # Port is in use
    else
        return 1  # Port is free
    fi
}

get_port_process() {
    local port=$1
    lsof -Pi :$port -sTCP:LISTEN -t 2>/dev/null
}

get_port_info() {
    local port=$1
    lsof -Pi :$port -sTCP:LISTEN 2>/dev/null
}

free_port() {
    local port=$1
    local force=${2:-false}
    
    if check_port $port; then
        local process_info=$(get_port_info $port)
        local pids=$(get_port_process $port)
        
        print_warning "Port $port is in use:"
        echo "$process_info"
        echo ""
        
        if [ "$force" = "true" ]; then
            print_status "Forcefully killing processes on port $port..."
            echo "$pids" | xargs -r kill -9
            sleep 2
        else
            echo "Options:"
            echo "1) Kill the processes using port $port"
            echo "2) Use a different port"
            echo "3) Exit and handle manually"
            read -p "Choose option (1/2/3): " choice
            
            case $choice in
                1)
                    print_status "Killing processes on port $port..."
                    echo "$pids" | xargs -r kill -9
                    sleep 2
                    if check_port $port; then
                        print_warning "Some processes may still be running. Trying SIGTERM..."
                        echo "$pids" | xargs -r kill
                        sleep 3
                    fi
                    ;;
                2)
                    return 2  # Signal to use alternative port
                    ;;
                3)
                    print_status "Exiting. Please free port $port manually and run the script again."
                    exit 0
                    ;;
                *)
                    print_error "Invalid choice. Exiting."
                    exit 1
                    ;;
            esac
        fi
        
        # Verify port is now free
        if check_port $port; then
            print_error "Failed to free port $port. Some processes may require manual intervention."
            return 1
        else
            print_success "Port $port is now free"
            return 0
        fi
    else
        print_success "Port $port is available"
        return 0
    fi
}

find_available_port() {
    local start_port=$1
    local max_attempts=10
    
    for ((i=0; i<max_attempts; i++)); do
        local test_port=$((start_port + i))
        if ! check_port $test_port; then
            echo $test_port
            return 0
        fi
    done
    
    return 1
}

check_ollama() {
    print_status "Checking for local Ollama installation..."
    
    # Check if Ollama is installed
    if command -v ollama &> /dev/null; then
        print_success "Ollama is installed locally"
        
        # Check if Ollama is running
        if curl -s http://localhost:11434/api/tags &> /dev/null; then
            print_success "Ollama is running on localhost:11434"
            return 0
        else
            print_warning "Ollama is installed but not running"
            print_status "Starting Ollama service..."
            
            # Try to start Ollama
            if command -v brew &> /dev/null && brew services list | grep -q ollama; then
                brew services start ollama
                sleep 3
            else
                print_status "Please start Ollama manually: 'ollama serve'"
                read -p "Press Enter after starting Ollama..."
            fi
            
            # Check again
            if curl -s http://localhost:11434/api/tags &> /dev/null; then
                print_success "Ollama is now running"
                return 0
            else
                print_error "Failed to start Ollama. Please start it manually."
                return 1
            fi
        fi
    else
        print_warning "Ollama is not installed locally"
        return 1
    fi
}

check_ngrok() {
    if command -v ngrok &> /dev/null; then
        print_success "ngrok is installed"
        return 0
    else
        print_warning "ngrok is not installed"
        return 1
    fi
}

install_ngrok() {
    print_status "Installing ngrok..."
    
    # Detect OS
    OS=$(uname -s)
    case $OS in
        Darwin)
            if command -v brew &> /dev/null; then
                brew install ngrok/ngrok/ngrok
            else
                print_error "Homebrew not found. Please install ngrok manually from https://ngrok.com/download"
                exit 1
            fi
            ;;
        Linux)
            # Download and install ngrok for Linux
            curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
            echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list
            sudo apt update && sudo apt install ngrok
            ;;
        *)
            print_error "Unsupported OS. Please install ngrok manually from https://ngrok.com/download"
            exit 1
            ;;
    esac
    
    print_success "ngrok installed successfully"
}

setup_searxng() {
    print_status "Setting up SearXNG search engine..."
    
    # Check and handle port conflicts for SearXNG
    print_status "Checking SearXNG port availability..."
    if ! free_port $SEARXNG_PORT; then
        if [ $? -eq 2 ]; then
            # User chose to use alternative port
            local alt_port=$(find_available_port $((SEARXNG_PORT + 1)))
            if [ -n "$alt_port" ]; then
                print_success "Using alternative port for SearXNG: $alt_port"
                SEARXNG_PORT=$alt_port
            else
                print_error "Could not find an available port for SearXNG. Please free port $SEARXNG_PORT manually."
                exit 1
            fi
        fi
    fi
    
    # Stop and remove existing SearXNG container if it exists
    if docker ps -a --format 'table {{.Names}}' | grep -q "^${SEARXNG_CONTAINER}$"; then
        print_status "Stopping existing SearXNG container..."
        docker stop $SEARXNG_CONTAINER
        docker rm $SEARXNG_CONTAINER
    fi
    
    # Create volume if it doesn't exist
    if ! docker volume ls | grep -q $SEARXNG_VOLUME; then
        print_status "Creating Docker volume for SearXNG config..."
        docker volume create $SEARXNG_VOLUME
    fi
    
    # Pull the latest SearXNG image
    print_status "Pulling SearXNG Docker image..."
    docker pull searxng/searxng:latest
    
    # Generate secret key for SearXNG
    local SEARXNG_SECRET=$(openssl rand -hex 32 2>/dev/null || echo "fallback-secret-key-$(date +%s)")
    
    # Run SearXNG container
    print_status "Starting SearXNG container..."
    docker run -d \
        --name $SEARXNG_CONTAINER \
        -p $SEARXNG_PORT:8080 \
        -v $SEARXNG_VOLUME:/etc/searxng \
        -e SEARXNG_BASE_URL=http://localhost:$SEARXNG_PORT/ \
        -e SEARXNG_SECRET_KEY=$SEARXNG_SECRET \
        --restart unless-stopped \
        searxng/searxng:latest
    
    # Wait for SearXNG to be ready
    print_status "Waiting for SearXNG to start..."
    sleep 15
    
    # Check if SearXNG container is running
    if docker ps --format 'table {{.Names}}' | grep -q "^${SEARXNG_CONTAINER}$"; then
        print_success "SearXNG is running successfully!"
        print_success "SearXNG available at: http://localhost:$SEARXNG_PORT"
    else
        print_error "Failed to start SearXNG container"
        docker logs $SEARXNG_CONTAINER
        exit 1
    fi
}

setup_openwebui() {
    print_status "Setting up OpenWebUI with search integration..."
    
    # Setup SearXNG first
    setup_searxng
    
    # Check for local Ollama and determine configuration
    local OLLAMA_HOST=""
    local NETWORK_ARGS=""
    local ACTUAL_PORT=$OPENWEBUI_PORT
    
    if check_ollama; then
        print_status "Configuring OpenWebUI to use local Ollama..."
        # For macOS/Linux, use host.docker.internal to access host services
        if [[ "$OSTYPE" == "darwin"* ]]; then
            OLLAMA_HOST="host.docker.internal:11434"
        else
            # For Linux, use host network mode
            NETWORK_ARGS="--network=host"
            OLLAMA_HOST="localhost:11434"
        fi
        print_success "Will connect to Ollama at: $OLLAMA_HOST"
    else
        print_warning "Local Ollama not detected. OpenWebUI will run without Ollama integration."
        print_status "You can configure Ollama connection later in OpenWebUI settings."
    fi
    
    # Check and handle port conflicts (only if not using host network)
    if [ -z "$NETWORK_ARGS" ]; then
        print_status "Checking OpenWebUI port availability..."
        if ! free_port $OPENWEBUI_PORT; then
            if [ $? -eq 2 ]; then
                # User chose to use alternative port
                local alt_port=$(find_available_port $((OPENWEBUI_PORT + 1)))
                if [ -n "$alt_port" ]; then
                    print_success "Using alternative port: $alt_port"
                    ACTUAL_PORT=$alt_port
                else
                    print_error "Could not find an available port. Please free port $OPENWEBUI_PORT manually."
                    exit 1
                fi
            fi
        fi
    fi
    
    # Stop and remove existing container if it exists
    if docker ps -a --format 'table {{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_status "Stopping existing OpenWebUI container..."
        docker stop $CONTAINER_NAME
        docker rm $CONTAINER_NAME
    fi
    
    # Create volume if it doesn't exist
    if ! docker volume ls | grep -q $VOLUME_NAME; then
        print_status "Creating Docker volume for OpenWebUI data..."
        docker volume create $VOLUME_NAME
    fi
    
    # Pull the latest OpenWebUI image
    print_status "Pulling OpenWebUI Docker image..."
    docker pull ghcr.io/open-webui/open-webui:main
    
    # Build Docker run command
    local DOCKER_CMD="docker run -d --name $CONTAINER_NAME"
    
    # Add network configuration
    if [ -n "$NETWORK_ARGS" ]; then
        DOCKER_CMD="$DOCKER_CMD $NETWORK_ARGS"
    else
        DOCKER_CMD="$DOCKER_CMD -p $ACTUAL_PORT:8080"
    fi
    
    # Add volume and environment variables
    DOCKER_CMD="$DOCKER_CMD -v $VOLUME_NAME:/app/backend/data"
    
    # Add Ollama configuration
    if [ -n "$OLLAMA_HOST" ]; then
        DOCKER_CMD="$DOCKER_CMD -e OLLAMA_BASE_URL=http://$OLLAMA_HOST"
    fi
    
    # Add SearXNG search integration
    DOCKER_CMD="$DOCKER_CMD -e ENABLE_RAG_WEB_SEARCH=true"
    DOCKER_CMD="$DOCKER_CMD -e RAG_WEB_SEARCH_ENGINE=searxng"
    if [ -z "$NETWORK_ARGS" ]; then
        # Standard networking - use localhost
        DOCKER_CMD="$DOCKER_CMD -e SEARXNG_QUERY_URL=http://host.docker.internal:$SEARXNG_PORT/search?q={query}"
    else
        # Host networking
        DOCKER_CMD="$DOCKER_CMD -e SEARXNG_QUERY_URL=http://localhost:$SEARXNG_PORT/search?q={query}"
    fi
    
    DOCKER_CMD="$DOCKER_CMD --restart unless-stopped ghcr.io/open-webui/open-webui:main"
    
    # Run OpenWebUI container
    print_status "Starting OpenWebUI container with search integration..."
    eval $DOCKER_CMD
    
    # Wait for container to be ready
    print_status "Waiting for OpenWebUI to start..."
    sleep 10
    
    # Check if container is running
    if docker ps --format 'table {{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_success "OpenWebUI is running successfully!"
        if [ -n "$NETWORK_ARGS" ]; then
            print_success "Access it locally at: http://localhost:8080"
        else
            print_success "Access it locally at: http://localhost:$ACTUAL_PORT"
        fi
        
        if [ -n "$OLLAMA_HOST" ]; then
            print_success "Connected to local Ollama at: $OLLAMA_HOST"
        fi
        
        print_success "Web search enabled via SearXNG at: http://localhost:$SEARXNG_PORT"
        
        # Update global port variable for ngrok
        OPENWEBUI_PORT=$ACTUAL_PORT
    else
        print_error "Failed to start OpenWebUI container"
        docker logs $CONTAINER_NAME
        exit 1
    fi
}

setup_ngrok_tunnel() {
    print_status "Setting up ngrok tunnel..."
    
    # Check if ngrok is authenticated
    if ! ngrok config check &> /dev/null; then
        print_warning "ngrok is not authenticated"
        echo "Please sign up at https://ngrok.com and get your authtoken"
        read -p "Enter your ngrok authtoken: " authtoken
        ngrok config add-authtoken $authtoken
    fi
    
    print_status "Starting ngrok tunnel on port $OPENWEBUI_PORT..."
    
    # Start ngrok in background with random subdomain
    nohup ngrok http $OPENWEBUI_PORT --log=stdout > ngrok.log 2>&1 &
    NGROK_PID=$!
    
    # Wait for ngrok to start
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
")
    
    if [ -n "$PUBLIC_URL" ]; then
        print_success "ngrok tunnel is active!"
        print_success "Public URL: $PUBLIC_URL"
        echo "ngrok PID: $NGROK_PID" > .ngrok_pid
        
        # Create a simple status script
        cat > check_status.sh << 'EOF'
#!/bin/bash
echo "=== OpenWebUI Status ==="
if docker ps --format 'table {{.Names}}' | grep -q "^open-webui$"; then
    echo "✅ OpenWebUI container: Running"
    echo "🏠 Local URL: http://localhost:3000"
else
    echo "❌ OpenWebUI container: Not running"
fi

if pgrep -f "ngrok http" > /dev/null; then
    echo "✅ ngrok tunnel: Active"
    PUBLIC_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | python3 -c "
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
    if [ -n "$PUBLIC_URL" ]; then
        echo "🌐 Public URL: $PUBLIC_URL"
    fi
else
    echo "❌ ngrok tunnel: Not active"
fi
EOF
        chmod +x check_status.sh
        
    else
        print_error "Failed to get ngrok public URL"
        print_status "You can check ngrok status at: http://localhost:4040"
    fi
}

cleanup() {
    print_status "Cleaning up..."
    
    # Stop ngrok if running
    if [ -f .ngrok_pid ]; then
        NGROK_PID=$(cat .ngrok_pid)
        if kill -0 $NGROK_PID 2>/dev/null; then
            kill $NGROK_PID
            rm .ngrok_pid
        fi
    fi
    
    # Stop OpenWebUI container
    if docker ps --format 'table {{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker stop $CONTAINER_NAME
    fi
    
    # Stop SearXNG container
    if docker ps --format 'table {{.Names}}' | grep -q "^${SEARXNG_CONTAINER}$"; then
        docker stop $SEARXNG_CONTAINER
    fi
    
    print_success "Cleanup completed"
}

show_help() {
    echo "🚀 OpenWebUI Complete Setup Script"
    echo ""
    echo "This script automatically installs and configures:"
    echo "  • Docker & Docker Compose"
    echo "  • OpenWebUI (AI chat interface)"
    echo "  • SearXNG (privacy-focused search engine)"
    echo "  • ngrok (public access tunnel) [optional]"
    echo "  • Ollama (local AI models) [optional]"
    echo ""
    echo "📋 Usage: $0 [OPTIONS]"
    echo ""
    echo "🔧 Options:"
    echo "  --setup-only     Setup OpenWebUI with search engine only"
    echo "  --ngrok-only     Setup ngrok tunnel (assumes OpenWebUI is running)"
    echo "  --install-deps   Install system dependencies only"
    echo "  --cleanup        Stop and cleanup all services"
    echo "  --free-ports     Force kill processes using required ports"
    echo "  --reset-db       Reset OpenWebUI database (allows new admin signup)"
    echo "  --status         Show status of all services"
    echo "  --help           Show this help message"
    echo ""
    echo "🔌 Port Management:"
    echo "  The script automatically detects port conflicts and offers options to:"
    echo "  1) Kill processes using the required ports"
    echo "  2) Use alternative ports automatically"
    echo "  3) Exit for manual resolution"
    echo ""
    echo "🗄️  Database Management:"
    echo "  If you can't create an admin account, use --reset-db for a fresh start."
    echo ""
    echo "🖥️  Supported Systems:"
    echo "  • macOS (with Homebrew)"
    echo "  • Ubuntu/Debian"
    echo "  • CentOS/RHEL/Fedora"
    echo ""
    echo "📞 Support:"
    echo "  • Documentation: README.md"
    echo "  • Issues: Check Docker and service logs"
    echo ""
}

show_status() {
    if [ -f check_status.sh ]; then
        ./check_status.sh
    else
        echo "Status script not found. Run setup first."
    fi
}

# Main execution
case "${1:-}" in
    --setup-only)
        check_docker
        setup_openwebui
        ;;
    --install-deps)
        print_step "Installing system dependencies only..."
        setup_system
        print_success "🎉 All dependencies installed successfully!"
        echo ""
        echo "📋 What was installed:"
        echo "  ✅ System packages (curl, wget, openssl)"
        if command -v docker &> /dev/null; then
            echo "  ✅ Docker ($(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1))"
        fi
        if command -v ngrok &> /dev/null; then
            echo "  ✅ ngrok ($(ngrok version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1))"
        fi
        if command -v ollama &> /dev/null; then
            echo "  ✅ Ollama ($(ollama --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "installed"))"
        fi
        echo ""
        echo "🚀 Ready to run: ./setup-openwebui.sh"
        ;;
    --ngrok-only)
        if ! check_ngrok; then
            read -p "Do you want to install ngrok? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                install_ngrok
            else
                print_error "ngrok is required for public access"
                exit 1
            fi
        fi
        setup_ngrok_tunnel
        ;;
    --cleanup)
        cleanup
        ;;
    --free-ports)
        print_status "Freeing up ports used by OpenWebUI and ngrok..."
        free_port $OPENWEBUI_PORT true
        free_port 4040 true  # ngrok web interface
        print_success "Ports freed"
        ;;
    --reset-db)
        print_status "Resetting OpenWebUI database..."
        if docker ps --format 'table {{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            print_status "Stopping OpenWebUI container..."
            docker stop $CONTAINER_NAME
        fi
        
        print_warning "This will delete all existing users, chats, and settings!"
        read -p "Are you sure you want to reset the database? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            docker run --rm -v $VOLUME_NAME:/data alpine rm -f /data/webui.db
            print_success "Database reset completed"
            print_status "Restarting OpenWebUI..."
            setup_openwebui
        else
            print_status "Database reset cancelled"
        fi
        ;;
    --status)
        show_status
        ;;
    --help)
        show_help
        ;;
    *)
        print_step "Starting complete OpenWebUI setup..."
        
        # Check if this is a fresh system
        if ! command -v docker &> /dev/null; then
            print_info "Fresh system detected. Installing all dependencies..."
            setup_system
        else
            print_info "Dependencies found. Checking versions..."
            install_docker  # This will check and upgrade if needed
            
            if ! command -v ngrok &> /dev/null; then
                read -p "Install ngrok for public access? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    install_ngrok
                fi
            fi
            
            if ! command -v ollama &> /dev/null; then
                read -p "Install Ollama for local AI models? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    install_ollama
                fi
            fi
        fi
        
        setup_openwebui
        
        if command -v ngrok &> /dev/null; then
            read -p "Setup ngrok tunnel for public access? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                setup_ngrok_tunnel
            fi
        fi
        
        print_success "🎉 Setup completed successfully!"
        echo ""
        echo "📋 Next steps:"
        echo "1. 🌐 Open http://localhost:$OPENWEBUI_PORT in your browser"
        echo "2. 👤 Create your admin account"
        echo "3. 🤖 Configure your AI models"
        echo ""
        if command -v ollama &> /dev/null; then
            echo "💡 Ollama tips:"
            echo "   • Install models: ollama pull llama2"
            echo "   • List models: ollama list"
            echo "   • Chat directly: ollama run llama2"
            echo ""
        fi
        echo "🔧 Management commands:"
        echo "   • Check status: ./setup-openwebui.sh --status"
        echo "   • Stop services: ./setup-openwebui.sh --cleanup"
        echo "   • Reset database: ./setup-openwebui.sh --reset-db"
        ;;
esac
