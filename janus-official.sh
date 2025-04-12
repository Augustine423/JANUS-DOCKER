#!/bin/bash

# Janus WebRTC Server Installation Script for Ubuntu 24.04
# Installs dependencies, builds Janus from source, sets up configs, and runs as a service

set -e

# Variables
JANUS_SRC_DIR="/tmp/janus-gateway"
JANUS_CONFIG_DIR="/etc/janus"
JANUS_INSTALL_PREFIX="/usr/local"
CMAKE_VERSION="3.31.6"
JANUS_CONFIG_COMMON="--disable-docs --enable-post-processing --enable-plugin-lua --enable-plugin-duktape --enable-json-logger"
JANUS_CONFIG_OPTS=""

# Ensure script runs with sudo
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root or with sudo."
    exit 1
fi

# Update package lists
echo "Updating package lists..."
apt-get update

# Install apt dependencies
echo "Installing apt dependencies..."
apt-get install -y --no-install-recommends \
    duktape-dev \
    libavcodec-dev \
    libavformat-dev \
    libavutil-dev \
    libcollection-dev \
    libconfig-dev \
    libevent-dev \
    libglib2.0-dev \
    libgirepository1.0-dev \
    liblua5.3-dev \
    libjansson-dev \
    libmicrohttpd-dev \
    libnanomsg-dev \
    libogg-dev \
    libopus-dev \
    libpcap-dev \
    librabbitmq-dev \
    libsofia-sip-ua-dev \
    libssl-dev \
    libcurl4-openssl-dev \
    libnice-dev \
    libsrtp2-dev \
    libusrsctp-dev \
    libwebsockets-dev \
    libtool \
    meson \
    ninja-build \
    git \
    build-essential \
    pkg-config \
    autoconf \
    automake \
    python3 \
    python3-pip

# Install CMake 3.31.6
echo "Installing CMake $CMAKE_VERSION..."
wget https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.sh -O /tmp/cmake-install.sh
chmod +x /tmp/cmake-install.sh
/tmp/cmake-install.sh --skip-license --prefix=/usr/local
rm /tmp/cmake-install.sh

# Install dependencies from source
echo "Building dependencies from source..."

# libnice
echo "Building libnice..."
git clone https://gitlab.freedesktop.org/libnice/libnice.git /tmp/libnice
cd /tmp/libnice
meson setup -Dprefix=/usr -Dlibdir=lib -Dc_args="-O0 -Wno-cast-align" \
    -Dexamples=disabled \
    -Dgtk_doc=disabled \
    -Dgstreamer=disabled \
    -Dgupnp=disabled \
    -Dtests=disabled \
    build
ninja -C build
ninja -C build install
cd -
rm -rf /tmp/libnice

# libsrtp
echo "Building libsrtp..."
git clone https://github.com/cisco/libsrtp.git /tmp/libsrtp
cd /tmp/libsrtp
git checkout v2.7.0
./configure --prefix=/usr CFLAGS="-O0" \
    --disable-pcap \
    --enable-openssl
make -j$(nproc) shared_library
make install
cd -
rm -rf /tmp/libsrtp

# usrsctp
echo "Building usrsctp..."
git clone https://github.com/sctplab/usrsctp.git /tmp/usrsctp
cd /tmp/usrsctp
./bootstrap
./configure --prefix=/usr CFLAGS="-O0" \
    --disable-debug \
    --disable-inet \
    --disable-inet6 \
    --disable-programs \
    --disable-static \
    --enable-shared
make -j$(nproc)
make install
cd -
rm -rf /tmp/usrsctp

# libwebsockets
echo "Building libwebsockets..."
git clone https://github.com/warmcat/libwebsockets.git /tmp/libwebsockets
cd /tmp/libwebsockets
git checkout v4.3-stable
mkdir build && cd build
cmake -DCMAKE_INSTALL_PREFIX:PATH=/usr -DCMAKE_BUILD_TYPE=RELEASE -DCMAKE_C_FLAGS="-O0" \
    -DLWS_ROLE_RAW_FILE=OFF \
    -DLWS_WITH_HTTP2=OFF \
    -DLWS_WITHOUT_EXTENSIONS=OFF \
    -DLWS_WITHOUT_TESTAPPS=ON \
    -DLWS_WITHOUT_TEST_CLIENT=ON \
    -DLWS_WITHOUT_TEST_PING=ON \
    -DLWS_WITHOUT_TEST_SERVER=ON \
    -DLWS_WITH_STATIC=OFF \
    ..
make -j$(nproc)
make install
cd ../..
rm -rf /tmp/libwebsockets

