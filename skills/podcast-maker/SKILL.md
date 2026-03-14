---
name: podcast-maker
description: Create YouTube-ready podcast videos from audio and images with AI-driven semantic image timing, fade transitions, and soft subtitles using local Whisper and FFmpeg
---

# Podcast Maker Skill

Create YouTube-ready podcast videos from audio files and images using local Whisper and FFmpeg.

## Overview

This skill generates professional podcast videos with:
- **Precise semantic alignment**: AI reads VTT cues and specifies exact transition points
- **Cue-based timing**: Image transitions align precisely with VTT cue boundaries
- **Smooth fade transitions**: True 0.5-second crossfade between images
- **Soft subtitles**: VTT captions embedded as a toggleable track (not burned in)
- **Optional transcription**: Uses local Whisper when user doesn't provide VTT

### Two Workflow Options

| Workflow | Best For | Precision |
|----------|----------|-----------|
| **Cue-Based (Recommended)** | Precise semantic alignment | Exact cue boundaries |
| **Segment-Based (Legacy)** | Quick, equal-duration segments | Approximate |

## Prerequisites

Ensure these tools are installed:
- `whisper` - OpenAI Whisper for speech-to-text
- `ffmpeg` - Video/audio processing
- `jq` - JSON parsing (for timeline processing)

---

## Cue-Based Workflow (Recommended)

This workflow provides **precise semantic alignment** by letting AI specify exact VTT cue ranges for each image.

### Phase 1: Gather Inputs

Collect the following from the user:

| Input | Required | Description |
|-------|----------|-------------|
| Audio file | Yes | Any format supported by ffmpeg (mp3, wav, m4a, flac, ogg, etc.) |
| Image files | Yes | One or more images (jpg, png, webp). Will be shown as slideshow |
| VTT file | No | If not provided, generate using Whisper |
| Output path | No | Default: `output.mp4` in current directory |

### Phase 2: Generate Transcription (if needed)

If the user does not provide a VTT file:

```bash
./scripts/transcribe.sh <audio_file> [output_directory]
```

### Phase 3: Analyze Images

**CRITICAL**: You MUST analyze each image to understand what it depicts.

```bash
./scripts/collect-image-info.sh <image1> <image2> <image3> ...
```

**Use the available image-viewing tool to inspect each image**, then document:

| Image | Description | Matches Content About |
|-------|-------------|----------------------|
| intro.png | Podcast logo | Introduction, welcome |
| guest.jpg | Headshot of Sarah Chen | When Sarah speaks |
| topic.png | ML pipeline diagram | Technical discussion |
| outro.png | Subscribe CTA | Closing, goodbye |

### Phase 4: Parse VTT and Read All Cues

**This is the key step for precise alignment.**

```bash
./scripts/parse-vtt.sh podcast.vtt > cues.json
```

**Output structure:**
```json
{
  "total_duration": 2880.5,
  "cue_count": 58,
  "cues": [
    {"index": 1, "start_seconds": 0.0, "end_seconds": 3.5, "text": "Welcome to AI Weekly..."},
    {"index": 2, "start_seconds": 3.5, "end_seconds": 7.2, "text": "I'm your host..."},
    ...
    {"index": 15, "start_seconds": 45.0, "end_seconds": 48.5, "text": "Today we have Sarah Chen..."},
    ...
  ]
}
```

**AI must read the full cues.json** to understand:
1. What content is discussed in each cue
2. Where semantic transitions occur (topic changes, speaker changes)
3. Which cue ranges correspond to each image

### Phase 5: Create Cue-Based Mapping

Based on your analysis, create a mapping that specifies **exactly which VTT cues** correspond to each image:

```bash
cat > cue_mapping.json << 'EOF'
{
  "mappings": [
    {
      "image": "/path/to/intro.png",
      "start_cue": 1,
      "end_cue": 14,
      "description": "Introduction and welcome"
    },
    {
      "image": "/path/to/guest.jpg",
      "start_cue": 15,
      "end_cue": 42,
      "description": "Sarah Chen interview"
    },
    {
      "image": "/path/to/topic.png",
      "start_cue": 43,
      "end_cue": 55,
      "description": "ML technical discussion"
    },
    {
      "image": "/path/to/outro.png",
      "start_cue": 56,
      "end_cue": -1,
      "description": "Closing and CTA"
    }
  ]
}
EOF
```

**Key points:**
- `start_cue`: 1-based index of first cue for this image
- `end_cue`: 1-based index of the last cue, or `-1` for "through the final cue"
- Cue ranges must be contiguous and cover all cues
- The script validates coverage and derives transition timestamps from cue boundaries

### Phase 6: Generate Precise Timeline

```bash
./scripts/cue-based-timeline.sh \
  podcast.vtt \
  cue_mapping.json \
  podcast.mp3 \
  output.mp4 > timeline.json
```

