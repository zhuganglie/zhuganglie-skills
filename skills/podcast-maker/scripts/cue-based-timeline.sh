#!/bin/bash
#
# cue-based-timeline.sh - Generate precise timeline from cue-based image mapping
#
# Usage: ./cue-based-timeline.sh <vtt_file> <cue_mapping_json> <audio_file> <output_mp4>
#
# This script creates a timeline where image transitions align precisely with
# VTT cue boundaries, ensuring semantic alignment between visuals and audio.
#
# The AI specifies which VTT cues correspond to each image, and this script
# reads the exact timestamps from the VTT file.
#
# Cue mapping format:
#   {
#     "mappings": [
#       {
#         "image": "/path/to/intro.jpg",
#         "start_cue": 1,
#         "end_cue": 12,
#         "description": "Introduction segment"
#       },
#       {
#         "image": "/path/to/main.jpg",
#         "start_cue": 13,
#         "end_cue": -1,  // -1 means until the end
#         "description": "Main content"
#       }
#     ]
#   }
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vtt-utils.sh"

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
    echo "Usage: $0 <vtt_file> <cue_mapping_json> <audio_file> <output_mp4>"
    echo ""
    echo "Generate precise timeline from cue-based image mapping"
    echo ""
    echo "Arguments:"
    echo "  vtt_file          Path to the VTT subtitle file"
    echo "  cue_mapping_json  JSON file with image-to-cue mappings"
    echo "  audio_file        Path to the audio file"
    echo "  output_mp4        Desired output video path"
    echo ""
    echo "Cue mapping format:"
    echo '  {'
    echo '    "mappings": ['
    echo '      {'
    echo '        "image": "/path/to/intro.jpg",'
    echo '        "start_cue": 1,'
    echo '        "end_cue": 12,'
    echo '        "description": "Introduction segment"'
    echo '      },'
    echo '      {'
    echo '        "image": "/path/to/main.jpg",'
    echo '        "start_cue": 13,'
    echo '        "end_cue": -1,'
    echo '        "description": "Main content (until end)"'
    echo '      }'
    echo '    ]'
    echo '  }'
    echo ""
    echo "Notes:"
    echo "  - start_cue: 1-based index of the first VTT cue for this image"
    echo "  - end_cue: 1-based index of the last VTT cue, or -1 for 'until end'"
    echo "  - Image transition occurs at the START of start_cue's timestamp"
    echo "  - Cue indices must be contiguous and cover all cues"
    echo ""
    echo "Output:"
    echo "  Complete timeline.json printed to stdout"
}

# Get audio duration
get_audio_duration() {
    local audio_file="$1"
    ffprobe -v error -show_entries format=duration -of csv=p=0 "$audio_file" 2>/dev/null || echo "0"
}

validate_mapping_structure() {
    local mapping_json="$1"
    local total_cues="$2"

    if ! echo "$mapping_json" | jq -e '.mappings | type == "array" and length > 0' >/dev/null; then
        log_error "Cue mapping must contain a non-empty .mappings array"
        exit 1
    fi

    local mappings num_mappings expected_start_cue
    mappings=$(echo "$mapping_json" | jq '.mappings')
    num_mappings=$(echo "$mappings" | jq 'length')
    expected_start_cue=1

    for ((i = 0; i < num_mappings; i++)); do
        local mapping start_cue end_cue effective_end_cue
        mapping=$(echo "$mappings" | jq ".[$i]")

        if ! echo "$mapping" | jq -e '
            (.image | type == "string" and length > 0) and
            (.start_cue | type == "number") and
            (.end_cue | type == "number")
        ' >/dev/null; then
            log_error "Mapping $((i + 1)) must include image, start_cue, and end_cue"
            exit 1
        fi

        start_cue=$(echo "$mapping" | jq -r '.start_cue')
        end_cue=$(echo "$mapping" | jq -r '.end_cue')

        if ! [[ "$start_cue" =~ ^[0-9]+$ ]]; then
            log_error "Mapping $((i + 1)) has invalid start_cue: $start_cue"
            exit 1
        fi

        if ! [[ "$end_cue" =~ ^-?[0-9]+$ ]]; then
            log_error "Mapping $((i + 1)) has invalid end_cue: $end_cue"
            exit 1
        fi

        if (( start_cue != expected_start_cue )); then
            log_error "Mapping $((i + 1)) must start at cue $expected_start_cue, got $start_cue"
            exit 1
        fi

        if (( start_cue < 1 || start_cue > total_cues )); then
            log_error "Mapping $((i + 1)) start_cue $start_cue is outside valid range 1-$total_cues"
            exit 1
        fi

        if (( end_cue == -1 )); then
            if (( i != num_mappings - 1 )); then
                log_error "Only the last mapping may use end_cue = -1"
                exit 1
            fi
            effective_end_cue="$total_cues"
        else
            if (( end_cue < start_cue || end_cue > total_cues )); then
                log_error "Mapping $((i + 1)) end_cue $end_cue is outside valid range $start_cue-$total_cues"
                exit 1
            fi
            effective_end_cue="$end_cue"
        fi

        if (( i == num_mappings - 1 && effective_end_cue != total_cues )); then
            log_error "Last mapping must end at cue $total_cues or use -1"
            exit 1
        fi

        expected_start_cue=$((effective_end_cue + 1))
    done
}

