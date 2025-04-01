#!/bin/bash

# Exit on any error
set -e

# Variables
PUBLIC_IP="13.213.46.108"
INSTALL_DIR="/home/ubuntu"
CONFIG_BACKUP_DIR="/home/ubuntu/janus-config-backup"  # Adjust this to your backup location
JANUS_INSTALL_DIR="/opt/janus"

# Step 1: Update the system
echo "Updating system..."
sudo apt update && sudo apt upgrade -y

# Step 2: Install dependencies
echo "Installing dependencies..."
sudo apt install -y \
    build-essential \
    git \
    cmake \
    pkg-config \
    automake \
    libtool \
    gengetopt \
    make \
    gcc \
    g++ \
    nginx \
    libmicrohttpd-dev \
    libjansson-dev \
    libssl-dev \
    libsrtp2-dev \
    libsofia-sip-ua-dev \
    libglib2.0-dev \
    libopus-dev \
    libogg-dev \
    libcurl4-openssl-dev \
    liblua5.3-dev \
    libconfig-dev \
    libnice-dev \
    libwebsockets-dev \
    libspeexdsp-dev \
    socat  # For Unix Sockets testing

# Step 3: Install usrsctp
echo "Installing usrsctp..."
cd $INSTALL_DIR
if [ ! -d "usrsctp" ]; then
    git clone https://github.com/sctplab/usrsctp.git || { echo "Failed to clone usrsctp"; exit 1; }
fi
cd usrsctp
./bootstrap
./configure
make && sudo make install
sudo ldconfig
cd ..

# Step 4: Install libsrtp from source
echo "Installing libsrtp..."
wget https://github.com/cisco/libsrtp/archive/v2.5.0.tar.gz -O libsrtp-2.5.0.tar.gz || { echo "Failed to download libsrtp"; exit 1; }
tar xfv libsrtp-2.5.0.tar.gz
cd libsrtp-2.5.0
./configure --prefix=/usr
make && sudo make install
sudo ldconfig
cd ..

# Step 5: Install Janus Gateway
echo "Installing Janus Gateway..."
if [ ! -d "janus-gateway" ]; then
    git clone https://github.com/meetecho/janus-gateway.git || { echo "Failed to clone janus-gateway"; exit 1; }
fi
cd janus-gateway
sh autogen.sh
./configure --prefix=$JANUS_INSTALL_DIR \
    --enable-websockets \
    --enable-libsrtp2
make
sudo make install
sudo make configs

# Step 6: Pull and apply backup configuration files
echo "Applying backup configuration files from $CONFIG_BACKUP_DIR..."
if [ -d "$CONFIG_BACKUP_DIR" ]; then
    sudo cp "$CONFIG_BACKUP_DIR/janus.jcfg" "$JANUS_INSTALL_DIR/etc/janus/janus.jcfg" || { echo "Failed to copy janus.jcfg"; exit 1; }
    sudo cp "$CONFIG_BACKUP_DIR/janus.plugin.streaming.jcfg" "$JANUS_INSTALL_DIR/etc/janus/janus.plugin.streaming.jcfg" || { echo "Failed to copy janus.plugin.streaming.jcfg"; exit 1; }
    sudo cp "$CONFIG_BACKUP_DIR/janus.plugin.videoroom.jcfg" "$JANUS_INSTALL_DIR/etc/janus/janus.plugin.videoroom.jcfg" || { echo "Failed to copy janus.plugin.videoroom.jcfg"; exit 1; }
    sudo cp "$CONFIG_BACKUP_DIR/janus.transport.pfunix.jcfg" "$JANUS_INSTALL_DIR/etc/janus/janus.transport.pfunix.jcfg" || { echo "Failed to copy janus.transport.pfunix.jcfg"; exit 1; }
else
    echo "Warning: Backup directory $CONFIG_BACKUP_DIR not found. Using default configs."
fi

# Step 7: Set permissions for config files
echo "Setting permissions for config files..."
sudo chown ubuntu:ubuntu $JANUS_INSTALL_DIR/etc/janus/*
sudo chmod 644 $JANUS_INSTALL_DIR/etc/janus/*

# Step 8: Copy demo files to nginx web root
echo "Copying demo files to /var/www/html..."
sudo cp -r $JANUS_INSTALL_DIR/share/janus/html/* /var/www/html/
sudo chown -R www-data:www-data /var/www/html/

# Step 9: Create systemd service file
echo "Creating Janus systemd service..."
sudo bash -c "cat > /etc/systemd/system/janus.service << EOL
[Unit]
Description=Janus WebRTC Server
After=network.target

[Service]
Type=simple
ExecStart=$JANUS_INSTALL_DIR/bin/janus --nat-1-1=$PUBLIC_IP -d 5 --log-file=/var/log/janus.log
WorkingDirectory=$JANUS_INSTALL_DIR
User=ubuntu
Group=ubuntu
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOL"

# Step 10: Set up log file
echo "Setting up log file..."
sudo touch /var/log/janus.log
sudo chown ubuntu:ubuntu /var/log/janus.log
sudo chmod 644 /var/log/janus.log

# Step 11: Reload systemd and enable/start service
echo "Reloading systemd and enabling Janus service..."
sudo systemctl daemon-reload
sudo systemctl enable janus.service
sudo systemctl start janus.service

# Step 12: Verify service status
echo "Checking Janus service status..."
sleep 5  # Give it a moment to start
sudo systemctl status janus.service

# Step 13: Basic connectivity test
echo "Testing HTTP endpoint locally..."
curl http://localhost:8088/janus || echo "HTTP test failed - check security group or network"

# Step 14: EC2 security group instructions
echo "---------------------------------------------------"
echo "EC2 Security Group Setup (do this manually in AWS console):"
echo "1. Go to EC2 > Security Groups > Select your instance’s group"
echo "2. Add inbound rules:"
echo "   - TCP 8088 (HTTP): Source 0.0.0.0/0"
echo "   - TCP 8188 (WebSockets): Source 0.0.0.0/0"
echo "   - UDP 5002-5044 (RTP for streaming): Source 0.0.0.0/0"
echo "   - UDP 20000-40000 (WebRTC media): Source 0.0.0.0/0"
echo "3. Save changes"
echo "---------------------------------------------------"
echo "ICE Server Info:"
echo "- Using Google STUN: stun.l.google.com:19302 (from janus.jcfg)"
echo "- If ICE fails, consider adding a Coturn TURN server."
echo "---------------------------------------------------"

echo "Janus installation and service setup complete!"
echo "Source directory: $INSTALL_DIR/janus-gateway"
echo "Configuration files: $JANUS_INSTALL_DIR/etc/janus/"
echo "Logs: /var/log/janus.log"
echo "Test externally: http://$PUBLIC_IP:8088/janus or ws://$PUBLIC_IP:8188"