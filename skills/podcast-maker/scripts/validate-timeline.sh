#!/bin/bash
#
# validate-timeline.sh - Validate timeline JSON against VTT and audio
#
# Usage: ./validate-timeline.sh <timeline.json> [--fix]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vtt-utils.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Tolerance for time matching (seconds)
TIME_TOLERANCE=0.05

log_info() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[CHECK]${NC} $1"
}

print_usage() {
    echo "Usage: $0 <timeline.json> [--fix]"
    echo ""
    echo "Validate timeline JSON for podcast video generation"
    echo ""
    echo "Arguments:"
    echo "  timeline.json   Path to the timeline JSON file"
    echo ""
    echo "Options:"
    echo "  --fix           Auto-fix last segment end time to match audio duration"
    echo ""
    echo "Validates:"
    echo "  - Timeline JSON structure and required files"
    echo "  - Segment contiguity and first/last timing"
    echo "  - Cue boundary alignment"
    echo "  - cue_range coverage for cue-based timelines"
    echo "  - Crossfade-safe segment durations"
}

abs_diff() {
    awk "BEGIN {d = $1 - $2; if (d < 0) d = -d; print d}"
}

times_match() {
    local diff
    diff=$(abs_diff "$1" "$2")
    awk "BEGIN {exit !($diff <= $TIME_TOLERANCE)}"
}