# paho.mqtt.c
echo "Building paho.mqtt.c..."
git clone https://github.com/eclipse/paho.mqtt.c.git /tmp/paho.mqtt.c
cd /tmp/paho.mqtt.c
git checkout v1.3.14
mkdir build.paho && cd build.paho
cmake -DCMAKE_INSTALL_PREFIX:PATH=/usr -DCMAKE_BUILD_TYPE=RELEASE -DCMAKE_C_FLAGS="-O0" \
    -DPAHO_HIGH_PERFORMANCE=TRUE \
    -DPAHO_BUILD_DOCUMENTATION=FALSE \
    -DPAHO_BUILD_SAMPLES=FALSE \
    -DPAHO_BUILD_SHARED=TRUE \
    -DPAHO_BUILD_STATIC=FALSE \
    -DPAHO_ENABLE_TESTING=FALSE \
    -DPAHO_WITH_SSL=TRUE \
    ..
make -j$(nproc)
make install
cd ../..
rm -rf /tmp/paho.mqtt.c

# Clone and build Janus
echo "Building Janus WebRTC Server..."
git clone https://github.com/meetecho/janus-gateway.git $JANUS_SRC_DIR
cd $JANUS_SRC_DIR
./autogen.sh
./configure $JANUS_CONFIG_COMMON $JANUS_CONFIG_OPTS CFLAGS="-O0"
make -j$(nproc)
make install
make configs
ldconfig
cd -
rm -rf $JANUS_SRC_DIR

# Create configuration files
echo "Setting up configuration files..."
mkdir -p $JANUS_CONFIG_DIR

# janus.jcfg
cat > $JANUS_CONFIG_DIR/janus.jcfg << 'EOF'
[general]
configs_folder = /etc/janus
plugins_folder = /usr/local/lib/janus/plugins
transports_folder = /usr/local/lib/janus/transports
events_folder = /usr/local/lib/janus/events
log_to_stdout = true
log_to_file = /var/log/janus/janus.log
debug_level = 4
debug_timestamps = true
debug_colors = true
session_timeout = 60
min_nack_queue = 0
no_media_timer = 1

[certificates]
cert_pem = /etc/janus/janus.pem
cert_key = /etc/janus/janus.key
dtls_ciphers = EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH

[media]
rtcp_mux = true
ice_lite = true
ice_tcp = false
rtp_port_range = 10000-60000
dtls_mtu = 1200
twcc_period = 100

[nat]
nice_debug = false
ice_enforce_list = eth0
stun_server = stun.l.google.com
stun_port = 19302
turn_server = 
turn_port = 3478
turn_type = udp
turn_user = 
turn_pwd = 

[plugins]
disable = 

[transports]
disable = 

[events]
disable = 
EOF

# janus.plugin.streaming.jcfg
cat > $JANUS_CONFIG_DIR/janus.plugin.streaming.jcfg << 'EOF'
[general]
enabled = true

[stream1]
type = rtp
id = 1
description = Sample RTP stream
is_private = false
secret = 
pin = 
audio = true
video = true
audioport = 5002
audiopt = 111
audiortpmap = opus/48000/2
videoport = 5004
videopt = 96
videortpmap = VP8/90000
EOF

# janus.plugin.videoroom.jcfg
cat > $JANUS_CONFIG_DIR/janus.plugin.videoroom.jcfg << 'EOF'
[general]
enabled = true
admin_key = supersecret

[room-1]
description = Sample Video Room
is_private = false
secret = 
pin = 
require_pvtid = false
publishers = 6
bitrate = 128000
fir_freq = 10
audiocodec = opus
videocodec = vp8
record = false
notify_joining = true
EOF

# janus.transport.pfunix.jcfg
cat > $JANUS_CONFIG_DIR/janus.transport.pfunix.jcfg << 'EOF'
[general]
enabled = true
json = indented
base_path = /tmp/janus
admin_base_path = /tmp/janus-admin
EOF

# Set permissions
echo "Setting configuration permissions..."
chown -R ubuntu:ubuntu $JANUS_CONFIG_DIR
chmod -R 644 $JANUS_CONFIG_DIR/*
mkdir -p /var/log/janus
chown ubuntu:ubuntu /var/log/janus

# Create systemd service
echo "Creating Janus systemd service..."
cat > /etc/systemd/system/janus.service << 'EOF'
[Unit]
Description=Janus WebRTC Server
After=network.target

[Service]
ExecStart=/usr/local/bin/janus --configs-folder=/etc/janus
Restart=always
User=ubuntu
Group=ubuntu

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
echo "Starting Janus service..."
systemctl daemon-reload
systemctl enable janus
systemctl start janus

# Verify installation
echo "Verifying Janus installation..."
if systemctl is-active --quiet janus; then
    echo "Janus WebRTC Server is running successfully."
else
    echo "Failed to start Janus. Check logs with 'journalctl -u janus'."
    exit 1
fi

# Clean up
echo "Cleaning up..."
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "Janus installation completed. Access the admin API at http://<EC2_IP>:8088/janus/info"