The script reads exact timestamps from VTT cues:
- Image 1 starts at 0s (cue 1 start)
- Image 2 starts at cue 15's start_seconds (e.g., 45.0s)
- Image 3 starts at cue 43's start_seconds (e.g., 180.5s)
- etc.

### Phase 7: Validate Timeline

```bash
./scripts/validate-timeline.sh timeline.json --fix
```

### Phase 8: Generate Video

```bash
./scripts/podcast-maker.sh timeline.json
```

### Phase 9: Report Results

Report to user:
- Output file path and size
- Video duration
- Image transition points with timestamps and cue ranges

---

## Cue-Based Example Session

### User Request
"Create a podcast video from interview.mp3 using: intro.png, guest.jpg, topic.png, outro.png"

### AI Workflow

#### 1. Analyze images
```bash
./scripts/collect-image-info.sh intro.png guest.jpg topic.png outro.png
```
Read each image and understand its content.

#### 2. Generate transcription (if needed)
```bash
./scripts/transcribe.sh interview.mp3
```

#### 3. Parse VTT and analyze cues
```bash
./scripts/parse-vtt.sh interview.vtt > cues.json
```

**AI reads cues.json and identifies semantic boundaries:**

| Cue Range | Content | Best Image |
|-----------|---------|------------|
| 1-14 | "Welcome to AI Weekly, I'm your host..." | intro.png |
| 15-42 | "Sarah, tell us about your work..." | guest.jpg |
| 43-55 | "Let's dive into the ML pipeline..." | topic.png |
| 56-58 | "Thanks for joining, subscribe..." | outro.png |

#### 4. Create cue mapping
```bash
cat > cue_mapping.json << 'EOF'
{
  "mappings": [
    {"image": "/path/to/intro.png", "start_cue": 1, "end_cue": 14, "description": "Introduction"},
    {"image": "/path/to/guest.jpg", "start_cue": 15, "end_cue": 42, "description": "Sarah Chen interview"},
    {"image": "/path/to/topic.png", "start_cue": 43, "end_cue": 55, "description": "ML discussion"},
    {"image": "/path/to/outro.png", "start_cue": 56, "end_cue": -1, "description": "Closing"}
  ]
}
EOF
```

#### 5. Generate precise timeline
```bash
./scripts/cue-based-timeline.sh interview.vtt cue_mapping.json interview.mp3 interview_video.mp4 > timeline.json
```

#### 6. Validate and generate
```bash
./scripts/validate-timeline.sh timeline.json --fix
./scripts/podcast-maker.sh timeline.json
```

#### 7. Report
"Created interview_video.mp4 (1.2 GB, 48:00) with precise semantic alignment:
- 0:00-0:45 (cues 1-14): intro.png - Introduction
- 0:45-25:00 (cues 15-42): guest.jpg - Sarah Chen interview
- 25:00-45:00 (cues 43-55): topic.png - ML technical discussion
- 45:00-48:00 (cues 56-58): outro.png - Closing"

---

## Segment-Based Workflow (Legacy)

This workflow divides audio into equal-duration segments. Use when you need quick results and precise timing is less critical.

### Phase 1: Gather Inputs

Collect the following from the user:

| Input | Required | Description |
|-------|----------|-------------|
| Audio file | Yes | Any format supported by ffmpeg (mp3, wav, m4a, flac, ogg, etc.) |
| Image files | Yes | One or more images (jpg, png, webp). Will be shown as slideshow |
| VTT file | No | If not provided, generate using Whisper |
| Output path | No | Default: `output.mp4` in current directory |

### Phase 2: Generate Transcription (if needed)

If the user does not provide a VTT file:

```bash
./scripts/transcribe.sh <audio_file> [output_directory]
```

### Phase 3: Analyze Images

**CRITICAL**: You MUST analyze each image to understand what it depicts before matching with audio content.

#### Step 3.1: Collect Image Metadata

```bash
./scripts/collect-image-info.sh <image1> <image2> <image3> ...
```

**Output:**
```json
{
  "image_count": 3,
  "images": [
    {
      "index": 1,
      "path": "/path/to/intro.jpg",
      "filename": "intro.jpg",
      "dimensions": "1920x1080",
      "description": "AI_MUST_ANALYZE: Read this image and describe what it shows",
      "suggested_content": "AI_MUST_ANALYZE: What audio content should play during this image?"
    }
  ]
}
```

#### Step 3.2: Analyze Each Image

**You MUST use the available image-viewing tool to inspect each image file**, then fill in:

1. **description**: What does the image show? (person, title slide, topic illustration, etc.)
2. **suggested_content**: What audio content should play during this image?
3. **keywords**: Key terms that might appear in matching audio segments

**Example Analysis:**