# Main function
generate_cue_based_timeline() {
    local vtt_file="$1"
    local mapping_file="$2"
    local audio_file="$3"
    local output_file="$4"
    
    # Validate files exist
    if [[ ! -f "$vtt_file" ]]; then
        log_error "VTT file not found: $vtt_file"
        exit 1
    fi
    
    if [[ ! -f "$mapping_file" ]]; then
        log_error "Cue mapping file not found: $mapping_file"
        exit 1
    fi
    
    if [[ ! -f "$audio_file" ]]; then
        log_error "Audio file not found: $audio_file"
        exit 1
    fi
    
    # Get absolute paths
    vtt_file=$(realpath "$vtt_file")
    audio_file=$(realpath "$audio_file")
    
    # Handle output directory
    local output_dir
    output_dir=$(dirname "$output_file")
    if [[ "$output_dir" != "." ]] && [[ ! -d "$output_dir" ]]; then
        mkdir -p "$output_dir"
    fi
    output_file=$(realpath "$output_file" 2>/dev/null || echo "$output_file")
    
    # Parse VTT to get all cues
    log_info "Parsing VTT file..."
    local cues
    if ! cues=$(parse_vtt_cues_array "$vtt_file"); then
        log_error "Failed to parse VTT file: $vtt_file"
        exit 1
    fi
    
    local total_cues
    total_cues=$(echo "$cues" | jq 'length')
    log_info "Found $total_cues cues in VTT"
    
    if [[ $total_cues -eq 0 ]]; then
        log_error "No cues found in VTT file"
        exit 1
    fi
    
    # Get audio duration
    local audio_duration
    audio_duration=$(get_audio_duration "$audio_file")
    log_info "Audio duration: ${audio_duration}s"
    
    # Read cue mapping
    local mapping_json
    mapping_json=$(cat "$mapping_file")
    validate_mapping_structure "$mapping_json" "$total_cues"
    
    local mappings
    mappings=$(echo "$mapping_json" | jq '.mappings')
    
    local num_mappings
    num_mappings=$(echo "$mappings" | jq 'length')
    log_info "Processing $num_mappings image mappings"
    
    # Build timeline segments
    local timeline_segments="[]"
    
    for ((i = 0; i < num_mappings; i++)); do
        local mapping
        mapping=$(echo "$mappings" | jq ".[$i]")
        
        local image_path start_cue end_cue effective_end_cue description
        image_path=$(echo "$mapping" | jq -r '.image')
        start_cue=$(echo "$mapping" | jq '.start_cue')
        end_cue=$(echo "$mapping" | jq '.end_cue')
        description=$(echo "$mapping" | jq -r '.description // "Segment"')

        if [[ "$end_cue" == "-1" ]]; then
            effective_end_cue="$total_cues"
        else
            effective_end_cue="$end_cue"
        fi
        
        # Validate image exists
        if [[ ! -f "$image_path" ]]; then
            log_error "Image not found: $image_path"
            exit 1
        fi
        image_path=$(realpath "$image_path")
        
        # Convert 1-based cue index to 0-based for jq
        local start_idx=$((start_cue - 1))
        
        # Get start time from the start_cue
        if [[ $start_idx -lt 0 ]] || [[ $start_idx -ge $total_cues ]]; then
            log_error "Invalid start_cue $start_cue for mapping $((i+1)) (valid range: 1-$total_cues)"
            exit 1
        fi
        
        local start_seconds
        start_seconds=$(echo "$cues" | jq ".[$start_idx].start_seconds")
        
        # First segment always starts at 0
        if [[ $i -eq 0 ]]; then
            start_seconds="0"
        fi
        
        # Calculate end time
        local end_seconds
        if [[ $end_cue -eq -1 ]]; then
            # -1 means until the end of audio
            end_seconds="$audio_duration"
        else
            # End at the start of the next segment (if there is one)
            if [[ $i -lt $((num_mappings - 1)) ]]; then
                # Get the next mapping's start_cue
                local next_start_cue
                next_start_cue=$(echo "$mappings" | jq ".[$((i+1))].start_cue")
                local next_start_idx=$((next_start_cue - 1))
                end_seconds=$(echo "$cues" | jq ".[$next_start_idx].start_seconds")
            else
                # Last segment ends at audio duration
                end_seconds="$audio_duration"
            fi
        fi
        
        # Build segment
        timeline_segments=$(echo "$timeline_segments" | jq \
            --arg image "$image_path" \
            --arg start "$start_seconds" \
            --arg end "$end_seconds" \
            --arg desc "$description" \
            --argjson start_cue "$start_cue" \
            --argjson end_cue "$effective_end_cue" \
            '. + [{
                "image": $image,
                "start": ($start | tonumber),
                "end": ($end | tonumber),
                "description": $desc,
                "cue_range": {
                    "start": $start_cue,
                    "end": $end_cue
                }
            }]')
        
        log_info "Segment $((i+1)): cues $start_cue-$effective_end_cue → ${start_seconds}s-${end_seconds}s"
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
            "timing_mode": "cue-based",
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
    
    generate_cue_based_timeline "$1" "$2" "$3" "$4"
}

main "$@"
