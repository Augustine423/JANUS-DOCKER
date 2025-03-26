# Use Ubuntu 22.04 as the base image
FROM ubuntu:22.04

# Set environment variables to avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Update and install dependencies
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y \
    libmicrohttpd-dev libjansson-dev libssl-dev libsrtp2-dev \
    libsofia-sip-ua-dev libglib2.0-dev libopus-dev libogg-dev \
    libcurl4-openssl-dev liblua5.3-dev libconfig-dev pkg-config \
    git cmake make gcc g++ libnice-dev libwebsockets-dev gengetopt \
    automake libtool nginx && \
    apt-get clean

# Install usrsctp
RUN git clone https://github.com/sctplab/usrsctp.git /tmp/usrsctp && \
    cd /tmp/usrsctp && \
    ./bootstrap && \
    ./configure && \
    make && make install && \
    ldconfig && \
    rm -rf /tmp/usrsctp

# Clone and install Janus Gateway
RUN git clone https://github.com/meetecho/janus-gateway.git /tmp/janus-gateway && \
    cd /tmp/janus-gateway && \
    sh autogen.sh && \
    ./configure --prefix=/opt/janus && \
    make && make install && make configs && \
    rm -rf /tmp/janus-gateway

# Copy Janus HTML files to Nginx web directory
RUN cp -r /opt/janus/share/janus/html/* /var/www/html/

# Copy custom streaming plugin configuration
COPY janus.plugin.streaming.jcfg /opt/janus/etc/janus/janus.plugin.streaming.jcfg

# Expose necessary ports (HTTP, WebSocket, RTP ports, etc.)
EXPOSE 80 8088 8188 5002 5004 5102 5104 5106

# Set up entrypoint to start Nginx and Janus
CMD service nginx start && /opt/janus/bin/janus --nat-1-1=auto