| Image | Description | Suggested Content | Keywords |
|-------|-------------|-------------------|----------|
| intro.jpg | Title slide with "Tech Talk Podcast" logo | Opening, introduction, welcome | intro, welcome, podcast |
| guest.jpg | Photo of Dr. Smith in office | When Dr. Smith speaks or is discussed | Dr. Smith, guest, expert |
| ai_diagram.jpg | Flowchart of AI architecture | Discussion about AI systems | AI, architecture, neural network |
| outro.jpg | "Thanks for watching" slide | Closing, goodbye, call to action | thanks, subscribe, outro |

### Phase 4: Analyze Audio Content

#### Step 4.1: Get Audio Duration

```bash
./scripts/get-audio-duration.sh <audio_file>
```

**Save the `duration_seconds` value** - needed for timeline.

#### Step 4.2: Analyze VTT Segments

Divide the audio into segments matching the number of images:

```bash
./scripts/analyze-segments.sh <vtt_file> <num_images>
```

**Output:**
```json
{
  "num_segments": 3,
  "segments": [
    {
      "segment_index": 1,
      "start_seconds": 0,
      "end_seconds": 120.5,
      "text_preview": "Welcome to Tech Talk Podcast. Today we're joined by...",
      "suggested_image": "AI_MUST_ASSIGN: Which image matches this content?"
    },
    {
      "segment_index": 2,
      "start_seconds": 120.5,
      "end_seconds": 850.2,
      "text_preview": "Dr. Smith, tell us about your research in AI...",
      "suggested_image": "AI_MUST_ASSIGN: Which image matches this content?"
    }
  ]
}
```

### Phase 5: Match Images to Segments

**This is the critical alignment step.** Compare:
- Image descriptions (from Phase 3)
- Segment text previews (from Phase 4)

Create a mapping based on **semantic relevance**:

| Segment | Text Preview | Best Matching Image | Reason |
|---------|--------------|---------------------|--------|
| 1 | "Welcome to Tech Talk..." | intro.jpg | Title slide matches intro |
| 2 | "Dr. Smith, tell us..." | guest.jpg | Guest photo for interview |
| 3 | "The AI architecture..." | ai_diagram.jpg | Diagram matches technical discussion |
| 4 | "Thanks for watching..." | outro.jpg | Closing slide for outro |

#### Create Image Mapping JSON

Save as `image_mapping.json`:
```json
[
  "/path/to/intro.jpg",
  "/path/to/guest.jpg",
  "/path/to/ai_diagram.jpg",
  "/path/to/outro.jpg"
]
```

Or with explicit segment indices:
```json
{
  "1": "/path/to/intro.jpg",
  "2": "/path/to/guest.jpg",
  "3": "/path/to/ai_diagram.jpg",
  "4": "/path/to/outro.jpg"
}
```

### Phase 6: Generate Timeline

Combine segments with image mapping:

```bash
./scripts/analyze-segments.sh <vtt_file> <num_images> > segments.json
./scripts/generate-timeline.sh segments.json image_mapping.json <audio_file> <output.mp4> > timeline.json
```

Or in one pipeline:
```bash
./scripts/analyze-segments.sh podcast.vtt 4 | \
  ./scripts/generate-timeline.sh - image_mapping.json podcast.mp3 output.mp4 > timeline.json
```

### Phase 7: Validate Timeline

**ALWAYS validate before generating video:**

```bash
./scripts/validate-timeline.sh timeline.json
```

Use `--fix` to auto-correct last segment end time:
```bash
./scripts/validate-timeline.sh timeline.json --fix
```

### Phase 8: Generate Video

```bash
./scripts/podcast-maker.sh timeline.json
```

### Phase 9: Report Results

Report to user:
- Output file path and size
- Video duration
- Number of image segments used
- Which image was used for each content section

---

## Quick Reference: Tool Commands

| Tool | Purpose | Command |
|------|---------|---------|
| Transcribe | Generate VTT from audio | `./scripts/transcribe.sh <audio>` |
| Image Info | Collect image metadata | `./scripts/collect-image-info.sh <images...>` |
| Audio Duration | Get exact audio length | `./scripts/get-audio-duration.sh <audio>` |
| Parse VTT | Get structured cue data | `./scripts/parse-vtt.sh <vtt>` |
| **Cue Timeline** | **Precise cue-based timeline** | `./scripts/cue-based-timeline.sh <vtt> <cue_mapping> <audio> <output>` |
| Analyze Segments | Divide VTT into N parts (legacy) | `./scripts/analyze-segments.sh <vtt> <N>` |
| Generate Timeline | Create timeline (legacy) | `./scripts/generate-timeline.sh <segments> <mapping> <audio> <output>` |
| Validate | Check timeline alignment | `./scripts/validate-timeline.sh <timeline> [--fix]` |
| Make Video | Generate final video | `./scripts/podcast-maker.sh <timeline>` |

