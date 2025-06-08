# Stage 1: Build Janus Gateway
FROM debian:bullseye-slim AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    cmake \
    pkg-config \
    automake \
    libtool \
    gengetopt \
    gcc \
    g++ \
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
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install usrsctp
WORKDIR /tmp
RUN git clone https://github.com/sctplab/usrsctp.git && \
    cd usrsctp && \
    ./bootstrap && \
    ./configure && \
    make && make install && \
    ldconfig

# Install libsrtp from source
RUN wget https://github.com/cisco/libsrtp/archive/v2.5.0.tar.gz -O libsrtp-2.5.0.tar.gz && \
    tar xfv libsrtp-2.5.0.tar.gz && \
    cd libsrtp-2.5.0 && \
    ./configure --prefix=/usr && \
    make && make install && \
    ldconfig

# Build Janus Gateway
WORKDIR /usr/local/src
RUN git clone https://github.com/meetecho/janus-gateway.git && \
    cd janus-gateway && \
    sh autogen.sh && \
    ./configure --prefix=/opt/janus --enable-websockets --enable-libsrtp2 && \
    make && make install && make configs

# Stage 2: Runtime image
FROM debian:bullseye-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libmicrohttpd12 \
    libjansson4 \
    libssl1.1 \
    libsofia-sip-ua0 \
    libglib2.0-0 \
    libopus0 \
    libogg0 \
    libcurl4 \
    liblua5.3-0 \
    libconfig9 \
    libusrsctp1 \
    libwebsockets16 \
    libspeexdsp1 \
    libavutil56 \
    libavcodec58 \
    libavformat58 \
    nginx \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy built artifacts from builder stage
COPY --from=builder /usr/lib/libsrtp2.so.1 /usr/lib/libsrtp2.so.1
RUN ln -s /usr/lib/libsrtp2.so.1 /usr/lib/libsrtp2.so
COPY --from=builder /usr/lib/libnice* /usr/lib/
COPY --from=builder /opt/janus /opt/janus

# Create directories for recordings and loggers
RUN mkdir -p /opt/janus/etc/janus /opt/janus/recordings /opt/janus/lib/janus/loggers /var/www/html && \
    chmod 755 /opt/janus/recordings /opt/janus/lib/janus/loggers

# Copy demo files to Nginx web root
COPY --from=builder /opt/janus/share/janus/html/* /var/www/html/

# Set environment variables for build metadata
ARG BUILD_DATE="undefined"
ARG GIT_BRANCH="undefined"
ARG GIT_COMMIT="undefined"
ARG VERSION="undefined"

LABEL build_date=${BUILD_DATE}
LABEL git_branch=${GIT_BRANCH}
LABEL git_commit=${GIT_COMMIT}
LABEL version=${VERSION}

ENV BUILD_DATE=${BUILD_DATE}
ENV GIT_BRANCH=${GIT_BRANCH}
ENV GIT_COMMIT=${GIT_COMMIT}
ENV VERSION=${VERSION}

# Expose necessary ports (aligned with your script)
EXPOSE 5002/udp 5004/udp 5100-5150/udp 8188 7088

# Start Janus
CMD ["/opt/janus/bin/janus", "-F", "/opt/janus/etc/janus"]