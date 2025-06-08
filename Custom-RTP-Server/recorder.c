#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <pthread.h>
#include "recorder.h"

typedef struct {
    AVFormatContext *fmt_ctx;
    AVCodecContext *codec_ctx;
    int stream_index;
} StreamContext;

static StreamContext *streams[1000];
static pthread_mutex_t stream_mutex = PTHREAD_MUTEX_INITIALIZER;

static StreamContext* get_stream_context(const char* ip, int port) {
    char key[32];
    snprintf(key, sizeof(key), "%s:%d", ip, port);
    
    pthread_mutex_lock(&stream_mutex);
    int index = -1;
    for (int i = 0; i < 1000; ++i) {
        if (!streams[i]) {
            index = i;
            break;
        }
        if (strcmp(key, streams[i]->fmt_ctx->url) == 0) {
            pthread_mutex_unlock(&stream_mutex);
            return streams[i];
        }
    }

    if (index == -1) {
        pthread_mutex_unlock(&stream_mutex);
        return NULL;
    }

    StreamContext *ctx = malloc(sizeof(StreamContext));
    if (!ctx) return NULL;

    if (avformat_alloc_output_context2(&ctx->fmt_ctx, NULL, "mp4", key) < 0) {
        free(ctx);
        pthread_mutex_unlock(&stream_mutex);
        return NULL;
    }

    const AVCodec *codec = avcodec_find_decoder(AV_CODEC_ID_H264); // Changed to const
    if (!codec) {
        avformat_free_context(ctx->fmt_ctx);
        free(ctx);
        pthread_mutex_unlock(&stream_mutex);
        return NULL;
    }

    ctx->codec_ctx = avcodec_alloc_context3(codec);
    if (!ctx->codec_ctx) {
        avformat_free_context(ctx->fmt_ctx);
        free(ctx);
        pthread_mutex_unlock(&stream_mutex);
        return NULL;
    }

    ctx->stream_index = -1;
    streams[index] = ctx;
    pthread_mutex_unlock(&stream_mutex);
    return ctx;
}

void record_to_mp4(const char* rtp_packet, int len, const char* ip, int port) {
    StreamContext *ctx = get_stream_context(ip, port);
    if (!ctx) {
        fprintf(stderr, "Failed to get stream context for %s:%d\n", ip, port);
        return;
    }

    AVPacket *pkt = av_packet_alloc();
    if (!pkt) return;
    pkt->data = (uint8_t*)rtp_packet;
    pkt->size = len;

    if (avcodec_send_packet(ctx->codec_ctx, pkt) < 0) {
        fprintf(stderr, "avcodec_send_packet failed for %s:%d\n", ip, port);
        av_packet_free(&pkt);
        return;
    }

    AVFrame *frame = av_frame_alloc();
    if (!frame) {
        av_packet_free(&pkt);
        return;
    }

    if (avcodec_receive_frame(ctx->codec_ctx, frame) == 0) {
        if (ctx->stream_index == -1) {
            AVStream *stream = avformat_new_stream(ctx->fmt_ctx, NULL);
            if (!stream) {
                av_frame_free(&frame);
                av_packet_free(&pkt);
                return;
            }
            ctx->stream_index = stream->index;
            avcodec_parameters_from_context(stream->codecpar, ctx->codec_ctx);
            if (avformat_write_header(ctx->fmt_ctx, NULL) < 0) {
                fprintf(stderr, "avformat_write_header failed for %s:%d\n", ip, port);
                av_frame_free(&frame);
                av_packet_free(&pkt);
                return;
            }
        }

        if (av_write_frame(ctx->fmt_ctx, pkt) < 0) {
            fprintf(stderr, "av_write_frame failed for %s:%d\n", ip, port);
        }
    }

    av_frame_free(&frame);
    av_packet_free(&pkt);
}

void recorder_cleanup() {
    pthread_mutex_lock(&stream_mutex);
    for (int i = 0; i < 1000; ++i) {
        if (streams[i]) {
            av_write_trailer(streams[i]->fmt_ctx);
            avcodec_free_context(&streams[i]->codec_ctx);
            avformat_free_context(streams[i]->fmt_ctx);
            free(streams[i]);
            streams[i] = NULL;
        }
    }
    pthread_mutex_unlock(&stream_mutex);
    pthread_mutex_destroy(&stream_mutex);
}