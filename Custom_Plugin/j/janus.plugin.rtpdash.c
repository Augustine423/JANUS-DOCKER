// janus.plugin.rtpdash.c
#include <janus/janus_plugin.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <pthread.h>
#include <jansson.h>

#define MAX_STREAMS 500
#define RTP_BASE_PORT 5000

typedef struct {
  int id;
  char ip[INET_ADDRSTRLEN];
  int port;
  int sockfd;
} stream_t;

static stream_t streams[MAX_STREAMS];
static int stream_count = 0;
static janus_plugin plugin_interface;
static janus_callbacks *janus_callbacks_ptr = NULL;

static void *rtp_thread(void *arg) {
  stream_t *st = arg;
  uint8_t buf[1500];
  struct sockaddr_in src;
  socklen_t sl = sizeof(src);
  ssize_t len;

  while ((len = recvfrom(st->sockfd, buf, sizeof(buf), 0, (struct sockaddr*)&src, &sl)) > 0) {
    if (st->ip[0] == '\0') {
      inet_ntop(AF_INET, &src.sin_addr, st->ip, sizeof(st->ip));
      st->port = ntohs(src.sin_port);

      janus_log(LOG_VERB, "New RTP stream %d from %s:%d\n", st->id, st->ip, st->port);

      json_t *event = json_pack("{s:{s:s, s:i, s:s, s:i}}",
        "streaming", "source-new",
        "id", st->id,
        "ip", st->ip,
        "port", st->port
      );
      janus_callbacks_ptr->push_event(NULL, &plugin_interface, NULL, NULL, event, NULL);
      json_decref(event);

      char fname[512];
      sprintf(fname, "/tmp/rtp_%s_%d.mp4", st->ip, st->port);
      char cmd[1024];
      sprintf(cmd,
        "ffmpeg -y -protocol_whitelist file,udp,rtp -i udp://127.0.0.1:%d "
        "-c:v copy -c:a copy %s &",
        RTP_BASE_PORT + st->id, fname
      );
      system(cmd);
    }
  }
  return NULL;
}

static int init(janus_callbacks *callback, const char *config_path) {
  janus_callbacks_ptr = callback;
  for (int i = 0; i < MAX_STREAMS; i++) {
    streams[i].id = i;
    streams[i].ip[0] = '\0';
    streams[i].sockfd = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in addr = { .sin_family = AF_INET,
                                .sin_addr.s_addr = INADDR_ANY,
                                .sin_port = htons(RTP_BASE_PORT + i)};
    bind(streams[i].sockfd, (struct sockaddr*)&addr, sizeof(addr));
    pthread_t th;
    pthread_create(&th, NULL, &rtp_thread, &streams[i]);
  }
  janus_log(LOG_VERB, "rtpdash plugin init, listening 500 RTP ports %d–%d\n",
            RTP_BASE_PORT, RTP_BASE_PORT+MAX_STREAMS-1);
  return 0;
}

static void destroy(void) { }

static janus_plugin_plugin *create(void **handle) {
  *handle = NULL;
  return &plugin_interface;
}

static void destroy_session(void *handle, uint64_t session_id, void *dummy) {}
static int setup_jsep(void *handle, uint64_t session_id, json_t *jsep) { return 0; }
static json_t *handle_message(void *handle, uint64_t session_id, json_t *message) {
  json_t *req = json_object();
  json_array_foreach(message, idx, entry) {
    const char *cmd = json_string_value(json_object_get(entry, "request"));
    if (cmd && strcmp(cmd, "list") == 0) {
      json_t *array = json_array();
      for (int i = 0; i < MAX_STREAMS; i++) {
        if (streams[i].ip[0] != '\0') {
          json_array_append_new(array,
            json_pack("{s:i, s:s, s:i}",
                      "id", streams[i].id,
                      "ip", streams[i].ip,
                      "port", streams[i].port));
        }
      }
      json_object_set(req, "streams", array);
      json_decref(array);
      break;
    }
  }
  return req;
}

janus_plugin plugin_interface = {
  .init           = init,
  .destroy        = destroy,
  .create         = create,
  .destroy_session= destroy_session,
  .setup_jsep     = setup_jsep,
  .handle_message = handle_message,
  .plugin_name    = "rtpdash",
  .plugin_version = "0.1",
  .description    = "RTP Dashboard plugin"
};
