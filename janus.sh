#!/bin/bash

# Update and upgrade the system
sudo apt update && sudo apt upgrade -y

# Install required dependencies
sudo apt install -y libmicrohttpd-dev libjansson-dev libssl-dev libsrtp2-dev \
libsofia-sip-ua-dev libglib2.0-dev libopus-dev libogg-dev libcurl4-openssl-dev \
liblua5.3-dev libconfig-dev pkg-config git cmake make gcc g++ libnice-dev \
libwebsockets-dev gengetopt automake libtool curl

# Install usrsctp
git clone https://github.com/sctplab/usrsctp.git
cd usrsctp
./bootstrap
./configure
make && sudo make install
sudo ldconfig
cd ..

# Update package list again
sudo apt update

# Install rnnoise
git clone https://github.com/xiph/rnnoise.git
cd rnnoise
./autogen.sh
./configure
make
sudo make install
sudo ldconfig
cd ..

# Clone and install Janus Gateway
git clone https://github.com/meetecho/janus-gateway.git
cd janus-gateway
sh autogen.sh
./configure --prefix=/opt/janus --enable-rnnoise --enable-websockets
make
sudo make install
sudo make configs
cd ..

# Install Nginx
sudo apt install nginx -y

# Copy Janus HTML files to Nginx web directory
sudo cp -r /opt/janus/share/janus/html/* /var/www/html/

# Detect public IP address
PUBLIC_IP=$(curl -s ifconfig.me)

# Create log and logger directories and set permissions
sudo mkdir -p /var/log/janus /opt/janus/lib/janus/loggers
sudo chown janus:janus /var/log/janus /opt/janus/lib/janus/loggers
sudo chmod 750 /var/log/janus /opt/janus/lib/janus/loggers

# Create janus.plugin.streaming.jcfg configuration file (RTP only)
STREAMING_CONFIG="/opt/janus/etc/janus/janus.plugin.streaming.jcfg"
sudo mkdir -p /opt/janus/etc/janus
sudo bash -c "cat > $STREAMING_CONFIG" << EOL
general: {
    rtp_port_range = "20000-40000"
    events = true
}

multi-video-stream: {
    type = "rtp"
    id = 1
    description = "4 Video Streams from External Source"
    audio = false
    media = (
        {
            type = "video"
            mid = "v1"
            label = "Video Stream 1"
            port = 5004
            pt = 96
            codec = "vp8"
        },
        {
            type = "video"
            mid = "v2"
            label = "Video Stream 2"
            port = 5006
            pt = 96
            codec = "vp8"
        },
        {
            type = "video"
            mid = "v3"
            label = "Video Stream 3"
            port = 5008
            pt = 96
            codec = "vp8"
        },
        {
            type = "video"
            mid = "v4"
            label = "Video Stream 4"
            port = 5010
            pt = 96
            codec = "vp8"
        }
    )
    secret = "your-secret"
}
EOL

# Update janus.jcfg to enable WebSocket and debug mode
JANUS_CONFIG="/opt/janus/etc/janus/janus.jcfg"
sudo bash -c "cat > $JANUS_CONFIG" << EOL
general: {
    configs_folder = "/opt/janus/etc/janus"
    plugins_folder = "/opt/janus/lib/janus/plugins"
    log_to_stdout = true
    log_to_file = "/var/log/janus/janus.log"
    debug_level = 4
}

nat: {
    stun_server = "stun.l.google.com"
    stun_port = 19302
    nat_1_1_mapping = "$PUBLIC_IP"
}

transports: {
    http: {
        enabled = true
        port = 8088
    }
    websocket: {
        enabled = true
        port = 8188
    }
}
EOL

# Set proper ownership and permissions for config files
sudo chown -R janus:janus /opt/janus/etc/janus
sudo chmod -R 640 /opt/janus/etc/janus

# Create systemd service file for Janus
SYSTEMD_SERVICE="/etc/systemd/system/janus.service"
sudo bash -c "cat > $SYSTEMD_SERVICE" << EOL
[Unit]
Description=Janus WebRTC Server
After=network.target

[Service]
ExecStart=/opt/janus/bin/janus
Restart=always
RestartSec=5
User=janus
Group=janus
WorkingDirectory=/opt/janus
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOL

# Create janus user and group if they don’t exist
sudo groupadd -r janus || true
sudo useradd -r -g janus -d /opt/janus -s /sbin/nologin janus || true
sudo chown -R janus:janus /opt/janus

# Reload systemd, enable, and start Janus service
sudo systemctl daemon-reload
sudo systemctl enable janus.service
sudo systemctl restart janus.service

# Wait briefly and check status
sleep 2
sudo systemctl status janus.service

# Echo connection instructions with detected public IP
echo "Sender commands for 4 video streams:"
echo "Stream 1: ffmpeg -f dshow -i video=\"USB2.0 HD UVC WebCam\" -c:v libvpx -b:v 500k -deadline realtime -f rtp rtp://$PUBLIC_IP:5004"
echo "Stream 2: ffmpeg -f dshow -i video=\"USB2.0 HD UVC WebCam\" -c:v libvpx -b:v 500k -deadline realtime -f rtp rtp://$PUBLIC_IP:5006"
echo "Stream 3: ffmpeg -f dshow -i video=\"USB2.0 HD UVC WebCam\" -c:v libvpx -b:v 500k -deadline realtime -f rtp rtp://$PUBLIC_IP:5008"
echo "Stream 4: ffmpeg -f dshow -i video=\"USB2.0 HD UVC WebCam\" -c:v libvpx -b:v 500k -deadline realtime -f rtp rtp://$PUBLIC_IP:5010"
echo "For Janus server info: http://$PUBLIC_IP:8088/janus/info"
echo "Janus demo page to view 4 video streams: http://$PUBLIC_IP/demos/streaming.html"
echo "WebSocket URL for clients: ws://$PUBLIC_IP:8188"