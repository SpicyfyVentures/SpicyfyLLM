# 🚀 SpicyfyLLM - OpenWebUI Complete Setup

A foolproof, one-command setup for OpenWebUI with all dependencies. Works on fresh machines with just the OS installed.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-blue.svg)](https://github.com/vamsikandikonda/SpicyfyLLM)
[![Docker](https://img.shields.io/badge/docker-required-blue.svg)](https://docker.com)

## 📋 Table of Contents

- [🚀 Quick Start (Fresh Machine)](#-quick-start-fresh-machine)
- [📦 What Gets Installed](#-what-gets-installed)
- [🖥️ Supported Systems](#️-supported-systems)
- [⚙️ System Requirements](#️-system-requirements)
- [🔧 Installation Options](#-installation-options)
- [🎛️ Management Commands](#️-management-commands)
- [⚙️ Configuration](#️-configuration)
- [🔍 Troubleshooting](#-troubleshooting)
- [🤝 Contributing](#-contributing)
- [📄 License](#-license)

## 🚀 Quick Start (Fresh Machine)

**One command to rule them all:**

```bash
# Download and run the setup script
curl -fsSL https://raw.githubusercontent.com/vamsikandikonda/SpicyfyLLM/main/setup-openwebui.sh | bash
```

**Or clone and run locally:**

```bash
git clone https://github.com/vamsikandikonda/SpicyfyLLM.git
cd SpicyfyLLM
chmod +x setup-openwebui.sh
./setup-openwebui.sh
```

That's it! The script will:
1. ✅ Install Docker (if not present)
2. ✅ Install Ollama (optional, with user prompt)
3. ✅ Set up OpenWebUI with SearXNG search integration
4. ✅ Configure ngrok for public access (optional)
5. ✅ Handle all port conflicts automatically
6. ✅ Start all services and provide access URLs

## 📦 What Gets Installed

| Component | Purpose | Port | Auto-Installed |
|-----------|---------|------|----------------|
| **OpenWebUI** | Main AI chat interface | 3000 | ✅ |
| **SearXNG** | Privacy-focused search engine | 8081 | ✅ |
| **Docker** | Container runtime | - | ✅ |
| **Ollama** | Local AI models (optional) | 11434 | 🔄 (with prompt) |
| **ngrok** | Public tunnel (optional) | - | 🔄 (with prompt) |

## 🖥️ Supported Systems

- ✅ **macOS** (Intel & Apple Silicon)
- ✅ **Ubuntu** (18.04+)
- ✅ **Debian** (10+)
- ✅ **CentOS/RHEL** (7+)
- ✅ **Fedora** (30+)

## ⚙️ System Requirements

- **RAM**: 4GB minimum, 8GB recommended
- **Storage**: 10GB free space
- **Network**: Internet connection for downloads
- **Permissions**: sudo access for system package installation

## 🔧 Installation Options

### Full Setup (Recommended)
```bash
./setup-openwebui.sh
```
Installs everything with interactive prompts for optional components.

### Dependencies Only
```bash
./setup-openwebui.sh --install-deps
```
Only installs system dependencies (Docker, etc.) without starting services.

### Setup Only (Skip Dependencies)
```bash
./setup-openwebui.sh --setup-only
```
Assumes dependencies are installed, only sets up and starts OpenWebUI.

### Cleanup
```bash
./setup-openwebui.sh --cleanup
```
Stops and removes all containers and data.

## 🎛️ Management Commands

### Check Status
```bash
./check_status.sh
```
Shows status of all running services and their URLs.

### Start Services
```bash
docker-compose up -d
```

### Stop Services
```bash
docker-compose down
```

### View Logs
```bash
# OpenWebUI logs
docker logs open-webui

# SearXNG logs
docker logs searxng
```

### Update Services
```bash
# Pull latest images
docker-compose pull

# Restart with new images
docker-compose up -d
```

## ⚙️ Configuration

### Environment Variables

Create a `.env` file in the project directory to customize settings:

```bash
# OpenWebUI Configuration
OPENWEBUI_PORT=3000
WEBUI_SECRET_KEY=your-secret-key-here

# SearXNG Configuration
SEARXNG_PORT=8081
SEARXNG_SECRET_KEY=your-searxng-secret

# Ollama Configuration (if using local Ollama)
OLLAMA_BASE_URL=http://host.docker.internal:11434

# ngrok Configuration (optional)
NGROK_AUTHTOKEN=your-ngrok-token
NGROK_DOMAIN=your-custom-domain.ngrok.io
```

### Setting Up Custom ngrok Domain

By default, ngrok generates random URLs like `https://abc123-def456.ngrok.io`. To use a custom domain:

#### Option 1: Using ngrok Configuration File

1. **Get a paid ngrok plan** that supports custom domains
2. **Reserve your domain** in the [ngrok dashboard](https://dashboard.ngrok.com/cloud-edge/domains)
3. **Create ngrok config file**:
   ```bash
   ngrok config edit
   ```
4. **Add your tunnel configuration**:
   ```yaml
   version: "3"
   agent:
     authtoken: your-auth-token-here
   tunnels:
     webui:
       proto: http
       addr: 3000
       domain: your-custom-domain.ngrok.io
   ```
5. **Start with named tunnel**:
   ```bash
   ngrok start webui
   ```

#### Option 2: Using Command Line

```bash
# For paid accounts with reserved domains
ngrok http 3000 --domain=your-custom-domain.ngrok.io

# For paid accounts with custom domains
ngrok http 3000 --domain=yourdomain.com
```

#### Option 3: Modify Setup Script

Edit `setup-openwebui.sh` and change the ngrok command:
```bash
# Find this line:
nohup ngrok http $OPENWEBUI_PORT --log=stdout > ngrok.log 2>&1 &

# Replace with:
nohup ngrok http $OPENWEBUI_PORT --domain=your-domain.ngrok.io --log=stdout > ngrok.log 2>&1 &
```

**Note**: Custom domains require a paid ngrok subscription. Free accounts get random subdomains.

### Custom Ports

If default ports are in use, the script will automatically:
1. 🔍 Detect port conflicts
2. 💭 Offer to kill conflicting processes
3. 🔄 Suggest alternative ports
4. ✅ Update configuration accordingly

### Search Engine Integration

OpenWebUI automatically integrates with SearXNG for web search capabilities:
- **SearXNG URL**: `http://localhost:8081`
- **Search Integration**: Automatic via OpenWebUI settings
- **Privacy**: No tracking, no data collection

## 🔍 Troubleshooting

### Common Issues

**Docker not starting:**
```bash
# Check Docker status
sudo systemctl status docker

# Start Docker
sudo systemctl start docker
```

**Port conflicts:**
```bash
# Check what's using a port
lsof -i :3000

# Kill process using port
sudo kill -9 <PID>
```

**Permission denied:**
```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Logout and login again, or run:
newgrp docker
```

**Ollama connection issues:**
```bash
# Check if Ollama is running
curl http://localhost:11434/api/version

# Start Ollama
ollama serve
```

### Debug Mode

Run the script with debug output:
```bash
DEBUG=1 ./setup-openwebui.sh
```

### Reset Everything

Complete reset (removes all data):
```bash
./setup-openwebui.sh --cleanup
docker system prune -af
docker volume prune -f
```

## 🌐 Access URLs

After successful installation:

- **OpenWebUI**: http://localhost:3000
- **SearXNG**: http://localhost:8081
- **ngrok Public URL**: Displayed in terminal (if enabled)

## 🔒 Security Considerations

- **Local by default**: All services run locally unless ngrok is enabled
- **No data collection**: SearXNG respects privacy
- **Secure secrets**: Generate strong secret keys for production
- **Firewall**: Consider firewall rules for production deployments

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature-name`
3. Make your changes
4. Test on multiple platforms
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [OpenWebUI](https://github.com/open-webui/open-webui) - Amazing AI chat interface
- [SearXNG](https://github.com/searxng/searxng) - Privacy-respecting search engine
- [Ollama](https://ollama.ai/) - Local AI model runtime
- [ngrok](https://ngrok.com/) - Secure tunneling service

---

**Made with ❤️ for the AI community**

*If you find this useful, please ⭐ star the repository!*
