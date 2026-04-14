#!/bin/bash
#
# vtt-utils.sh - Shared helpers for robust WebVTT parsing
#

# Parse a WebVTT file into a JSON array of cues.
parse_vtt_cues_array() {
    local vtt_file="$1"

    if [[ ! -f "$vtt_file" ]]; then
        return 1
    fi

    # Read VTT line by line and construct a JSON stream of objects using awk,
    # then slurp them into a single JSON array using jq -s.
    awk '
    function trim(s) {
        sub(/^[ \t\r\n]+/, "", s)
        sub(/[ \t\r\n]+$/, "", s)
        return s
    }
    function ts2sec(ts) {
        gsub(/,/, ".", ts)
        n = split(ts, parts, ":")
        if (n == 3) {
            return parts[1] * 3600 + parts[2] * 60 + parts[3]
        } else if (n == 2) {
            return parts[1] * 60 + parts[2]
        }
        return 0
    }
    function escape_json(str) {
        gsub(/\\/, "\\\\", str)
        gsub(/"/, "\\\"", str)
        gsub(/\n/, "\\n", str)
        gsub(/\r/, "", str)
        gsub(/\t/, "\\t", str)
        return str
    }
    BEGIN {
        cue_index = 1
        has_cue = 0
    }
    {
        line = $0
        sub(/\r$/, "", line)
        trimmed = trim(line)
        
        if (skip_block) {
            if (trimmed == "") skip_block = 0
            next
        }
        
        if (trimmed == "") {
            in_text = 0
            next
        }
        
        if (trimmed ~ /^WEBVTT/) next
        
        if (trimmed ~ /^NOTE/ || trimmed ~ /^STYLE/ || trimmed ~ /^REGION/) {
            skip_block = 1
            next
        }
        
        if (trimmed ~ /-->/) {
            if (has_cue) {
                # Print previous cue as a JSON object
                printf "{\"index\": %d, \"start_seconds\": %.3f, \"end_seconds\": %.3f, \"start_formatted\": \"%s\", \"end_formatted\": \"%s\", \"text\": \"%s\"}\n", cue_index, start_sec, end_sec, start_fmt, end_fmt, escape_json(text)
                cue_index++
            }
            
            # Split the timestamp line
            # Format: 00:00:01.000 --> 00:00:02.000 align:start size:15%
            idx = index(trimmed, "-->")
            start_fmt = trim(substr(trimmed, 1, idx - 1))
            
            rest = trim(substr(trimmed, idx + 3))
            split(rest, end_parts, " ")
            end_fmt = trim(end_parts[1])
            
            start_sec = ts2sec(start_fmt)
            end_sec = ts2sec(end_fmt)
            
            text = ""
            has_cue = 1
            in_text = 1
            next
        }
        
        if (in_text) {
            if (text != "") text = text " "
            text = text trimmed
        }
    }
    END {
        if (has_cue) {
            printf "{\"index\": %d, \"start_seconds\": %.3f, \"end_seconds\": %.3f, \"start_formatted\": \"%s\", \"end_formatted\": \"%s\", \"text\": \"%s\"}\n", cue_index, start_sec, end_sec, start_fmt, end_fmt, escape_json(text)
        }
    }' "$vtt_file" | jq -s .
}
