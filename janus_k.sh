#!/bin/bash

# Exit on any error
set -e

# Auto-detect public IP of EC2
PUBLIC_IP=$(curl -s https://api.ipify.org || echo "127.0.0.1")
INSTALL_DIR="/home/ubuntu"

# Function to check if a port is in use
check_port() {
    local port=$1
    if sudo netstat -tuln | grep -q ":${port}\b"; then
        echo "Error: Port $port is already in use."
        exit 1
    fi
}

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
    libavutil-dev \
    libavcodec-dev \
    libavformat-dev \
    ffmpeg

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
    --enable-libsrtp2 \
    --enable-post-processing \
    --enable-recordings
make
sudo make install
sudo make configs

# Step 6: Ensure logger plugins folder exists and has correct permissions
echo "Ensuring logger plugins folder exists..."
sudo mkdir -p /opt/janus/lib/janus/loggers
sudo chmod 755 /opt/janus/lib/janus/loggers
sudo chown root:root /opt/janus/lib/janus/loggers

# Step 6.1: Create recordings directory and set permissions
echo "Creating recordings directory..."
sudo mkdir -p /opt/janus/recordings
sudo chmod 755 /opt/janus/recordings
sudo chown root:root /opt/janus/recordings

# Step 7: Apply custom Janus core configuration
echo "Applying custom Janus core configuration..."
cat <<EOF | sudo tee /opt/janus/etc/janus/janus.jcfg > /dev/null
general: {
        configs_folder = "/opt/janus/etc/janus"
        plugins_folder = "/opt/janus/lib/janus/plugins"
        transports_folder = "/opt/janus/lib/janus/transports"
        events_folder = "/opt/janus/lib/janus/events"
        loggers_folder = "/opt/janus/lib/janus/loggers"
        debug_level = 4
        admin_secret = "janusoverlord"
        protected_folders = [
                "/bin",
                "/boot",
                "/dev",
                "/etc",
                "/initrd",
                "/lib",
                "/lib32",
                "/lib64",
                "/proc",
                "/sbin",
                "/sys",
                "/usr",
                "/var",
                "/opt/janus/bin",
                "/opt/janus/etc",
                "/opt/janus/include",
                "/opt/janus/lib",
                "/opt/janus/lib32",
                "/opt/janus/lib64",
                "/opt/janus/sbin"
        ]
}

certificates: {
}

media: {
}

nat: {
        stun_server = "stun.l.google.com"
        stun_port = 19302
        nice_debug = false
        full_trickle = true
        ice_lite = true
        ignore_mdns = true
        nat_1_1_mapping = "auto"
}

plugins: {
}

transports: {
        disable = "libjanus_rabbitmq.so"
}

loggers: {
        disable = "libjanus_jsonlog.so"
}

events: {
}
EOF

# Step 8: Apply custom video room plugin configuration
echo "Applying custom video room plugin configuration..."
cat <<EOF | sudo tee /opt/janus/etc/janus/janus.plugin.videoroom.jcfg > /dev/null
general: {
        admin_key = "supersecret"
        events = true
        string_ids = true
}

room-1234: {
        description = "Demo Room"
        secret = "adminpwd"
        publishers = 50
        bitrate = 128000
        fir_freq = 10
        audiocodec = "opus"
        videocodec = "h264"
        record = true
        rec_dir = "/opt/janus/recordings"
        lock_record = true
}
EOF

# Step 9: Apply custom Unix sockets transport configuration
echo "Applying custom Unix sockets transport configuration..."
cat <<EOF | sudo tee /opt/janus/etc/janus/janus.transport.pfunix.jcfg > /dev/null
general: {
        enabled = true
        json = "indented"
        path = "/tmp/janus.sock"
}

admin: {
        admin_enabled = true
        admin_path = "/tmp/janus-admin.sock"
}
EOF

# Step 10: Apply custom WebSockets transport configuration
echo "Applying custom WebSockets transport configuration..."
cat <<EOF | sudo tee /opt/janus/etc/janus/janus.transport.websockets.jcfg > /dev/null
general: {
        json = "indented"
        ws = true
        ws_port = 8188
        wss = false
}

admin: {
        admin_ws = false
        admin_ws_port = 7188
        admin_wss = false
}

cors: {
}

certificates: {
}
EOF

# Step 11: Apply custom streaming plugin configuration
echo "Applying custom streaming plugin configuration..."
cat <<EOF | sudo tee /opt/janus/etc/janus/janus.plugin.streaming.jcfg > /dev/null
general: {
    admin_key = "supersecret"
    events = true
    string_ids = false
}

multistream-test: {
    type = "rtp"
    id = 1234
    description = "Multistream test (100 video)"
    metadata = "This is an example of a multistream mountpoint: you'll get one hundred video feeds"
    secret = "adminpwd"
    media = (
        {
            type = "video"
            mid = "v001"
            label = "5001"
            port = 5001
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v1-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v002"
            label = "5002"
            port = 5002
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v2-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v003"
            label = "5003"
            port = 5003
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v3-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v004"
            label = "5004"
            port = 5004
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v4-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v005"
            label = "5005"
            port = 5005
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v5-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v006"
            label = "5006"
            port = 5006
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v6-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v007"
            label = "5007"
            port = 5007
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v7-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v008"
            label = "5008"
            port = 5008
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v8-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v009"
            label = "5009"
            port = 5009
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v9-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v010"
            label = "5010"
            port = 5010
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v10-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v011"
            label = "5011"
            port = 5011
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v11-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v012"
            label = "5012"
            port = 5012
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v12-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v013"
            label = "5013"
            port = 5013
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v13-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v014"
            label = "5014"
            port = 5014
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v14-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v015"
            label = "5015"
            port = 5015
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v15-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v016"
            label = "5016"
            port = 5016
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v16-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v017"
            label = "5017"
            port = 5017
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v17-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v018"
            label = "5018"
            port = 5018
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v18-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v019"
            label = "5019"
            port = 5019
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v19-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v020"
            label = "5020"
            port = 5020
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v20-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v021"
            label = "5021"
            port = 5021
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v21-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v022"
            label = "5022"
            port = 5022
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v22-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v023"
            label = "5023"
            port = 5023
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v23-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v024"
            label = "5024"
            port = 5024
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v24-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v025"
            label = "5025"
            port = 5025
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v25-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v026"
            label = "5026"
            port = 5026
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v26-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v027"
            label = "5027"
            port = 5027
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v27-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v028"
            label = "5028"
            port = 5028
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v28-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v029"
            label = "5029"
            port = 5029
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v29-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v030"
            label = "5030"
            port = 5030
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v30-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v031"
            label = "5031"
            port = 5031
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v31-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v032"
            label = "5032"
            port = 5032
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v32-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v033"
            label = "5033"
            port = 5033
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v33-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v034"
            label = "5034"
            port = 5034
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v34-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v035"
            label = "5035"
            port = 5035
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v35-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v036"
            label = "5036"
            port = 5036
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v36-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v037"
            label = "5037"
            port = 5037
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v37-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v038"
            label = "5038"
            port = 5038
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v38-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v039"
            label = "5039"
            port = 5039
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v39-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v040"
            label = "5040"
            port = 5040
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v40-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v041"
            label = "5041"
            port = 5041
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v41-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v042"
            label = "5042"
            port = 5042
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v42-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v043"
            label = "5043"
            port = 5043
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v43-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v044"
            label = "5044"
            port = 5044
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v44-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v045"
            label = "5045"
            port = 5045
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v45-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v046"
            label = "5046"
            port = 5046
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v46-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v047"
            label = "5047"
            port = 5047
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v47-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v048"
            label = "5048"
            port = 5048
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v48-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v049"
            label = "5049"
            port = 5049
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v49-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v050"
            label = "5050"
            port = 5050
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v50-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v051"
            label = "5051"
            port = 5051
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v51-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v052"
            label = "5052"
            port = 5052
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v52-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v053"
            label = "5053"
            port = 5053
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v53-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v054"
            label = "5054"
            port = 5054
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v54-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v055"
            label = "5055"
            port = 5055
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v55-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v056"
            label = "5056"
            port = 5056
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v56-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v057"
            label = "5057"
            port = 5057
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v57-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v058"
            label = "5058"
            port = 5058
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v58-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v059"
            label = "5059"
            port = 5059
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v59-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v060"
            label = "5060"
            port = 5060
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v60-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v061"
            label = "5061"
            port = 5061
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v61-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v062"
            label = "5062"
            port = 5062
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v62-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v063"
            label = "5063"
            port = 5063
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v63-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v064"
            label = "5064"
            port = 5064
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v64-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v065"
            label = "5065"
            port = 5065
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v65-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v066"
            label = "5066"
            port = 5066
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v66-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v067"
            label = "5067"
            port = 5067
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v67-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v068"
            label = "5068"
            port = 5068
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v68-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v069"
            label = "5069"
            port = 5069
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v69-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v070"
            label = "5070"
            port = 5070
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v70-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v071"
            label = "5071"
            port = 5071
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v71-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v072"
            label = "5072"
            port = 5072
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v72-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v073"
            label = "5073"
            port = 5073
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v73-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v074"
            label = "5074"
            port = 5074
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v74-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v075"
            label = "5075"
            port = 5075
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v75-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v076"
            label = "5076"
            port = 5076
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v76-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v077"
            label = "5077"
            port = 5077
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v77-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v078"
            label = "5078"
            port = 5078
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v78-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v079"
            label = "5079"
            port = 5079
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v79-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v080"
            label = "5080"
            port = 5080
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v80-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v081"
            label = "5081"
            port = 5081
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v81-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v082"
            label = "5082"
            port = 5082
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v82-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v083"
            label = "5083"
            port = 5083
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v83-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v084"
            label = "5084"
            port = 5084
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v84-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v085"
            label = "5085"
            port = 5085
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v85-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v086"
            label = "5086"
            port = 5086
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v86-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v087"
            label = "5087"
            port = 5087
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v87-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v088"
            label = "5088"
            port = 5088
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v88-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v089"
            label = "5089"
            port = 5089
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v89-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v090"
            label = "5090"
            port = 5090
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v90-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v091"
            label = "5091"
            port = 5091
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v91-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v092"
            label = "5092"
            port = 5092
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v92-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v093"
            label = "5093"
            port = 5093
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v93-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v094"
            label = "5094"
            port = 5094
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v94-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v095"
            label = "5095"
            port = 5095
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v95-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v096"
            label = "5096"
            port = 5096
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v96-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v097"
            label = "5097"
            port = 5097
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v97-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v098"
            label = "5098"
            port = 5098
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v98-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v099"
            label = "5099"
            port = 5099
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v99-%Y%m%d%H%M%S.mjr"
        },
        {
            type = "video"
            mid = "v100"
            label = "5100"
            port = 5100
            pt = 100
            codec = "h264"
            record = true
            recfile = "/opt/janus/recordings/multistream-test-v100-%Y%m%d%H%M%S.mjr"
        }
    )
}
EOF

# Step 12: Copy demo files to nginx web root
echo "Copying demo files to /var/www/html..."
sudo cp -r /opt/janus/share/janus/html/* /var/www/html/

# Step 13: Verify installation
echo "Verifying Janus installation..."
/opt/janus/bin/janus --version



# Step 14: Test Janus with NAT setting
echo "Starting Janus with NAT 1:1 mapping ($PUBLIC_IP)..."
/opt/janus/bin/janus --nat-1-1=$PUBLIC_IP -d 5 &

# Wait a few seconds for Janus to start
sleep 5

# Step 15: Create systemd service for Janus
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
