#!/bin/bash
#
# generate-timeline.sh - Generate timeline JSON from analyzed segments and images
#
# Usage: ./generate-timeline.sh <segments_json> <image_mapping_json> <audio_file> <output_file>
#
# This script combines:
#   - Analyzed VTT segments (from analyze-segments.sh)
#   - Image-to-segment mapping (provided by AI)
#   - Audio file path
#   - Desired output path
#
# To produce a complete timeline.json ready for podcast-maker.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_usage() {
    echo "Usage: $0 <segments_json> <image_mapping_json> <audio_file> <output_mp4>"
    echo ""
    echo "Generate timeline JSON from analyzed segments and image mapping"
    echo ""
    echo "Arguments:"
    echo "  segments_json       Output from analyze-segments.sh (file or stdin with -)"
    echo "  image_mapping_json  JSON mapping segment indices to image paths"
    echo "  audio_file          Path to the audio file"
    echo "  output_mp4          Desired output video path"
    echo ""
    echo "Image mapping format:"
    echo '  {'
    echo '    "1": "/path/to/intro.jpg",'
    echo '    "2": "/path/to/main.jpg",'
    echo '    "3": "/path/to/outro.jpg"'
    echo '  }'
    echo ""
    echo "Or array format (images in order):"
    echo '  ["/path/to/intro.jpg", "/path/to/main.jpg", "/path/to/outro.jpg"]'
    echo ""
    echo "Output:"
    echo "  Complete timeline.json printed to stdout"
    echo ""
    echo "Example:"
    echo "  # Using pipe from analyze-segments.sh"
    echo "  ./analyze-segments.sh audio.vtt 3 | \\"
    echo "    ./generate-timeline.sh - mapping.json audio.mp3 output.mp4 > timeline.json"
}

# Get audio duration
get_audio_duration() {
    local audio_file="$1"
    ffprobe -v error -show_entries format=duration -of csv=p=0 "$audio_file" 2>/dev/null || echo "0"
}

# Main function
generate_timeline() {
    local segments_source="$1"
    local mapping_source="$2"
    local audio_file="$3"
    local output_file="$4"
    
    # Read segments JSON
    local segments_json
    if [[ "$segments_source" == "-" ]]; then
        segments_json=$(cat)
    else
        if [[ ! -f "$segments_source" ]]; then
            log_error "Segments file not found: $segments_source"
            exit 1
        fi
        segments_json=$(cat "$segments_source")
    fi
    
    # Read image mapping JSON
    local mapping_json
    if [[ ! -f "$mapping_source" ]]; then
        log_error "Image mapping file not found: $mapping_source"
        exit 1
    fi
    mapping_json=$(cat "$mapping_source")
    
    # Check audio file
    if [[ ! -f "$audio_file" ]]; then
        log_error "Audio file not found: $audio_file"
        exit 1
    fi
    
    # Get absolute paths
    audio_file=$(realpath "$audio_file")
    
    # Determine output directory and create if needed
    local output_dir
    output_dir=$(dirname "$output_file")
    if [[ "$output_dir" != "." ]] && [[ ! -d "$output_dir" ]]; then
        mkdir -p "$output_dir"
    fi
    output_file=$(realpath "$output_file" 2>/dev/null || echo "$output_file")
    
    # Get VTT file path from segments
    local vtt_file
    vtt_file=$(echo "$segments_json" | jq -r '.vtt_file')
    
    if [[ ! -f "$vtt_file" ]]; then
        log_error "VTT file not found: $vtt_file"
        exit 1
    fi
    
    # Get actual audio duration
    local audio_duration
    audio_duration=$(get_audio_duration "$audio_file")
    log_info "Audio duration: ${audio_duration}s"
    
    # Check if mapping is array or object
    local is_array
    is_array=$(echo "$mapping_json" | jq 'type == "array"')
    
    # Extract segments and build timeline
    local segments
    segments=$(echo "$segments_json" | jq '.segments')
    
    local num_segments
    num_segments=$(echo "$segments" | jq 'length')
    
    local timeline_segments="[]"
    
    for ((i = 0; i < num_segments; i++)); do
        local seg
        seg=$(echo "$segments" | jq ".[$i]")
        
        local seg_index start_seconds end_seconds
        seg_index=$(echo "$seg" | jq '.segment_index')
        start_seconds=$(echo "$seg" | jq '.start_seconds')
        end_seconds=$(echo "$seg" | jq '.end_seconds')
        
        # Get image for this segment
        local image_path
        if [[ "$is_array" == "true" ]]; then
            image_path=$(echo "$mapping_json" | jq -r ".[$i]")
        else
            image_path=$(echo "$mapping_json" | jq -r ".[\"$seg_index\"] // .[\"$i\"] // .[$i]")
        fi
        
        if [[ -z "$image_path" ]] || [[ "$image_path" == "null" ]]; then
            log_error "No image mapping for segment $seg_index"
            exit 1
        fi
        
        # Convert to absolute path
        if [[ -f "$image_path" ]]; then
            image_path=$(realpath "$image_path")
        else
            log_error "Image not found: $image_path"
            exit 1
        fi
        
        # Adjust last segment to end at audio duration
        if [[ $i -eq $((num_segments - 1)) ]]; then
            end_seconds="$audio_duration"
        fi
        
        # Get text preview as description
        local description
        description=$(echo "$seg" | jq -r '.text_preview // "Segment \(.segment_index)"' | head -c 100)
        
        # Add to timeline
        timeline_segments=$(echo "$timeline_segments" | jq \
            --arg image "$image_path" \
            --arg start "$start_seconds" \
            --arg end "$end_seconds" \
            --arg desc "$description" \
            '. + [{
                "image": $image,
                "start": ($start | tonumber),
                "end": ($end | tonumber),
                "description": $desc
            }]')
    done
    
    # Build final timeline
    jq -n \
        --arg audio "$audio_file" \
        --arg vtt "$vtt_file" \
        --arg output "$output_file" \
        --argjson segments "$timeline_segments" \
        '{
            "audio_file": $audio,
            "vtt_file": $vtt,
            "output_file": $output,
            "resolution": "1920x1080",
            "fade_duration": 0.5,
            "segments": $segments
        }'
}

# Main entry point
main() {
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        print_usage
        exit 0
    fi
    
    if [[ $# -lt 4 ]]; then
        log_error "Missing required arguments"
        echo ""
        print_usage
        exit 1
    fi
    
    # Check dependencies
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Install with: apt install jq or brew install jq"
        exit 1
    fi
    
    if ! command -v ffprobe &> /dev/null; then
        log_error "ffprobe is not installed. Install ffmpeg package."
        exit 1
    fi
    
    generate_timeline "$1" "$2" "$3" "$4"
}

main "$@"
