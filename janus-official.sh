#!/bin/bash

# Exit on any error
set -e

# Auto-detect public IP
PUBLIC_IP=$(curl -s https://api.ipify.org || echo "127.0.0.1")
INSTALL_DIR="/home/ubuntu"

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
    libspeexdsp-dev

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
./configure --prefix=/opt/janus \
    --enable-websockets \
    --enable-libsrtp2
make
sudo make install
sudo make configs

# Step 5.5: Copy custom Janus configurations
echo "Copying custom Janus configurations..."
if [ -d "$INSTALL_DIR/janus_configuration" ]; then
    sudo cp -r $INSTALL_DIR/JANUS-DOCKER/janus_configuration/* /opt/janus/etc/janus/
    echo "Custom configurations copied successfully."
else
    echo "Warning: janus_configuration directory not found in $INSTALL_DIR"
fi

# Step 6: Configure Janus to use Google STUN
echo "Configuring Janus with Google STUN..."
sudo sed -i '/\[nat\]/,/^\[/ s/stun_server = .*/stun_server = stun.l.google.com/' /opt/janus/etc/janus/janus.jcfg
sudo sed -i '/\[nat\]/,/^\[/ s/stun_port = .*/stun_port = 19302/' /opt/janus/etc/janus/janus.jcfg

# Step 7: Copy demo files to nginx web root
echo "Copying demo files to /var/www/html..."
sudo cp -r /opt/janus/share/janus/html/* /var/www/html/

# Step 8: Verify installation
echo "Verifying Janus installation..."
/opt/janus/bin/janus --version

# Step 9: Test Janus with NAT setting
echo "Starting Janus with NAT 1:1 mapping ($PUBLIC_IP)..."
/opt/janus/bin/janus --nat-1-1=$PUBLIC_IP -d 5 &

# Wait a few seconds for Janus to start
sleep 5



# Step 11: Create systemd service for Janus
echo "Creating systemd service for Janus..."
cat <<EOF | sudo tee /etc/systemd/system/janus.service > /dev/null
[Unit]
Description=Janus WebRTC Gateway
After=network.target

[Service]
ExecStart=/opt/janus/bin/janus --nat-1-1=$PUBLIC_IP
Restart=always
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable janus
sudo systemctl start janus