#!/bin/bash

# Exit on error
set -e

# Check if script is running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root. Using sudo..."
    exec sudo "$0" "$@"
fi

# Update package lists and upgrade system
echo "Updating system packages..."
apt update && apt upgrade -y

# Install GStreamer and related packages
echo "Installing GStreamer packages..."
apt-get install -y \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    libgstreamer-plugins-bad1.0-dev \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    gstreamer1.0-tools \
    gstreamer1.0-x \
    gstreamer1.0-alsa \
    gstreamer1.0-gl \
    gstreamer1.0-gtk3 \
    gstreamer1.0-qt5 \
    gstreamer1.0-pulseaudio

# Verify GStreamer installation
echo "Checking GStreamer version..."
gst-inspect-1.0 --version

echo "GStreamer installation completed successfully!"