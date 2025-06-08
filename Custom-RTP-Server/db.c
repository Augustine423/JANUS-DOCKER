#include <stdio.h>
#include <stdlib.h>
#include <string.h> // Added for strlen, strncpy, memset
#include <mysql.h>
#include <pthread.h>
#include "db.h"

static MYSQL *conn;
static pthread_mutex_t db_mutex = PTHREAD_MUTEX_INITIALIZER;

void db_init() {
    conn = mysql_init(NULL);
    if (!conn) {
        fprintf(stderr, "mysql_init failed\n");
        exit(1);
    }

    char *host = getenv("MYSQL_HOST");
    char *user = getenv("MYSQL_USER");
    char *password = getenv("MYSQL_PASSWORD");
    char *database = getenv("MYSQL_DATABASE");

    if (!mysql_real_connect(conn, host ? host : "localhost",
                           user ? user : "rtp_user",
                           password ? password : "password",
                           database ? database : "rtp_streams",
                           0, NULL, 0)) {
        fprintf(stderr, "mysql_real_connect failed: %s\n", mysql_error(conn));
        mysql_close(conn);
        exit(1);
    }

    const char *create_table = "CREATE TABLE IF NOT EXISTS rtp_ports ("
                               "ip VARCHAR(15) NOT NULL, "
                               "port INT NOT NULL, "
                               "allocated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, "
                               "PRIMARY KEY (ip, port))";
    if (mysql_query(conn, create_table)) {
        fprintf(stderr, "CREATE TABLE failed: %s\n", mysql_error(conn));
        mysql_close(conn);
        exit(1);
    }
}

void db_store_source(const char* ip, int port) {
    pthread_mutex_lock(&db_mutex);
    MYSQL_STMT *stmt;
    MYSQL_BIND bind[2];
    char query[] = "INSERT IGNORE INTO rtp_ports (ip, port) VALUES (?, ?)";

    stmt = mysql_stmt_init(conn);
    if (!stmt) {
        fprintf(stderr, "mysql_stmt_init failed: %s\n", mysql_error(conn));
        pthread_mutex_unlock(&db_mutex);
        return;
    }

    if (mysql_stmt_prepare(stmt, query, strlen(query))) {
        fprintf(stderr, "mysql_stmt_prepare failed: %s\n", mysql_error(conn));
        mysql_stmt_close(stmt);
        pthread_mutex_unlock(&db_mutex);
        return;
    }

    char ip_str[16];
    strncpy(ip_str, ip, 16);
    int port_val = port;

    memset(bind, 0, sizeof(bind));
    bind[0].buffer_type = MYSQL_TYPE_STRING;
    bind[0].buffer = ip_str;
    bind[0].buffer_length = strlen(ip_str);
    bind[1].buffer_type = MYSQL_TYPE_LONG;
    bind[1].buffer = &port_val;

    if (mysql_stmt_bind_param(stmt, bind)) {
        fprintf(stderr, "mysql_stmt_bind_param failed: %s\n", mysql_error(conn));
        mysql_stmt_close(stmt);
        pthread_mutex_unlock(&db_mutex);
        return;
    }

    if (mysql_stmt_execute(stmt)) {
        fprintf(stderr, "mysql_stmt_execute failed: %s\n", mysql_error(conn));
    }

    mysql_stmt_close(stmt);
    pthread_mutex_unlock(&db_mutex);
}

void db_get_sources(void (*callback)(const char* ip, int port, void* user_data), void* user_data) {
    pthread_mutex_lock(&db_mutex);
    const char *query = "SELECT ip, port FROM rtp_ports";
    if (mysql_query(conn, query)) {
        fprintf(stderr, "SELECT query failed: %s\n", mysql_error(conn));
        pthread_mutex_unlock(&db_mutex);
        return;
    }

    MYSQL_RES *result = mysql_store_result(conn);
    if (!result) {
        fprintf(stderr, "mysql_store_result failed: %s\n", mysql_error(conn));
        pthread_mutex_unlock(&db_mutex);
        return;
    }

    MYSQL_ROW row;
    while ((row = mysql_fetch_row(result))) {
        const char *ip = row[0];
        int port = atoi(row[1]);
        callback(ip, port, user_data);
    }

    mysql_free_result(result);
    pthread_mutex_unlock(&db_mutex);
}

void db_cleanup() {
    pthread_mutex_lock(&db_mutex);
    mysql_close(conn);
    pthread_mutex_unlock(&db_mutex);
    pthread_mutex_destroy(&db_mutex);
}