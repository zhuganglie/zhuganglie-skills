#!/bin/bash
#
# regression-test.sh - End-to-end regression checks for podcast-maker
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d /tmp/podcast-maker-regression.XXXXXX)"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

log() {
    printf '[TEST] %s\n' "$1"
}

fail() {
    printf '[FAIL] %s\n' "$1" >&2
    exit 1
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        fail "Missing dependency: $1"
    fi
}

assert_close() {
    local actual="$1"
    local expected="$2"
    local tolerance="$3"
    local label="$4"

    local diff
    diff=$(awk "BEGIN {d = $actual - $expected; if (d < 0) d = -d; print d}")
    if ! awk "BEGIN {exit !($diff <= $tolerance)}"; then
        fail "$label differs too much: actual=$actual expected=$expected tolerance=$tolerance"
    fi
}

require_command ffmpeg
require_command ffprobe
require_command jq

log "Creating synthetic fixtures in $TMP_DIR"
ffmpeg -y -f lavfi -i color=c=red:s=1280x720:d=0.1 -frames:v 1 -update 1 "$TMP_DIR/red.jpg" >/dev/null 2>&1
ffmpeg -y -f lavfi -i color=c=blue:s=1280x720:d=0.1 -frames:v 1 -update 1 "$TMP_DIR/blue.jpg" >/dev/null 2>&1
ffmpeg -y -f lavfi -i sine=frequency=1000:duration=4 "$TMP_DIR/test.wav" >/dev/null 2>&1

cat > "$TMP_DIR/settings.vtt" <<'EOF'
WEBVTT

00:00.000 --> 00:02.000 align:start position:0%
Hello

00:02.000 --> 00:04.000 line:90%
World
EOF

cat > "$TMP_DIR/mapping.json" <<EOF
{
  "mappings": [
    {
      "image": "$TMP_DIR/red.jpg",
      "start_cue": 1,
      "end_cue": 1,
      "description": "Intro"
    },
    {
      "image": "$TMP_DIR/blue.jpg",
      "start_cue": 2,
      "end_cue": -1,
      "description": "Outro"
    }
  ]
}
EOF

cat > "$TMP_DIR/bad-mapping.json" <<EOF
{
  "mappings": [
    {
      "image": "$TMP_DIR/red.jpg",
      "start_cue": 1,
      "end_cue": 999,
      "description": "Broken"
    },
    {
      "image": "$TMP_DIR/blue.jpg",
      "start_cue": 2,
      "end_cue": -1,
      "description": "Outro"
    }
  ]
}
EOF

log "Parsing WebVTT with cue settings"
parse_output="$("$SCRIPT_DIR/parse-vtt.sh" "$TMP_DIR/settings.vtt")"
[[ "$(echo "$parse_output" | jq -r '.cue_count')" == "2" ]] || fail "parse-vtt.sh did not return two cues"

log "Analyzing segments with 1-based cue numbering"
segment_output="$("$SCRIPT_DIR/analyze-segments.sh" "$TMP_DIR/settings.vtt" 2)"
[[ "$(echo "$segment_output" | jq -r '.segments[0].start_cue')" == "1" ]] || fail "analyze-segments.sh start_cue is not 1-based"
[[ "$(echo "$segment_output" | jq -r '.segments[0].end_cue')" == "1" ]] || fail "analyze-segments.sh end_cue is not 1-based"

log "Generating cue-based timeline"
"$SCRIPT_DIR/cue-based-timeline.sh" \
    "$TMP_DIR/settings.vtt" \
    "$TMP_DIR/mapping.json" \
    "$TMP_DIR/test.wav" \
    "$TMP_DIR/out.mp4" > "$TMP_DIR/timeline.json"

log "Validating cue-based timeline"
"$SCRIPT_DIR/validate-timeline.sh" "$TMP_DIR/timeline.json" >/dev/null

log "Rejecting invalid cue mappings"
if "$SCRIPT_DIR/cue-based-timeline.sh" \
    "$TMP_DIR/settings.vtt" \
    "$TMP_DIR/bad-mapping.json" \
    "$TMP_DIR/test.wav" \
    "$TMP_DIR/should-not-exist.mp4" > /dev/null 2>&1; then
    fail "cue-based-timeline.sh accepted an invalid end_cue"
fi

log "Generating final video"
"$SCRIPT_DIR/podcast-maker.sh" "$TMP_DIR/timeline.json" >/dev/null
[[ -f "$TMP_DIR/out.mp4" ]] || fail "podcast-maker.sh did not create output file"

log "Checking output duration and subtitle stream"
audio_duration="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$TMP_DIR/test.wav")"
video_duration="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$TMP_DIR/out.mp4")"
subtitle_streams="$(ffprobe -v error -select_streams s -show_entries stream=index -of csv=p=0 "$TMP_DIR/out.mp4" | wc -l | tr -d ' ')"

assert_close "$video_duration" "$audio_duration" "0.1" "output duration"
[[ "$subtitle_streams" -ge 1 ]] || fail "output file is missing subtitle streams"

log "All regression checks passed"
