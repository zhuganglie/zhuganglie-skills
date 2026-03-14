#!/bin/bash
#
# podcast-maker.sh - Generate YouTube podcast video from images and audio
#
# Usage: ./podcast-maker.sh <timeline.json>
#
# The timeline.json file should contain:
#   - audio_file: Path to the audio file
#   - vtt_file: Path to the VTT subtitle file
#   - output_file: Path for the output video
#   - resolution: Video resolution (e.g., "1920x1080")
#   - fade_duration: Fade transition duration in seconds
#   - segments: Array of {image, start, end, description}
#
# Environment variables:
#   FFMPEG_THREADS - Number of encoding threads (default: 0 = auto)
#   FFMPEG_PRESET  - Encoding preset (default: medium)
#   FFMPEG_CRF     - Quality setting, lower = better (default: 23)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
FFMPEG_THREADS="${FFMPEG_THREADS:-0}"
FFMPEG_PRESET="${FFMPEG_PRESET:-medium}"
FFMPEG_CRF="${FFMPEG_CRF:-23}"

print_usage() {
    echo "Usage: $0 <timeline.json>"
    echo ""
    echo "Generate a YouTube podcast video from images and audio"
    echo ""
    echo "Arguments:"
    echo "  timeline.json   JSON file containing video timeline configuration"
    echo ""
    echo "Timeline JSON format:"
    echo "  {"
    echo "    \"audio_file\": \"/path/to/audio.mp3\","
    echo "    \"vtt_file\": \"/path/to/subtitles.vtt\","
    echo "    \"output_file\": \"/path/to/output.mp4\","
    echo "    \"resolution\": \"1920x1080\","
    echo "    \"fade_duration\": 0.5,"
    echo "    \"segments\": ["
    echo "      {\"image\": \"/path/to/img.jpg\", \"start\": 0, \"end\": 120},"
    echo "      ..."
    echo "    ]"
    echo "  }"
    echo ""
    echo "Environment variables:"
    echo "  FFMPEG_THREADS  Encoding threads, 0=auto (default: 0)"
    echo "  FFMPEG_PRESET   Encoding preset (default: medium)"
    echo "  FFMPEG_CRF      Quality, lower=better (default: 23)"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check dependencies
check_dependencies() {
    local missing=()

    if ! command -v ffmpeg &> /dev/null; then
        missing+=("ffmpeg")
    fi

    if ! command -v ffprobe &> /dev/null; then
        missing+=("ffprobe")
    fi

    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_error "Please install them before running this script."
        exit 1
    fi
}

# Get audio duration in seconds
get_audio_duration() {
    local audio_file="$1"
    ffprobe -v error -show_entries format=duration -of csv=p=0 "$audio_file"
}

# Basic timeline sanity check
check_timeline_inputs() {
    local timeline_file="$1"

    # Check file exists
    if [[ ! -f "$timeline_file" ]]; then
        log_error "Timeline file not found: $timeline_file"
        exit 1
    fi

    # Validate JSON syntax
    if ! jq empty "$timeline_file" 2>/dev/null; then
        log_error "Invalid JSON in timeline file: $timeline_file"
        exit 1
    fi

    # Check required fields
    local required_fields=("audio_file" "vtt_file" "output_file" "segments")
    for field in "${required_fields[@]}"; do
        if [[ "$(jq -r ".$field // empty" "$timeline_file")" == "" ]]; then
            log_error "Missing required field in timeline: $field"
            exit 1
        fi
    done

    # Validate audio file exists
    local audio_file
    audio_file=$(jq -r '.audio_file' "$timeline_file")
    if [[ ! -f "$audio_file" ]]; then
        log_error "Audio file not found: $audio_file"
        exit 1
    fi

    # Validate VTT file exists
    local vtt_file
    vtt_file=$(jq -r '.vtt_file' "$timeline_file")
    if [[ ! -f "$vtt_file" ]]; then
        log_error "VTT file not found: $vtt_file"
        exit 1
    fi

    # Validate all images exist
    local segment_count
    segment_count=$(jq '.segments | length' "$timeline_file")

    for ((i = 0; i < segment_count; i++)); do
        local image_path
        image_path=$(jq -r ".segments[$i].image" "$timeline_file")
        if [[ ! -f "$image_path" ]]; then
            log_error "Image file not found: $image_path (segment $i)"
            exit 1
        fi
    done

    log_info "Timeline inputs look sane"
}

# Build FFmpeg filter complex for slideshow with true crossfades.
build_filter_complex() {
    local timeline_file="$1"
    local resolution="$2"
    local fade_duration="$3"

    local width height
    width=$(echo "$resolution" | cut -d'x' -f1)
    height=$(echo "$resolution" | cut -d'x' -f2)

    local segment_count
    segment_count=$(jq '.segments | length' "$timeline_file")

    local filter_complex=""
    local current_label=""
    local current_output_duration="0"

    for ((i = 0; i < segment_count; i++)); do
        local start end duration clip_duration
        start=$(jq -r ".segments[$i].start" "$timeline_file")
        end=$(jq -r ".segments[$i].end" "$timeline_file")
        duration=$(awk "BEGIN {printf \"%.6f\", $end - $start}")

        clip_duration="$duration"
        if (( i > 0 && segment_count > 1 )); then
            clip_duration=$(awk "BEGIN {printf \"%.6f\", $duration + $fade_duration}")
        fi

        filter_complex+="[$i:v]scale=${width}:${height}:force_original_aspect_ratio=decrease,"
        filter_complex+="pad=${width}:${height}:(ow-iw)/2:(oh-ih)/2:black,"
        filter_complex+="setsar=1,"
        filter_complex+="format=yuv420p,"
        filter_complex+="trim=duration=$clip_duration,"
        filter_complex+="setpts=PTS-STARTPTS"
        filter_complex+="[v$i];"

        if (( i == 0 )); then
            current_label="v0"
            current_output_duration="$duration"
            continue
        fi

        local transition_offset next_label
        transition_offset=$(awk "BEGIN {printf \"%.6f\", $current_output_duration - $fade_duration}")
        next_label="x$i"
        filter_complex+="[$current_label][v$i]xfade=transition=fade:duration=$fade_duration:offset=$transition_offset[$next_label];"

        current_label="$next_label"
        current_output_duration="$end"
    done

    if (( segment_count == 1 )); then
        filter_complex+="[v0]null[video]"
    else
        filter_complex+="[$current_label]null[video]"
    fi

    echo "$filter_complex"
}

# Generate the video
generate_video() {
    local timeline_file="$1"

    check_timeline_inputs "$timeline_file"

    # Read configuration from timeline
    local audio_file vtt_file output_file resolution fade_duration
    audio_file=$(jq -r '.audio_file' "$timeline_file")
    vtt_file=$(jq -r '.vtt_file' "$timeline_file")
    output_file=$(jq -r '.output_file' "$timeline_file")
    resolution=$(jq -r '.resolution // "1920x1080"' "$timeline_file")
    fade_duration=$(jq -r '.fade_duration // 0.5' "$timeline_file")

    local segment_count
    segment_count=$(jq '.segments | length' "$timeline_file")

    log_info "Configuration:"
    log_info "  Audio: $audio_file"
    log_info "  Subtitles: $vtt_file"
    log_info "  Output: $output_file"
    log_info "  Resolution: $resolution"
    log_info "  Fade duration: ${fade_duration}s"
    log_info "  Segments: $segment_count"
    log_info "  Preset: $FFMPEG_PRESET"
    log_info "  CRF: $FFMPEG_CRF"

    # Get audio duration for verification
    local audio_duration
    audio_duration=$(get_audio_duration "$audio_file")
    log_info "  Audio duration: ${audio_duration}s"

    # Build input arguments for all images
    local input_args=()
    for ((i = 0; i < segment_count; i++)); do
        local image_path
        image_path=$(jq -r ".segments[$i].image" "$timeline_file")
        input_args+=(-loop 1 -i "$image_path")
    done

    # Add audio input
    input_args+=(-i "$audio_file")

    # Build filter complex
    log_step "Building filter complex..."
    local filter_complex
    filter_complex=$(build_filter_complex "$timeline_file" "$resolution" "$fade_duration")

    # Create output directory if needed
    local output_dir
    output_dir=$(dirname "$output_file")
    mkdir -p "$output_dir"

    # Build FFmpeg command with soft subtitles (embedded as separate track)
    log_step "Running FFmpeg (this may take a while)..."
    
    local ffmpeg_cmd=(
        ffmpeg
        -y  # Overwrite output
        "${input_args[@]}"
        -i "$vtt_file"  # Add subtitle file as input
        -filter_complex "$filter_complex"
        -map "[video]"
        -map "$segment_count:a"  # Audio is the last input (before subtitle)
        -map "$((segment_count + 1)):s"  # Subtitle is the final input
        -c:v libx264
        -preset "$FFMPEG_PRESET"
        -crf "$FFMPEG_CRF"
        -c:a aac
        -b:a 192k
        -ar 48000
        -c:s mov_text  # Soft subtitles for MP4 container
        -metadata:s:s:0 language=eng  # Set subtitle language
        -threads "$FFMPEG_THREADS"
        -movflags +faststart  # Optimize for web streaming
        -pix_fmt yuv420p  # Compatibility
        -shortest
        "$output_file"
    )

    # Show command for debugging
    log_info "FFmpeg command:"
    echo "  ${ffmpeg_cmd[*]}" | fold -w 100 -s | sed 's/^/    /'

    # Run FFmpeg
    if "${ffmpeg_cmd[@]}"; then
        log_info "Video generation complete!"
        
        # Show output info
        local output_size duration
        output_size=$(du -h "$output_file" | cut -f1)
        duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$output_file")
        duration=$(printf "%.2f" "$duration")

        echo ""
        log_info "Output Summary:"
        log_info "  File: $output_file"
        log_info "  Size: $output_size"
        log_info "  Duration: ${duration}s"
        log_info "  Segments: $segment_count images with ${fade_duration}s true crossfades"
        echo ""
        log_info "Video is ready for YouTube upload!"
    else
        log_error "FFmpeg failed to generate video"
        exit 1
    fi
}

# Main entry point
main() {
    # Check for help flag
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        print_usage
        exit 0
    fi

    # Validate arguments
    if [[ $# -lt 1 ]]; then
        log_error "Missing required argument: timeline.json"
        echo ""
        print_usage
        exit 1
    fi

    local timeline_file="$1"

    echo ""
    echo "======================================"
    echo "   Podcast Video Generator"
    echo "======================================"
    echo ""

    # Check dependencies
    log_step "Checking dependencies..."
    check_dependencies

    # Validate timeline
    log_step "Validating timeline..."
    bash "$SCRIPT_DIR/validate-timeline.sh" "$timeline_file"

    # Generate video
    log_step "Starting video generation..."
    generate_video "$timeline_file"
}

main "$@"