is_positive_number() {
    [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

is_number() {
    [[ "$1" =~ ^-?[0-9]+([.][0-9]+)?$ ]]
}

find_nearest_boundary() {
    local time="$1"
    shift
    local boundaries=("$@")

    local nearest=""
    local min_diff=999999

    for boundary in "${boundaries[@]}"; do
        local diff
        diff=$(abs_diff "$time" "$boundary")
        if awk "BEGIN {exit !($diff < $min_diff)}"; then
            min_diff=$diff
            nearest=$boundary
        fi
    done

    printf '%s\n' "$nearest"
}

validate_timeline() {
    local timeline_file="$1"
    local fix_mode="${2:-false}"

    local errors=0
    local warnings=0

    echo ""
    echo "========================================"
    echo "   Timeline Validation Report"
    echo "========================================"
    echo ""

    log_step "Checking timeline file exists..."
    if [[ ! -f "$timeline_file" ]]; then
        log_error "Timeline file not found: $timeline_file"
        exit 1
    fi
    log_info "Timeline file found"

    log_step "Validating JSON syntax..."
    if ! jq empty "$timeline_file" 2>/dev/null; then
        log_error "Invalid JSON in timeline file"
        exit 1
    fi
    log_info "JSON syntax valid"

    local audio_file vtt_file fade_duration segment_count
    audio_file=$(jq -r '.audio_file // empty' "$timeline_file")
    vtt_file=$(jq -r '.vtt_file // empty' "$timeline_file")
    fade_duration=$(jq -r '.fade_duration // 0.5' "$timeline_file")
    segment_count=$(jq '.segments | length' "$timeline_file")

    if [[ -z "$audio_file" || -z "$vtt_file" ]]; then
        log_error "Timeline must include audio_file and vtt_file"
        exit 1
    fi

    if [[ "$segment_count" -lt 1 ]]; then
        log_error "Timeline must include at least one segment"
        exit 1
    fi

    if ! is_positive_number "$fade_duration"; then
        log_error "fade_duration must be a non-negative number"
        exit 1
    fi

    log_step "Checking audio file..."
    if [[ ! -f "$audio_file" ]]; then
        log_error "Audio file not found: $audio_file"
        ((errors++))
    else
        log_info "Audio file found: $audio_file"
    fi

    log_step "Checking VTT file..."
    if [[ ! -f "$vtt_file" ]]; then
        log_error "VTT file not found: $vtt_file"
        ((errors++))
    else
        log_info "VTT file found: $vtt_file"
    fi

    if (( errors > 0 )); then
        echo ""
        log_error "Cannot continue validation until missing files are fixed"
        return 1
    fi

    log_step "Getting audio duration..."
    local audio_duration
    audio_duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$audio_file" 2>/dev/null || echo "")
    if ! is_positive_number "$audio_duration"; then
        log_error "Could not determine audio duration"
        return 1
    fi
    log_info "Audio duration: ${audio_duration}s"

    log_step "Parsing VTT cues..."
    local cues
    if ! cues=$(parse_vtt_cues_array "$vtt_file"); then
        log_error "Failed to parse VTT cues from: $vtt_file"
        return 1
    fi

    local total_cues
    total_cues=$(echo "$cues" | jq 'length')
    if [[ "$total_cues" -lt 1 ]]; then
        log_error "No cues found in VTT file"
        return 1
    fi
    log_info "Found $total_cues VTT cues"

    local vtt_boundaries=()
    mapfile -t vtt_boundaries < <(echo "$cues" | jq -r '.[].start_seconds')
    if [[ "${vtt_boundaries[0]}" != "0"* ]]; then
        vtt_boundaries=("0.000" "${vtt_boundaries[@]}")
    fi

    local has_full_cue_ranges="false"
    if jq -e '.segments | length > 0 and all(.[]; (.cue_range.start? | type == "number") and (.cue_range.end? | type == "number"))' "$timeline_file" >/dev/null 2>&1; then
        has_full_cue_ranges="true"
    fi

    log_step "Validating segments..."
    log_info "Found $segment_count segments"
    echo ""

    local prev_end="0"
    for ((i = 0; i < segment_count; i++)); do
        local image start end duration
        image=$(jq -r ".segments[$i].image // empty" "$timeline_file")
        start=$(jq -r ".segments[$i].start" "$timeline_file")
        end=$(jq -r ".segments[$i].end" "$timeline_file")

        echo "  Segment $((i + 1)): ${start}s - ${end}s"

        if [[ -z "$image" || ! -f "$image" ]]; then
            log_error "    Image not found: $image"
            ((errors++))
        fi

        if ! is_number "$start" || ! is_number "$end"; then
            log_error "    Segment times must be numeric"
            ((errors++))
            continue
        fi

        duration=$(awk "BEGIN {printf \"%.6f\", $end - $start}")
        if ! awk "BEGIN {exit !($duration > 0)}"; then
            log_error "    Segment duration must be positive"
            ((errors++))
        fi

        if [[ $i -eq 0 ]]; then
            if ! times_match "$start" "0"; then
                log_error "    First segment should start at 0.0, but starts at $start"
                ((errors++))
            fi
        else
            if ! times_match "$start" "$prev_end"; then
                local gap
                gap=$(awk "BEGIN {printf \"%.3f\", $start - $prev_end}")
                log_error "    Gap/overlap detected: previous end=$prev_end, this start=$start (diff=${gap}s)"
                ((errors++))
            fi
        fi

        if [[ $i -lt $((segment_count - 1)) ]]; then
            if ! awk "BEGIN {exit !($duration >= $fade_duration)}"; then
                log_error "    Segment duration $duration is shorter than fade_duration $fade_duration"
                ((errors++))
            fi
        fi

        if [[ "$has_full_cue_ranges" == "false" ]]; then
            if [[ $i -gt 0 ]]; then
                if ! printf '%s\n' "${vtt_boundaries[@]}" | grep -qx "$start"; then
                    local nearest_start
                    nearest_start=$(find_nearest_boundary "$start" "${vtt_boundaries[@]}")
                    log_warn "    Start time $start doesn't align with a cue boundary"
                    log_warn "    Nearest VTT boundary: $nearest_start"
                    ((warnings++))
                fi
            fi

            if [[ $i -lt $((segment_count - 1)) ]]; then
                if ! printf '%s\n' "${vtt_boundaries[@]}" | grep -qx "$end"; then
                    local nearest_end
                    nearest_end=$(find_nearest_boundary "$end" "${vtt_boundaries[@]}")
                    log_warn "    End time $end doesn't align with a cue boundary"
                    log_warn "    Nearest VTT boundary: $nearest_end"
                    ((warnings++))
                fi
            fi
        fi

        prev_end="$end"
    done

    echo ""
    log_step "Checking last segment end time..."
    local last_end
    last_end=$(jq -r ".segments[$((segment_count - 1))].end" "$timeline_file")

    if ! times_match "$last_end" "$audio_duration"; then
        local end_diff
        end_diff=$(abs_diff "$last_end" "$audio_duration")
        log_error "Last segment end ($last_end) doesn't match audio duration ($audio_duration)"
        log_error "Difference: ${end_diff}s"

        if [[ "$fix_mode" == "true" ]]; then
            echo ""
            log_step "Applying fix: updating last segment end time..."
            local fixed_timeline
            fixed_timeline=$(jq --arg dur "$audio_duration" '.segments[-1].end = ($dur | tonumber)' "$timeline_file")
            printf '%s\n' "$fixed_timeline" > "$timeline_file"
            log_info "Fixed: last segment end time updated to $audio_duration"
            last_end="$audio_duration"
        else
            echo "  Suggestion: Use --fix flag or manually set last segment end to $audio_duration"
            ((errors++))
        fi
    else
        log_info "Last segment end time matches audio duration"
    fi

    if [[ "$has_full_cue_ranges" == "true" ]]; then
        echo ""
        log_step "Validating cue_range coverage..."

        local expected_start_cue=1
        for ((i = 0; i < segment_count; i++)); do
            local start_cue end_cue segment_start segment_end expected_start_time expected_end_time
            start_cue=$(jq -r ".segments[$i].cue_range.start" "$timeline_file")
            end_cue=$(jq -r ".segments[$i].cue_range.end" "$timeline_file")
            segment_start=$(jq -r ".segments[$i].start" "$timeline_file")
            segment_end=$(jq -r ".segments[$i].end" "$timeline_file")

            if ! [[ "$start_cue" =~ ^[0-9]+$ && "$end_cue" =~ ^[0-9]+$ ]]; then
                log_error "Segment $((i + 1)) has a non-numeric cue_range"
                ((errors++))
                continue
            fi

            if (( start_cue != expected_start_cue )); then
                log_error "Segment $((i + 1)) should start at cue $expected_start_cue, got $start_cue"
                ((errors++))
            fi

            if (( end_cue < start_cue || end_cue > total_cues )); then
                log_error "Segment $((i + 1)) has invalid cue_range $start_cue-$end_cue"
                ((errors++))
                continue
            fi

            if [[ $i -eq 0 ]]; then
                expected_start_time="0"
            else
                expected_start_time=$(echo "$cues" | jq ".[$((start_cue - 1))].start_seconds")
            fi

            if [[ $i -lt $((segment_count - 1)) ]]; then
                local next_start_cue
                next_start_cue=$(jq -r ".segments[$((i + 1))].cue_range.start" "$timeline_file")
                expected_end_time=$(echo "$cues" | jq ".[$((next_start_cue - 1))].start_seconds")
            else
                expected_end_time="$audio_duration"
            fi

            if ! times_match "$segment_start" "$expected_start_time"; then
                log_error "Segment $((i + 1)) start time $segment_start doesn't match cue $start_cue boundary $expected_start_time"
                ((errors++))
            fi

            if ! times_match "$segment_end" "$expected_end_time"; then
                log_error "Segment $((i + 1)) end time $segment_end doesn't match expected boundary $expected_end_time"
                ((errors++))
            fi

            expected_start_cue=$((end_cue + 1))
        done

        if (( expected_start_cue != total_cues + 1 )); then
            log_error "cue_range coverage stops early; expected to cover cue $total_cues"
            ((errors++))
        else
            log_info "cue_range coverage is contiguous and complete"
        fi
    fi

    echo ""
    echo "========================================"
    echo "   Summary"
    echo "========================================"
    echo ""

    if [[ $errors -eq 0 ]] && [[ $warnings -eq 0 ]]; then
        log_info "Timeline is valid!"
        echo ""
        return 0
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "Found $errors error(s)"
    fi

    if [[ $warnings -gt 0 ]]; then
        log_warn "Found $warnings warning(s)"
        echo ""
        echo "Warnings mean the timeline is usable but not perfectly cue-aligned."
        echo "Use: ./scripts/parse-vtt.sh <vtt_file> | jq '.cues[] | {index, start_seconds, text}'"
    fi

    echo ""

    if [[ $errors -gt 0 ]]; then
        return 1
    fi

    return 0
}

main() {
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        print_usage
        exit 0
    fi

    if [[ $# -lt 1 ]]; then
        log_error "Missing required argument: timeline.json"
        echo ""
        print_usage
        exit 1
    fi

    if ! command -v ffprobe &> /dev/null; then
        log_error "ffprobe is not installed. Install ffmpeg package."
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Install with: apt install jq or brew install jq"
        exit 1
    fi

    local timeline_file="$1"
    local fix_mode="false"

    if [[ "${2:-}" == "--fix" ]]; then
        fix_mode="true"
    fi

    validate_timeline "$timeline_file" "$fix_mode"
}

main "$@"
