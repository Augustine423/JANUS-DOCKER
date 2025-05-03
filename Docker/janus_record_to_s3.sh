#!/bin/bash

# Variables
S3_BUCKET="mdt-video-gallery"
RECORDINGS_DIR="/opt/janus/recordings"
PROCESSED_DIR="/tmp/processed_recordings"
JANUS_LOG="/opt/janus/log/janus.log"

# Create processed recordings directory
mkdir -p "$PROCESSED_DIR"
chmod 755 "$PROCESSED_DIR"

# Function to get source IP and port from Janus logs
get_source_info() {
    local mjr_file="$1"
    local base_name=$(basename "$mjr_file" .mjr)
    local source_info="unknown_0"

    # Search Janus log for the .mjr filename to find associated IP and port
    if [ -f "$JANUS_LOG" ]; then
        log_entry=$(grep "$base_name" "$JANUS_LOG" | tail -n 1)
        if [[ -n "$log_entry" ]]; then
            # Extract IP and port (assuming log format includes "from <IP>:<PORT>")
            ip_port=$(echo "$log_entry" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+' | head -n 1)
            if [[ -n "$ip_port" ]]; then
                # Replace colon with underscore for filename
                source_info=${ip_port//:/_}
            fi
        fi
    fi
    
    echo "$source_info"
}

# Function to process .mjr files
process_mjr_file() {
    local mjr_file="$1"
    local base_name=$(basename "$mjr_file" .mjr)
    local timestamp=$(date -r "$mjr_file" +%Y%m%d_%H%M%S)
    local source_info=$(get_source_info "$mjr_file")
    local output_filename="${source_info}_${timestamp}"
    local temp_webm="$PROCESSED_DIR/$base_name.webm"
    local output_mp4="$PROCESSED_DIR/$output_filename.mp4"
    
    echo "Processing $mjr_file (Source: $source_info, Timestamp: $timestamp)..."
    
    # Convert .mjr to .webm using janus-pp-rec
    /opt/janus/bin/janus-pp-rec "$mjr_file" "$temp_webm"
    
    # Convert .webm to .mp4 using FFmpeg
    ffmpeg -i "$temp_webm" -c:v copy -c:a aac "$output_mp4"
    
    # Upload to S3
    aws s3 cp "$output_mp4" "s3://$S3_BUCKET/$output_filename.mp4"
    
    # Clean up
    rm -f "$temp_webm" "$output_mp4" "$mjr_file"
}

# Process all .mjr files in recordings directory
find "$RECORDINGS_DIR" -type f -name "*.mjr" | while read -r mjr_file; do
    process_mjr_file "$mjr_file"
done