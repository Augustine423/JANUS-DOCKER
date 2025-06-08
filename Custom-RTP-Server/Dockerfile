FROM ubuntu:22.04


RUN apt-get update && apt-get install -y \
    gcc \
    make \
    libmysqlclient-dev \
    libavformat-dev \
    libavcodec-dev \
    libavutil-dev \
    libwebsockets-dev \
    libpthread-stubs0-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*


WORKDIR /app


COPY rtp_server.h rtp_server.c db.h db.c recorder.h recorder.c websocket_server.h websocket_server.c ./


RUN gcc -o rtp_server rtp_server.c db.c recorder.c websocket_server.c \
    -I/usr/include/mysql -L/usr/lib/x86_64-linux-gnu \
    -lmysqlclient -lavformat -lavcodec -lavutil -lwebsockets -pthread

COPY .env ./


EXPOSE 5000-5999/udp 8188

CMD ["./rtp_server"]