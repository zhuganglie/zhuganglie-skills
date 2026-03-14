#!/bin/bash
#
# vtt-utils.sh - Shared helpers for robust WebVTT parsing
#

trim_whitespace() {
    local value="$1"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    printf '%s\n' "$value"
}

# Convert WebVTT timestamp (HH:MM:SS.mmm or MM:SS.mmm) to seconds.
timestamp_to_seconds() {
    local ts
    ts=$(trim_whitespace "$1")
    ts="${ts//,/.}"

    local hours="0"
    local minutes="0"
    local seconds=""

    if [[ "$ts" =~ ^([0-9]+):([0-9]{2}):([0-9]{2}(\.[0-9]+)?)$ ]]; then
        hours="${BASH_REMATCH[1]}"
        minutes="${BASH_REMATCH[2]}"
        seconds="${BASH_REMATCH[3]}"
    elif [[ "$ts" =~ ^([0-9]+):([0-9]{2}(\.[0-9]+)?)$ ]]; then
        minutes="${BASH_REMATCH[1]}"
        seconds="${BASH_REMATCH[2]}"
    else
        return 1
    fi

    hours=$((10#$hours))
    minutes=$((10#$minutes))

    awk "BEGIN {printf \"%.3f\", $hours * 3600 + $minutes * 60 + $seconds}"
}

# Extract start and end timestamps from a WebVTT cue timing line.
extract_vtt_timestamps() {
    local line="$1"

    if [[ "$line" != *"-->"* ]]; then
        return 1
    fi

    local start_part rest end_part
    start_part=$(trim_whitespace "${line%%-->*}")
    rest=$(trim_whitespace "${line#*-->}")
    read -r end_part _ <<< "$rest"

    if [[ -z "$start_part" || -z "$end_part" ]]; then
        return 1
    fi

    printf '%s\t%s\n' "$start_part" "$end_part"
}

append_vtt_cue() {
    local cues_json="$1"
    local cue_index="$2"
    local start_formatted="$3"
    local end_formatted="$4"
    local text="$5"

    local start_seconds end_seconds
    if ! start_seconds=$(timestamp_to_seconds "$start_formatted"); then
        return 1
    fi

    if ! end_seconds=$(timestamp_to_seconds "$end_formatted"); then
        return 1
    fi

    printf '%s\n' "$cues_json" | jq -c \
        --argjson idx "$cue_index" \
        --arg start_sec "$start_seconds" \
        --arg end_sec "$end_seconds" \
        --arg start_fmt "$start_formatted" \
        --arg end_fmt "$end_formatted" \
        --arg text "$text" \
        '. + [{
            "index": $idx,
            "start_seconds": ($start_sec | tonumber),
            "end_seconds": ($end_sec | tonumber),
            "start_formatted": $start_fmt,
            "end_formatted": $end_fmt,
            "text": $text
        }]'
}

# Parse a WebVTT file into a JSON array of cues.
parse_vtt_cues_array() {
    local vtt_file="$1"

    if [[ ! -f "$vtt_file" ]]; then
        return 1
    fi

    local cues_json="[]"
    local cue_index=0
    local current_start=""
    local current_end=""
    local current_text=""
    local in_cue=false
    local skip_block=false

    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
        local line trimmed
        line="${raw_line//$'\r'/}"
        trimmed=$(trim_whitespace "$line")

        if [[ "$skip_block" == true ]]; then
            if [[ -z "$trimmed" ]]; then
                skip_block=false
            fi
            continue
        fi

        if [[ -z "$trimmed" ]]; then
            continue
        fi

        if [[ "$trimmed" == "WEBVTT"* ]]; then
            continue
        fi

        if [[ "$trimmed" == "NOTE"* ]] || [[ "$trimmed" == "STYLE"* ]] || [[ "$trimmed" == "REGION"* ]]; then
            skip_block=true
            continue
        fi

        if [[ "$trimmed" == *"-->"* ]]; then
            if [[ "$in_cue" == true ]] && [[ -n "$current_start" ]]; then
                if ! cues_json=$(append_vtt_cue "$cues_json" "$cue_index" "$current_start" "$current_end" "$current_text"); then
                    return 1
                fi
            fi

            local parsed_timestamps
            if ! parsed_timestamps=$(extract_vtt_timestamps "$trimmed"); then
                return 1
            fi

            cue_index=$((cue_index + 1))
            current_start="${parsed_timestamps%%$'\t'*}"
            current_end="${parsed_timestamps#*$'\t'}"
            current_text=""
            in_cue=true
            continue
        fi

        if [[ "$in_cue" == true ]]; then
            current_text="${current_text:+$current_text }$trimmed"
        fi
    done < "$vtt_file"

    if [[ "$in_cue" == true ]] && [[ -n "$current_start" ]]; then
        if ! cues_json=$(append_vtt_cue "$cues_json" "$cue_index" "$current_start" "$current_end" "$current_text"); then
            return 1
        fi
    fi

    printf '%s\n' "$cues_json"
}
