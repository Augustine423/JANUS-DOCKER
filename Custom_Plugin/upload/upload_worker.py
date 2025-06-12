#!/usr/bin/env python3
import os, time, boto3, psycopg2, re

AWS_BUCKET = "my-janus-bucket"
WATCH_DIR = "/tmp"
PG_CONN = "dbname=janus host=db user=janus pass=secret"

s3 = boto3.client("s3")
db = psycopg2.connect(PG_CONN)

pattern = re.compile(r"rtp_([^_]+)_(\d+)\.mp4")

while True:
    for f in os.listdir(WATCH_DIR):
        m = pattern.match(f)
        if m:
            ip, port = m.groups()
            local = os.path.join(WATCH_DIR, f)
            s3key = f"videos/{f}"
            s3.upload_file(local, AWS_BUCKET, s3key)
            url = f"https://{AWS_BUCKET}.s3.amazonaws.com/{s3key}"
            cur = db.cursor()
            cur.execute("INSERT INTO rtp_streams(ip, port, video_url) VALUES (%s,%s,%s)",
                        (ip, int(port), url))
            db.commit()
            os.remove(local)
    time.sleep(10)
