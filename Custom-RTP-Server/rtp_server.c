#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <netinet/in.h>
#include <arpa/inet.h> // Added for inet_ntoa
#include <pthread.h>
#include <signal.h>
#include <unistd.h>
#include "rtp_server.h" // Added for running variable
#include "db.h"
#include "recorder.h"
#include "websocket_server.h" // Added for start_websocket_server

#define MAX_STREAMS 1000
#define BUFFER_SIZE 2048

volatile sig_atomic_t running = 1;

void signal_handler(int sig) {
    running = 0;
}

void* handle_rtp_stream(void* arg) {
    int sock = *(int*)arg;
    free(arg);
    struct sockaddr_in src_addr;
    socklen_t addrlen = sizeof(src_addr);
    char buffer[BUFFER_SIZE];

    while (running) {
        ssize_t recv_len = recvfrom(sock, buffer, BUFFER_SIZE, 0,
                                    (struct sockaddr*)&src_addr, &addrlen);
        if (recv_len < 0) {
            if (running) perror("recvfrom failed");
            continue;
        }
        if (recv_len > 0) {
            char* ip = inet_ntoa(src_addr.sin_addr);
            int port = ntohs(src_addr.sin_port);
            db_store_source(ip, port);
            record_to_mp4(buffer, recv_len, ip, port);
        }
    }
    close(sock);
    return NULL;
}

int main() {
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    char *base_port_str = getenv("BASE_PORT");
    char *max_streams_str = getenv("MAX_STREAMS");
    int base_port = base_port_str ? atoi(base_port_str) : 5000;
    int max_streams = max_streams_str ? atoi(max_streams_str) : MAX_STREAMS;

    db_init();

    pthread_t threads[max_streams];
    int thread_count = 0;

    for (int i = 0; i < max_streams && running; ++i) {
        int sock = socket(AF_INET, SOCK_DGRAM, 0);
        if (sock < 0) {
            perror("socket creation failed");
            continue;
        }

        struct sockaddr_in servaddr = {0};
        servaddr.sin_family = AF_INET;
        servaddr.sin_addr.s_addr = INADDR_ANY;
        servaddr.sin_port = htons(base_port + i);

        if (bind(sock, (struct sockaddr*)&servaddr, sizeof(servaddr)) < 0) {
            perror("bind failed");
            close(sock);
            continue;
        }

        int* sock_ptr = malloc(sizeof(int));
        if (!sock_ptr) {
            perror("malloc failed");
            close(sock);
            continue;
        }
        *sock_ptr = sock;

        if (pthread_create(&threads[thread_count++], NULL, handle_rtp_stream, sock_ptr) != 0) {
            perror("pthread_create failed");
            free(sock_ptr);
            close(sock);
        }
    }

    start_websocket_server();

    for (int i = 0; i < thread_count; ++i) {
        pthread_join(threads[i], NULL);
    }

    db_cleanup();
    recorder_cleanup();
    return 0;
}