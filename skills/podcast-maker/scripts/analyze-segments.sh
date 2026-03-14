#!/bin/bash
#
# analyze-segments.sh - Analyze VTT content and suggest semantic segments
#
# Usage: ./analyze-segments.sh <vtt_file> <num_segments>
#
# This script divides the VTT content into N segments based on:
#   1. Time distribution (roughly equal duration per segment)
#   2. Natural break points (gaps between cues)
#   3. Cue boundaries (never split in middle of a cue)
#
# The AI should then refine these segments based on semantic content.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vtt-utils.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_usage() {
    echo "Usage: $0 <vtt_file> <num_segments>"
    echo ""
    echo "Analyze VTT content and suggest semantic segments"
    echo ""
    echo "Arguments:"
    echo "  vtt_file       Path to the VTT subtitle file"
    echo "  num_segments   Number of segments to divide into (usually = number of images)"
    echo ""
    echo "Output:"
    echo "  JSON with suggested segments, each containing:"
    echo "  - segment_index: segment number (1-based)"
    echo "  - start_seconds: suggested start time"
    echo "  - end_seconds: suggested end time"
    echo "  - start_cue: first VTT cue index in this segment"
    echo "  - end_cue: last VTT cue index in this segment"
    echo "  - cue_count: number of cues in this segment"
    echo "  - text_preview: first ~200 characters of text in segment"
    echo "  - duration: segment duration in seconds"
    echo ""
    echo "The AI should use this as a starting point, then:"
    echo "  1. Review text_preview to understand segment content"
    echo "  2. Match each segment with the most appropriate image"
    echo "  3. Adjust boundaries if needed for semantic coherence"
}

# Find natural break points (larger gaps between cues)
find_break_points() {
    local cues="$1"
    local num_segments="$2"
    
    local cue_count
    cue_count=$(echo "$cues" | jq 'length')
    
    if [[ $cue_count -eq 0 ]]; then
        echo "[]"
        return
    fi
    
    # Calculate total duration and target segment duration
    local first_start last_end total_duration target_duration
    first_start=$(echo "$cues" | jq '.[0].start_seconds')
    last_end=$(echo "$cues" | jq '.[-1].end_seconds')
    total_duration=$(awk "BEGIN {print $last_end - $first_start}")
    target_duration=$(awk "BEGIN {print $total_duration / $num_segments}")
    
    # Find break points - choose cues that are closest to target boundaries
    local break_points="[0]"  # Always start at first cue
    local current_target="$target_duration"
    
    for ((seg = 1; seg < num_segments; seg++)); do
        local best_cue=0
        local best_diff=999999
        
        # Find cue whose start time is closest to target
        for ((i = 1; i < cue_count; i++)); do
            local cue_start
            cue_start=$(echo "$cues" | jq ".[$i].start_seconds")
            local diff
            diff=$(awk "BEGIN {d = $cue_start - $current_target; if (d < 0) d = -d; print d}")
            
            if awk "BEGIN {exit !($diff < $best_diff)}"; then
                best_diff=$diff
                best_cue=$i
            fi
        done
        
        # Add this cue as a break point if it's not already added
        local already_added
        already_added=$(echo "$break_points" | jq "contains([$best_cue])")
        if [[ "$already_added" == "false" ]]; then
            break_points=$(echo "$break_points" | jq ". + [$best_cue]")
        fi
        
        current_target=$(awk "BEGIN {print $current_target + $target_duration}")
    done
    
    # Sort and return
    echo "$break_points" | jq 'sort'
}

