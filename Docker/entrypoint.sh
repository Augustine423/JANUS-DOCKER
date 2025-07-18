#!/bin/bash

# Exit on any error
set -e

# Start nginx in the foreground
nginx -g 'daemon off;' &


# Auto-detect public IP of EC2
PUBLIC_IP=$(curl -s https://api.ipify.org || echo "127.0.0.1")

# Log the selected IP
echo "Using PUBLIC_IP: $PUBLIC_IP"

# Start nginx in the foreground
nginx -g 'daemon off;' &

# Start Janus with the selected PUBLIC_IP
exec /opt/janus/bin/janus --nat-1-1="$PUBLIC_IP" -d 5