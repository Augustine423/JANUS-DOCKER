# Use Ubuntu 22.04 as the base image
FROM ubuntu:22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV INSTALL_DIR=/home/kzys
ENV PUBLIC_IP=127.0.0.1

# Install dependencies
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y \
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
    wget \
    curl && \
    apt-get clean

# Create installation directory
RUN mkdir -p $INSTALL_DIR
WORKDIR $INSTALL_DIR

# Install usrsctp
RUN git clone https://github.com/sctplab/usrsctp.git && \
    cd usrsctp && \
    ./bootstrap && \
    ./configure && \
    make && make install && \
    ldconfig && \
    cd ..

# Install libsrtp
RUN wget https://github.com/cisco/libsrtp/archive/v2.5.0.tar.gz -O libsrtp-2.5.0.tar.gz && \
    tar xfv libsrtp-2.5.0.tar.gz && \
    cd libsrtp-2.5.0 && \
    ./configure --prefix=/usr && \
    make && make install && \
    ldconfig && \
    cd ..

# Install Janus Gateway
RUN git clone https://github.com/meetecho/janus-gateway.git && \
    cd janus-gateway && \
    sh autogen.sh && \
    ./configure --prefix=/opt/janus \
        --enable-websockets \
        --enable-libsrtp2 \
        --enable-post-processing \
        --enable-recordings && \
    make && make install && make configs

# Create necessary directories and set permissions
RUN mkdir -p /opt/janus/lib/janus/loggers /opt/janus/recordings && \
    chmod 755 /opt/janus/lib/janus/loggers /opt/janus/recordings && \
    chown root:root /opt/janus/lib/janus/loggers /opt/janus/recordings

# Copy configuration files
COPY janus.jcfg /opt/janus/etc/janus/janus.jcfg
COPY janus.plugin.videoroom.jcfg /opt/janus/etc/janus/janus.plugin.videoroom.jcfg
COPY janus.transport.pfunix.jcfg /opt/janus/etc/janus/janus.transport.pfunix.jcfg
COPY janus.transport.websockets.jcfg /opt/janus/etc/janus/janus.transport.websockets.jcfg
COPY janus.plugin.streaming.jcfg /opt/janus/etc/janus/janus.plugin.streaming.jcfg

# Copy demo files to nginx web root
RUN cp -r /opt/janus/share/janus/html/* /var/www/html/

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose necessary ports
EXPOSE 80 8088 8188 5001-5100/udp

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]
CMD []