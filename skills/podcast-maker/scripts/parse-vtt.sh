#!/bin/bash
#
# parse-vtt.sh - Parse VTT file into structured JSON for timeline analysis
#
# Usage: ./parse-vtt.sh <vtt_file>
#
# Output:
#   JSON with cues array, each containing:
#   - index: cue number (1-based)
#   - start_seconds: start time in seconds (float)
#   - end_seconds: end time in seconds (float)
#   - start_formatted: original timestamp (HH:MM:SS.mmm)
#   - end_formatted: original timestamp (HH:MM:SS.mmm)
#   - text: subtitle text content
#
# This helps AI accurately identify time boundaries for semantic image transitions.
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
    echo "Usage: $0 <vtt_file>"
    echo ""
    echo "Parse VTT file into structured JSON for timeline analysis"
    echo ""
    echo "Arguments:"
    echo "  vtt_file    Path to the VTT subtitle file"
    echo ""
    echo "Output:"
    echo "  JSON object with:"
    echo "    - total_duration: duration of last cue end time (seconds)"
    echo "    - cue_count: total number of cues"
    echo "    - cues: array of cue objects with timestamps and text"
    echo ""
    echo "Example output:"
    echo '  {'
    echo '    "total_duration": 125.5,'
    echo '    "cue_count": 42,'
    echo '    "cues": ['
    echo '      {"index": 1, "start_seconds": 0.0, "end_seconds": 3.5, ...},'
    echo '      ...'
    echo '    ]'
    echo '  }'
}

# Main parsing function
parse_vtt() {
    local vtt_file="$1"
    
    if [[ ! -f "$vtt_file" ]]; then
        log_error "VTT file not found: $vtt_file"
        exit 1
    fi
    
    local cues_json
    if ! cues_json=$(parse_vtt_cues_array "$vtt_file"); then
        log_error "Failed to parse VTT file: $vtt_file"
        exit 1
    fi

    local cue_count last_end_seconds
    cue_count=$(echo "$cues_json" | jq 'length')
    last_end_seconds=$(echo "$cues_json" | jq 'if length == 0 then 0 else .[-1].end_seconds end')
    
    # Build final JSON output
    echo "$cues_json" | jq --arg duration "$last_end_seconds" --arg count "$cue_count" '{
        "total_duration": ($duration | tonumber),
        "cue_count": ($count | tonumber),
        "cues": .
    }'
}

# Main entry point
main() {
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        print_usage
        exit 0
    fi
    
    if [[ $# -lt 1 ]]; then
        log_error "Missing required argument: vtt_file"
        echo ""
        print_usage
        exit 1
    fi
    
    # Check jq is available
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Install with: apt install jq or brew install jq"
        exit 1
    fi
    
    parse_vtt "$1"
}

main "$@"