---

## Segment-Based Example Session (Legacy)

### User Request
"Create a podcast video from interview.mp3 using: intro.png, guest.jpg, topic.png, outro.png"

### AI Workflow

#### 1. Collect image info and analyze each image

```bash
./scripts/collect-image-info.sh intro.png guest.jpg topic.png outro.png
```

**Read each image and analyze:**

| File | Description | Matches Content About |
|------|-------------|----------------------|
| intro.png | Podcast logo with "AI Weekly" title | Introduction, welcome |
| guest.jpg | Headshot of interviewee Sarah Chen | When Sarah speaks |
| topic.png | Diagram showing machine learning pipeline | Technical ML discussion |
| outro.png | "Subscribe" call-to-action slide | Closing, goodbye |

#### 2. Generate transcription (if needed)

```bash
./scripts/transcribe.sh interview.mp3
```

#### 3. Get audio duration

```bash
./scripts/get-audio-duration.sh interview.mp3
# Output: {"duration_seconds": 2880.5, ...}
```

#### 4. Analyze segments (4 images = 4 segments)

```bash
./scripts/analyze-segments.sh interview.vtt 4 > segments.json
```

Review segment content:
- Segment 1 (0-180s): "Welcome to AI Weekly, I'm your host..."
- Segment 2 (180-1500s): "Sarah, tell us about your work at..."
- Segment 3 (1500-2700s): "Let's dive into the technical details of ML..."
- Segment 4 (2700-2880s): "Thanks for joining us, don't forget to subscribe..."

#### 5. Create image mapping based on semantic match

```bash
cat > image_mapping.json << 'EOF'
[
  "/path/to/intro.png",
  "/path/to/guest.jpg",
  "/path/to/topic.png",
  "/path/to/outro.png"
]
EOF
```

#### 6. Generate timeline

```bash
./scripts/generate-timeline.sh segments.json image_mapping.json interview.mp3 interview_video.mp4 > timeline.json
```

#### 7. Validate

```bash
./scripts/validate-timeline.sh timeline.json --fix
```

#### 8. Generate video

```bash
./scripts/podcast-maker.sh timeline.json
```

#### 9. Report

"Created interview_video.mp4 (1.2 GB, 48:00) with 4 segments:
- 0:00-3:00: intro.png (Introduction)
- 3:00-25:00: guest.jpg (Sarah Chen interview)
- 25:00-45:00: topic.png (ML technical discussion)
- 45:00-48:00: outro.png (Closing)"

---

## Troubleshooting

### Image-Audio Misalignment

**Symptoms:**
- Wrong image showing during speech
- Images don't match what's being discussed

**Causes & Solutions:**

| Cause | Solution |
|-------|----------|
| Didn't analyze images | Inspect each image with the image-viewing tool before matching |
| Wrong image order | Re-check semantic match between image descriptions and segment text |
| Segment boundaries wrong | Use cue-based workflow for precise control |
| Timestamps miscalculated | Use `cue-based-timeline.sh` to read exact VTT timestamps |

### Common Issues

| Issue | Solution |
|-------|----------|
| "whisper: command not found" | Install: `pip install openai-whisper` |
| "ffmpeg: command not found" | Install ffmpeg via package manager |
| "jq: command not found" | Install: `apt install jq` or `brew install jq` |
| Video too large | Increase CRF: `FFMPEG_CRF=28` |
| Last segment too short/long | Use `--fix` flag with validate-timeline.sh |

---

## File Locations

```
/home/caesar/.agents/skills/podcast-maker/
├── SKILL.md                        # This file
└── scripts/
    ├── transcribe.sh               # Whisper transcription
    ├── collect-image-info.sh       # Collect image metadata for AI analysis
    ├── get-audio-duration.sh       # Get audio duration (JSON)
    ├── parse-vtt.sh                # Parse VTT to structured JSON
    ├── cue-based-timeline.sh       # Generate timeline from cue mappings (RECOMMENDED)
    ├── analyze-segments.sh         # Divide VTT into N segments (legacy)
    ├── generate-timeline.sh        # Generate timeline from segments (legacy)
    ├── validate-timeline.sh        # Validate timeline alignment
    └── podcast-maker.sh            # FFmpeg video generation
```

---

## Key Principles for Alignment

1. **Use cue-based workflow** - For precise semantic alignment, always prefer cue-based-timeline.sh
2. **Always analyze images first** - Understand what each image shows before matching
3. **Read all VTT cues** - Parse the full VTT to identify semantic transition points
4. **Specify exact cue ranges** - Tell the script exactly which cues correspond to each image
5. **Validate before generating** - Always run validate-timeline.sh
6. **Match by semantics** - Pair images with audio based on content meaning, not time
