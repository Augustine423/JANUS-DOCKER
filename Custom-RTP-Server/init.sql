CREATE TABLE IF NOT EXISTS rtp_ports (
    ip VARCHAR(15) NOT NULL,
    port INT NOT NULL,
    allocated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (ip, port)
);