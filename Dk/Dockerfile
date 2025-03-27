# Use Ubuntu 22.04 as the base image
FROM ubuntu:22.04

# Set environment variables to avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Update and install base dependencies
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y \
    libmicrohttpd-dev libjansson-dev libssl-dev \
    libsofia-sip-ua-dev libglib2.0-dev libopus-dev libogg-dev \
    libcurl4-openssl-dev liblua5.3-dev libconfig-dev pkg-config \
    git cmake make gcc g++ libnice-dev gengetopt automake libtool nginx \
    libnanomsg-dev && \
    apt-get clean

# Install libsrtp (latest version 2.6.0)
RUN git clone https://github.com/cisco/libsrtp.git /tmp/libsrtp && \
    cd /tmp/libsrtp && \
    git checkout v2.6.0 && \
    ./configure --prefix=/usr --enable-openssl && \
    make shared_library && make install && \
    cd / && rm -rf /tmp/libsrtp

# Install usrsctp (latest from repo)
RUN git clone https://github.com/sctplab/usrsctp.git /tmp/usrsctp && \
    cd /tmp/usrsctp && \
    ./bootstrap && \
    ./configure --prefix=/usr && \
    make && make install && \
    ldconfig && \
    cd / && rm -rf /tmp/usrsctp

# Install libwebsockets (latest stable 4.3.3)
RUN git clone https://github.com/warmcat/libwebsockets.git /tmp/libwebsockets && \
    cd /tmp/libwebsockets && \
    git checkout v4.3.3 && \
    mkdir build && cd build && \
    cmake -DLWS_MAX_SMP=1 -DCMAKE_INSTALL_PREFIX:PATH=/usr -DCMAKE_C_FLAGS="-fpic" .. && \
    make && make install && \
    cd / && rm -rf /tmp/libwebsockets

# Install paho.mqtt.c (latest from repo)
RUN git clone https://github.com/eclipse/paho.mqtt.c.git /tmp/paho.mqtt.c && \
    cd /tmp/paho.mqtt.c && \
    make && make install PREFIX=/usr && \
    cd / && rm -rf /tmp/paho.mqtt.c

# Install rabbitmq-c (latest from repo)
RUN git clone https://github.com/alanxz/rabbitmq-c.git /tmp/rabbitmq-c && \
    cd /tmp/rabbitmq-c && \
    git submodule init && git submodule update && \
    mkdir build && cd build && \
    cmake -DCMAKE_INSTALL_PREFIX=/usr .. && \
    make && make install && \
    cd / && rm -rf /tmp/rabbitmq-c

# Install Janus Gateway
RUN git clone https://github.com/meetecho/janus-gateway.git /tmp/janus-gateway && \
    cd /tmp/janus-gateway && \
    sh autogen.sh && \
    ./configure --prefix=/opt/janus && \
    make && make install && make configs && \
    cd / && rm -rf /tmp/janus-gateway

# Copy Janus HTML files to Nginx web directory
RUN cp -r /opt/janus/share/janus/html/* /var/www/html/

# Copy custom plugin configurations
COPY janus.plugin.streaming.jcfg /opt/janus/etc/janus/janus.plugin.streaming.jcfg
COPY janus.plugin.videoroom.jcfg /opt/janus/etc/janus/janus.plugin.videoroom.jcfg

# Create and set permissions for the recordings directory
RUN mkdir -p /recordings && \
    chown -R www-data:www-data /recordings && \
    chmod -R 775 /recordings

# Expose necessary ports (HTTP, WebSocket, RTP ports, etc.)
EXPOSE 80 8088 8188 5002 5004 5102 5104 5106

# Set up entrypoint to start Nginx and Janus
CMD service nginx start && /opt/janus/bin/janus --nat-1-1=auto