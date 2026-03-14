#!/bin/bash
#
# transcribe.sh - Generate VTT subtitles from audio using Whisper
#
# Usage: ./transcribe.sh <audio_file> [output_dir]
#
# Environment variables:
#   WHISPER_MODEL    - Model to use (default: small)
#   WHISPER_LANGUAGE - Language code (default: auto-detect)
#   WHISPER_DEVICE   - Device to use: cpu, cuda (default: auto)
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default configuration
WHISPER_MODEL="${WHISPER_MODEL:-small}"
WHISPER_LANGUAGE="${WHISPER_LANGUAGE:-}"
WHISPER_DEVICE="${WHISPER_DEVICE:-}"

print_usage() {
    echo "Usage: $0 <audio_file> [output_dir]"
    echo ""
    echo "Generate VTT subtitles from audio using OpenAI Whisper"
    echo ""
    echo "Arguments:"
    echo "  audio_file   Path to the audio file (any format supported by ffmpeg)"
    echo "  output_dir   Output directory for VTT file (default: current directory)"
    echo ""
    echo "Environment variables:"
    echo "  WHISPER_MODEL    Model size: tiny, base, small, medium, large (default: small)"
    echo "  WHISPER_LANGUAGE Language code, e.g., en, zh, ja (default: auto-detect)"
    echo "  WHISPER_DEVICE   Device: cpu, cuda (default: auto)"
    echo ""
    echo "Examples:"
    echo "  $0 podcast.mp3"
    echo "  $0 interview.wav ./subtitles/"
    echo "  WHISPER_MODEL=medium $0 audio.m4a"
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

# Check dependencies
check_dependencies() {
    if ! command -v whisper &> /dev/null; then
        log_error "whisper is not installed. Install with: pip install openai-whisper"
        exit 1
    fi

    if ! command -v ffmpeg &> /dev/null; then
        log_error "ffmpeg is not installed. Please install ffmpeg."
        exit 1
    fi
}

# Validate input file
validate_input() {
    local audio_file="$1"

    if [[ ! -f "$audio_file" ]]; then
        log_error "Audio file not found: $audio_file"
        exit 1
    fi

    # Check if file is readable
    if [[ ! -r "$audio_file" ]]; then
        log_error "Cannot read audio file: $audio_file"
        exit 1
    fi

    # Verify it's a valid audio file using ffprobe
    if ! ffprobe -v error -select_streams a:0 -show_entries stream=codec_type -of csv=p=0 "$audio_file" 2>/dev/null | grep -q "audio"; then
        log_error "File does not appear to be a valid audio file: $audio_file"
        exit 1
    fi
}

# Main transcription function
transcribe() {
    local audio_file="$1"
    local output_dir="$2"

    # Get absolute paths
    audio_file="$(realpath "$audio_file")"
    output_dir="$(realpath "$output_dir")"

    # Extract basename without extension
    local basename
    basename="$(basename "$audio_file")"
    basename="${basename%.*}"

    log_info "Starting transcription..."
    log_info "  Audio file: $audio_file"
    log_info "  Output dir: $output_dir"
    log_info "  Model: $WHISPER_MODEL"

    # Build whisper command
    local whisper_cmd=(whisper "$audio_file"
        --model "$WHISPER_MODEL"
        --output_format vtt
        --output_dir "$output_dir"
    )

    # Add optional language parameter
    if [[ -n "$WHISPER_LANGUAGE" ]]; then
        whisper_cmd+=(--language "$WHISPER_LANGUAGE")
        log_info "  Language: $WHISPER_LANGUAGE"
    else
        log_info "  Language: auto-detect"
    fi

    # Add optional device parameter
    if [[ -n "$WHISPER_DEVICE" ]]; then
        whisper_cmd+=(--device "$WHISPER_DEVICE")
        log_info "  Device: $WHISPER_DEVICE"
    fi

    # Run whisper
    log_info "Running Whisper transcription (this may take a while)..."
    
    if "${whisper_cmd[@]}"; then
        local vtt_file="$output_dir/$basename.vtt"
        
        if [[ -f "$vtt_file" ]]; then
            log_info "Transcription complete!"
            log_info "Output: $vtt_file"
            
            # Show file info
            local line_count
            line_count=$(wc -l < "$vtt_file")
            log_info "VTT file contains $line_count lines"
            
            echo "$vtt_file"
        else
            log_error "VTT file was not created. Check whisper output for errors."
            exit 1
        fi
    else
        log_error "Whisper transcription failed"
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
        log_error "Missing required argument: audio_file"
        echo ""
        print_usage
        exit 1
    fi

    local audio_file="$1"
    local output_dir="${2:-.}"

    # Create output directory if it doesn't exist
    mkdir -p "$output_dir"

    # Check dependencies
    check_dependencies

    # Validate input
    validate_input "$audio_file"

    # Run transcription
    transcribe "$audio_file" "$output_dir"
}

main "$@"
