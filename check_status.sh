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
