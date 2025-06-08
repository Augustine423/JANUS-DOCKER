#ifndef RECORDER_H
#define RECORDER_H

void record_to_mp4(const char* rtp_packet, int len, const char* ip, int port);
void recorder_cleanup();

#endif