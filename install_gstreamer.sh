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

# Install v4l-utils for Video4Linux support
echo "Installing v4l-utils..."
apt-get install -y v4l-utils v4l2loopback-dkms

# Install GStreamer and related packages
echo "Installing GStreamer packages..."
apt-get install -y \
    libg=1.0-dev \
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
    gstreamer1.***REMOVED***tk3 \
    gstreamer1.0-qt5 \
    gstreamer1.0-pulseaudio

# Install VLC
echo "Installing VLC..."
apt-get install -y vlc

# Verify GStreamer installation
echo "Checking GStreamer version..."
gst-inspect-1.0 --version

# Verify v4l2 installation
echo "Checking v4l2 devices..."
v4l2-ctl --list-devices

echo "GStreamer installation completed successfully!"

# Stream webcam to Janus at 13.213.46.108:5004
echo "Starting webcam stream to Janus use this command and replace your server ip address and port"
echo"gst-launch-1.0 v4l2src device=/dev/video0 ! videoconvert ! video/x-raw,format=I420,width=1280,height=720,framerate=30/1 ! x264enc tune=zerolatency bitrate=1000 ! h264parse ! rtph264pay pt=96 ! udpsink host=13.213.46.108 port=5004"

echo"gst-launch-1.0 v4l2src device=/dev/video0 ! image/jpeg,width=1280,height=720,framerate=30/1 ! jpegdec ! videoconvert ! video/x-raw,format=I420 ! x264enc tune=zerolatency bitrate=2000 ! h264parse ! rtph264pay pt=96 ! udpsink host=13.213.46.108 port=5004"