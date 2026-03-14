#!/bin/bash
#
# get-audio-duration.sh - Get audio file duration in seconds
#
# Usage: ./get-audio-duration.sh <audio_file>
#
# Output:
#   JSON object with duration information:
#   - duration_seconds: total duration in seconds (float)
#   - duration_formatted: human-readable format (HH:MM:SS)
#   - sample_rate: audio sample rate
#   - channels: number of audio channels
#
# This ensures the timeline's last segment ends at the correct time.
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
NC='\033[0m' # No Color

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_usage() {
    echo "Usage: $0 <audio_file>"
    echo ""
    echo "Get audio file duration and metadata"
    echo ""
    echo "Arguments:"
    echo "  audio_file    Path to the audio file"
    echo ""
    echo "Output:"
    echo "  JSON object with duration and audio metadata"
    echo ""
    echo "Example output:"
    echo '  {'
    echo '    "file": "/path/to/audio.mp3",'
    echo '    "duration_seconds": 2880.5,'
    echo '    "duration_formatted": "00:48:00",'
    echo '    "sample_rate": 48000,'
    echo '    "channels": 2,'
    echo '    "codec": "mp3",'
    echo '    "bitrate": "192000"'
    echo '  }'
}

# Format seconds to HH:MM:SS
format_duration() {
    local seconds="$1"
    local hours minutes secs
    
    hours=$(awk "BEGIN {printf \"%d\", $seconds / 3600}")
    minutes=$(awk "BEGIN {printf \"%d\", ($seconds % 3600) / 60}")
    secs=$(awk "BEGIN {printf \"%d\", $seconds % 60}")
    
    printf "%02d:%02d:%02d" "$hours" "$minutes" "$secs"
}

# Main function
get_duration() {
    local audio_file="$1"
    
    if [[ ! -f "$audio_file" ]]; then
        log_error "Audio file not found: $audio_file"
        exit 1
    fi
    
    # Get absolute path
    audio_file=$(realpath "$audio_file")
    
    # Get audio stream info using ffprobe
    local probe_output
    probe_output=$(ffprobe -v error \
        -select_streams a:0 \
        -show_entries stream=codec_name,sample_rate,channels,bit_rate \
        -show_entries format=duration,bit_rate \
        -of json "$audio_file" 2>/dev/null)
    
    if [[ -z "$probe_output" ]]; then
        log_error "Failed to probe audio file: $audio_file"
        exit 1
    fi
    
    # Extract values
    local duration codec sample_rate channels bitrate
    duration=$(echo "$probe_output" | jq -r '.format.duration // empty')
    codec=$(echo "$probe_output" | jq -r '.streams[0].codec_name // "unknown"')
    sample_rate=$(echo "$probe_output" | jq -r '.streams[0].sample_rate // 0')
    channels=$(echo "$probe_output" | jq -r '.streams[0].channels // 0')
    bitrate=$(echo "$probe_output" | jq -r '.format.bit_rate // .streams[0].bit_rate // "0"')
    
    if [[ -z "$duration" ]] || [[ "$duration" == "null" ]]; then
        log_error "Could not determine audio duration"
        exit 1
    fi
    
    # Format duration
    local formatted
    formatted=$(format_duration "$duration")
    
    # Build JSON output
    jq -n \
        --arg file "$audio_file" \
        --arg duration "$duration" \
        --arg formatted "$formatted" \
        --arg sample_rate "$sample_rate" \
        --arg channels "$channels" \
        --arg codec "$codec" \
        --arg bitrate "$bitrate" \
        '{
            "file": $file,
            "duration_seconds": ($duration | tonumber),
            "duration_formatted": $formatted,
            "sample_rate": ($sample_rate | tonumber),
            "channels": ($channels | tonumber),
            "codec": $codec,
            "bitrate": $bitrate
        }'
}

# Main entry point
main() {
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        print_usage
        exit 0
    fi
    
    if [[ $# -lt 1 ]]; then
        log_error "Missing required argument: audio_file"
        echo ""
        print_usage
        exit 1
    fi
    
    # Check dependencies
    if ! command -v ffprobe &> /dev/null; then
        log_error "ffprobe is not installed. Install ffmpeg package."
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Install with: apt install jq or brew install jq"
        exit 1
    fi
    
    get_duration "$1"
}

main "$@"
