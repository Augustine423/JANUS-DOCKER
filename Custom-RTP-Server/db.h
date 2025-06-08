#ifndef DB_H
#define DB_H

void db_init();
void db_store_source(const char* ip, int port);
void db_get_sources(void (*callback)(const char* ip, int port, void* user_data), void* user_data);
void db_cleanup();

#endif