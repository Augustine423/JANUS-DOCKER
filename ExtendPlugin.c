#include <netinet/in.h>
#include <arpa/inet.h>
// ... (other includes)

static void janus_streaming_handle_message(janus_plugin_session *handle, char *transaction, json_t *message, json_t *jsep) {
    // ... (existing code)
    if (!strcasecmp(request_text, "list")) {
        json_t *list = json_array();
        janus_mutex_lock(&mountpoints_mutex);
        GHashTableIter iter;
        gpointer value;
        g_hash_table_iter_init(&iter, mountpoints);
        while (g_hash_table_iter_next(&iter, NULL, &value)) {
            janus_streaming_mountpoint *mp = value;
            json_t *ml = json_object();
            json_object_set_new(ml, "id", json_integer(mp->id));
            json_object_set_new(ml, "description", mp->description ? json_string(mp->description) : json_null());
            // Add IP and port from RTP source
            if (mp->streaming_source == JANUS_STREAMING_SOURCE_RTP && mp->source.rtp) {
                struct sockaddr_in *addr = (struct sockaddr_in *)mp->source.rtp->local_addr;
                char ip_str[INET_ADDRSTRLEN];
                inet_ntop(AF_INET, &(addr->sin_addr), ip_str, INET_ADDRSTRLEN);
                json_object_set_new(ml, "source_ip", json_string(ip_str));
                json_object_set_new(ml, "source_port", json_integer(ntohs(addr->sin_port)));
            } else {
                json_object_set_new(ml, "source_ip", json_null());
                json_object_set_new(ml, "source_port", json_null());
            }
            json_array_append_new(list, ml);
        }
        janus_mutex_unlock(&mountpoints_mutex);
        json_t *root = json_object();
        json_object_set_new(root, "janus", json_string("success"));
        json_object_set_new(root, "list", list);
        janus_plugin_push_event(handle, root, transaction);
        json_decref(root);
        return;
    }
    // ... (handle other requests like "info" similarly)
}