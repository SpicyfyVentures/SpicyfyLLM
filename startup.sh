#!/bin/bash

# SpicyfyLLM - Startup Script
# Automatically starts OpenWebUI, SearXNG, and ngrok on system boot

# Change to the project directory
cd "$(dirname "$0")"

# Wait for Docker to be ready
echo "Waiting for Docker to be ready..."
while ! docker info >/dev/null 2>&1; do
    sleep 2
done

# Start Docker containers
echo "Starting OpenWebUI and SearXNG..."
docker-compose up -d

# Wait for services to be ready
echo "Waiting for services to start..."
sleep 10

# Start ngrok if configured
if [ -f "/Users/vamsikandikonda/Library/Application Support/ngrok/ngrok.yml" ]; then
    echo "Starting ngrok tunnel..."
    nohup ngrok start webui > ngrok.log 2>&1 &
    echo $! > .ngrok_pid
    echo "ngrok started with PID $(cat .ngrok_pid)"
else
    echo "No ngrok configuration found, skipping tunnel setup"
fi

echo "All services started successfully!"
echo "OpenWebUI: http://localhost:3000"
echo "SearXNG: http://localhost:8081"

# Check status
./check_status.sh
