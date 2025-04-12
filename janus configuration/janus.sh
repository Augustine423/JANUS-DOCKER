#!/bin/bash

# Exit on any error
set -e

# Variables
PUBLIC_IP="18.143.74.115"
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

# Step 10: Basic connectivity test
echo "Testing HTTP endpoint locally..."
curl http://localhost:8088/janus || echo "HTTP test failed - check security group or network"

# Step 11: EC2 security group instructions
echo "---------------------------------------------------"
echo "EC2 Security Group Setup (do this manually in AWS console):"
echo "1. Go to EC2 > Security Groups > Select your instance’s group"
echo "2. Add inbound rules:"
echo "   - TCP 8088 (HTTP): Source 0.0.0.0/0"
echo "   - TCP 8188 (WebSockets): Source 0.0.0.0/0"
echo "   - UDP 20000-40000 (RTP): Source 0.0.0.0/0"
echo "3. Save changes"
echo "---------------------------------------------------"
echo "ICE Server Info:"
echo "- Using Google STUN: stun.l.google.com:19302"
echo "- If ICE fails (e.g., symmetric NAT), consider adding Coturn TURN server later."
echo "---------------------------------------------------"

echo "Janus installation complete!"
echo "Source directory: $INSTALL_DIR/janus-gateway"
echo "Configuration files: /opt/janus/etc/janus/"
echo "Test externally: http://$PUBLIC_IP:8088/janus or ws://$PUBLIC_IP:8188"
