#!/bin/bash
#
# collect-image-info.sh - Collect image metadata for AI analysis
#
# Usage: ./collect-image-info.sh <image1> [image2] [image3] ...
#
# Output:
#   JSON with image metadata that AI should analyze and describe.
#   The AI must read each image and fill in the semantic description.
#
# This enables AI to understand what each image represents and match
# it with the corresponding audio content.
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_usage() {
    echo "Usage: $0 <image1> [image2] [image3] ..."
    echo ""
    echo "Collect image metadata for semantic analysis"
    echo ""
    echo "Arguments:"
    echo "  image1, image2, ...   Path(s) to image files"
    echo ""
    echo "Output:"
    echo "  JSON array with image metadata:"
    echo "  - path: absolute path to image"
    echo "  - filename: basename of image"
    echo "  - index: order in sequence (1-based)"
    echo "  - dimensions: width x height"
    echo "  - file_size: size in bytes"
    echo "  - description: PLACEHOLDER - AI must fill this in"
    echo "  - suggested_content: PLACEHOLDER - AI must fill this in"
    echo ""
    echo "The AI should:"
    echo "  1. Inspect each image with the available image-viewing tool"
    echo "  2. Analyze what the image shows"
    echo "  3. Fill in 'description' with what the image depicts"
    echo "  4. Fill in 'suggested_content' with what audio content matches"
}

# Get image dimensions using ffprobe or file command
get_image_dimensions() {
    local image_path="$1"
    
    # Try ffprobe first
    if command -v ffprobe &> /dev/null; then
        local dims
        dims=$(ffprobe -v error -select_streams v:0 \
            -show_entries stream=width,height \
            -of csv=p=0:s=x "$image_path" 2>/dev/null || echo "")
        if [[ -n "$dims" ]]; then
            echo "$dims"
            return
        fi
    fi
    
    # Try identify (ImageMagick)
    if command -v identify &> /dev/null; then
        local dims
        dims=$(identify -format "%wx%h" "$image_path" 2>/dev/null || echo "")
        if [[ -n "$dims" ]]; then
            echo "$dims"
            return
        fi
    fi
    
    # Fallback: try to extract from file command
    if command -v file &> /dev/null; then
        local file_output
        file_output=$(file "$image_path" 2>/dev/null || echo "")
        # Extract dimensions like "1920 x 1080" or "1920x1080"
        local dims
        dims=$(echo "$file_output" | grep -oP '\d+\s*x\s*\d+' | head -1 | tr -d ' ')
        if [[ -n "$dims" ]]; then
            echo "$dims"
            return
        fi
    fi
    
    echo "unknown"
}

# Main function
collect_info() {
    local images=("$@")
    local result="[]"
    local index=1
    
    for image in "${images[@]}"; do
        if [[ ! -f "$image" ]]; then
            log_error "Image not found: $image"
            continue
        fi
        
        # Get absolute path
        local abs_path
        abs_path=$(realpath "$image")
        
        # Get filename
        local filename
        filename=$(basename "$image")
        
        # Get file size
        local file_size
        file_size=$(stat -c%s "$abs_path" 2>/dev/null || stat -f%z "$abs_path" 2>/dev/null || echo "0")
        
        # Get dimensions
        local dimensions
        dimensions=$(get_image_dimensions "$abs_path")
        
        # Add to result
        result=$(echo "$result" | jq \
            --arg path "$abs_path" \
            --arg filename "$filename" \
            --argjson index "$index" \
            --arg dimensions "$dimensions" \
            --argjson file_size "$file_size" \
            '. + [{
                "index": $index,
                "path": $path,
                "filename": $filename,
                "dimensions": $dimensions,
                "file_size": $file_size,
                "description": "AI_MUST_ANALYZE: Read this image and describe what it shows",
                "suggested_content": "AI_MUST_ANALYZE: What audio content should play during this image?",
                "keywords": []
            }]')
        
        ((index++))
    done
    
    # Create final output with instructions
    jq -n \
        --argjson images "$result" \
        --argjson count "$((index - 1))" \
        '{
            "image_count": $count,
            "instructions": "AI must analyze each image and fill in: description, suggested_content, and keywords",
            "images": $images
        }'
}

# Main entry point
main() {
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        print_usage
        exit 0
    fi
    
    if [[ $# -lt 1 ]]; then
        log_error "Missing required argument: at least one image file"
        echo ""
        print_usage
        exit 1
    fi
    
    # Check jq is available
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Install with: apt install jq or brew install jq"
        exit 1
    fi
    
    collect_info "$@"
}

main "$@"
