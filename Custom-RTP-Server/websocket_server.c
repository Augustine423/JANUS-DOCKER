#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libwebsockets.h>
#include "rtp_server.h"
#include "db.h"

static struct lws_context *context;
static struct lws *clients[100];
static int client_count = 0;
static pthread_mutex_t ws_mutex = PTHREAD_MUTEX_INITIALIZER;

// Mount configuration for serving static files
static const struct lws_http_mount mount_output = {
    .mount_next = NULL,
    .mountpoint = "/output",
    .origin = "/app/output",
    .def = NULL,
    .protocol = NULL,
    .cgienv = NULL,
    .extra_mimetypes = NULL,
    .interpret = NULL,
    .cgi_timeout = 0,
    .cache_max_age = 0,
    .auth_mask = 0,
    .cache_reusable = 0,
    .cache_revalidate = 0,
    .cache_intermediaries = 0,
    .origin_protocol = LWSMPRO_FILE,
    .mountpoint_len = 7,
};

static const struct lws_http_mount mount_index = {
    .mount_next = &mount_output,
    .mountpoint = "/",
    .origin = "/app/frontend/index.html",
    .def = "index.html",
    .protocol = NULL,
    .cgienv = NULL,
    .extra_mimetypes = NULL,
    .interpret = NULL,
    .cgi_timeout = 0,
    .cache_max_age = 0,
    .auth_mask = 0,
    .cache_reusable = 0,
    .cache_revalidate = 0,
    .cache_intermediaries = 0,
    .origin_protocol = LWSMPRO_FILE,
    .mountpoint_len = 1,
};

static void send_json(const char* ip, int port, void* user_data) {
    char json[256];
    snprintf(json, sizeof(json), "{\"ip\": \"%s\", \"port\": %d}", ip, port);
    
    pthread_mutex_lock(&ws_mutex);
    for (int i = 0; i < client_count; ++i) {
        if (clients[i]) {
            lws_write(clients[i], (unsigned char*)json, strlen(json), LWS_WRITE_TEXT);
        }
    }
    pthread_mutex_unlock(&ws_mutex);
}

static int callback_websocket(struct lws *wsi, enum lws_callback_reasons reason,
                             void *user, void *in, size_t len) {
    switch (reason) {
        case LWS_CALLBACK_ESTABLISHED:
            pthread_mutex_lock(&ws_mutex);
            if (client_count < 100) {
                clients[client_count++] = wsi;
            }
            pthread_mutex_unlock(&ws_mutex);
            db_get_sources(send_json, NULL);
            break;
        case LWS_CALLBACK_CLOSED:
            pthread_mutex_lock(&ws_mutex);
            for (int i = 0; i < client_count; ++i) {
                if (clients[i] == wsi) {
                    clients[i] = clients[--client_count];
                    clients[client_count] = NULL;
                    break;
                }
            }
            pthread_mutex_unlock(&ws_mutex);
            break;
        default:
            break;
    }
    return 0;
}

static struct lws_protocols protocols[] = {
    {
        "rtp-config",
        callback_websocket,
        0,
        0
    },
    {
        "http",
        lws_callback_http_dummy,
        0,
        0
    },
    { NULL, NULL, 0, 0 }
};

void start_websocket_server() {
    struct lws_context_creation_info info = {0};
    info.port = atoi(getenv("WEBSOCKET_PORT") ? getenv("WEBSOCKET_PORT") : "8188");
    info.protocols = protocols;
    info.mounts = &mount_index;
    info.options = LWS_SERVER_OPTION_DO_SSL_GLOBAL_INIT;

    context = lws_create_context(&info);
    if (!context) {
        fprintf(stderr, "lws_create_context failed\n");
        return;
    }

    while (running) {
        lws_service(context, 1000);
    }

    lws_context_destroy(context);
}