# Generate segments from break points
generate_segments() {
    local cues="$1"
    local break_points="$2"
    local total_duration="$3"
    
    local num_breaks
    num_breaks=$(echo "$break_points" | jq 'length')
    
    local cue_count
    cue_count=$(echo "$cues" | jq 'length')
    
    local segments="[]"
    
    for ((i = 0; i < num_breaks; i++)); do
        local start_cue end_cue
        start_cue=$(echo "$break_points" | jq ".[$i]")
        
        if [[ $i -lt $((num_breaks - 1)) ]]; then
            end_cue=$(echo "$break_points" | jq ".[$((i + 1))]")
            end_cue=$((end_cue - 1))
        else
            end_cue=$((cue_count - 1))
        fi
        
        # Get start and end times
        local start_time end_time
        start_time=$(echo "$cues" | jq ".[$start_cue].start_seconds")
        
        if [[ $i -lt $((num_breaks - 1)) ]]; then
            # End at the start of next segment's first cue
            local next_start_cue
            next_start_cue=$(echo "$break_points" | jq ".[$((i + 1))]")
            end_time=$(echo "$cues" | jq ".[$next_start_cue].start_seconds")
        else
            # Last segment ends at total duration
            end_time="$total_duration"
        fi
        
        # First segment always starts at 0
        if [[ $i -eq 0 ]]; then
            start_time="0"
        fi
        
        # Calculate duration
        local duration
        duration=$(awk "BEGIN {printf \"%.3f\", $end_time - $start_time}")
        
        # Collect text preview (first ~200 chars)
        local text_preview=""
        local char_count=0
        for ((c = start_cue; c <= end_cue && char_count < 200; c++)); do
            local cue_text
            cue_text=$(echo "$cues" | jq -r ".[$c].text")
            text_preview="$text_preview $cue_text"
            char_count=${#text_preview}
        done
        text_preview=$(echo "$text_preview" | sed 's/^ //; s/  */ /g')
        if [[ ${#text_preview} -gt 200 ]]; then
            text_preview="${text_preview:0:200}..."
        fi
        
        # Calculate cue count in this segment
        local cue_count_in_seg=$((end_cue - start_cue + 1))
        
        # Add segment
        segments=$(echo "$segments" | jq \
            --argjson idx "$((i + 1))" \
            --arg start "$start_time" \
            --arg end "$end_time" \
            --argjson start_cue "$((start_cue + 1))" \
            --argjson end_cue "$((end_cue + 1))" \
            --argjson cue_count "$cue_count_in_seg" \
            --arg duration "$duration" \
            --arg preview "$text_preview" \
            '. + [{
                "segment_index": $idx,
                "start_seconds": ($start | tonumber),
                "end_seconds": ($end | tonumber),
                "start_cue": $start_cue,
                "end_cue": $end_cue,
                "cue_count": $cue_count,
                "duration": ($duration | tonumber),
                "text_preview": $preview,
                "suggested_image": "AI_MUST_ASSIGN: Which image matches this content?"
            }]')
    done
    
    echo "$segments"
}

# Main function
analyze_segments() {
    local vtt_file="$1"
    local num_segments="$2"
    
    if [[ ! -f "$vtt_file" ]]; then
        log_error "VTT file not found: $vtt_file"
        exit 1
    fi
    
    if [[ ! "$num_segments" =~ ^[0-9]+$ ]] || [[ "$num_segments" -lt 1 ]]; then
        log_error "num_segments must be a positive integer"
        exit 1
    fi
    
    # Parse VTT
    local cues
    if ! cues=$(parse_vtt_cues_array "$vtt_file"); then
        log_error "Failed to parse VTT file: $vtt_file"
        exit 1
    fi
    
    local cue_count
    cue_count=$(echo "$cues" | jq 'length')
    
    if [[ $cue_count -eq 0 ]]; then
        log_error "No cues found in VTT file"
        exit 1
    fi
    
    # Get total duration
    local total_duration
    total_duration=$(echo "$cues" | jq '.[-1].end_seconds')
    
    # Find break points
    local break_points
    break_points=$(find_break_points "$cues" "$num_segments")
    
    # Generate segments
    local segments
    segments=$(generate_segments "$cues" "$break_points" "$total_duration")
    
    # Build final output
    jq -n \
        --arg vtt_file "$(realpath "$vtt_file")" \
        --argjson total_duration "$total_duration" \
        --argjson cue_count "$cue_count" \
        --argjson num_segments "$num_segments" \
        --argjson segments "$segments" \
        '{
            "vtt_file": $vtt_file,
            "total_duration": $total_duration,
            "total_cues": $cue_count,
            "num_segments": $num_segments,
            "instructions": "AI should: 1) Review each segment text_preview, 2) Match with appropriate image based on content, 3) Adjust boundaries if needed for semantic coherence",
            "segments": $segments
        }'
}

# Main entry point
main() {
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        print_usage
        exit 0
    fi
    
    if [[ $# -lt 2 ]]; then
        log_error "Missing required arguments"
        echo ""
        print_usage
        exit 1
    fi
    
    # Check jq is available
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Install with: apt install jq or brew install jq"
        exit 1
    fi
    
    analyze_segments "$1" "$2"
}

main "$@"
