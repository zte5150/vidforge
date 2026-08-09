#!/usr/bin/env bash

set -Eeuo pipefail

CONFIG_FILE="${VIDFORGE_CONFIG_FILE:-/etc/vidforge.conf}"

if [[ ! -r "$CONFIG_FILE" ]]; then
    printf 'Configuration file is not readable: %s\n' "$CONFIG_FILE" >&2
    exit 1
fi

# shellcheck source=/etc/vidforge.conf
source "$CONFIG_FILE"

: "${SOURCE_ROOT:?SOURCE_ROOT is not configured}"
: "${OUTPUT_ROOT:?OUTPUT_ROOT is not configured}"
: "${LOG_DIR:?LOG_DIR is not configured}"

FFMPEG_IMAGE="${FFMPEG_IMAGE:-lscr.io/linuxserver/ffmpeg:latest}"
VIDEO_CODEC="${VIDEO_CODEC:-libsvtav1}"
AV1_PRESET="${AV1_PRESET:-6}"
AV1_CRF="${AV1_CRF:-28}"
VIDEO_PIXEL_FORMAT="${VIDEO_PIXEL_FORMAT:-yuv420p10le}"
VIDEO_ENCODER_PARAMS="${VIDEO_ENCODER_PARAMS-tune=0}"
AUDIO_CODEC="${AUDIO_CODEC:-libopus}"
AUDIO_BITRATE="${AUDIO_BITRATE-160k}"
SUBTITLE_CODEC="${SUBTITLE_CODEC:-copy}"
DATA_CODEC="${DATA_CODEC:-copy}"

input_file="${1:?Usage: vidforge-encode INPUT_FILE}"

log()
{
    printf '%s %s\n' "$(date --iso-8601=seconds)" "$*"
}

# Resolve a canonical path where possible.
if ! input_file="$(realpath --canonicalize-existing -- "$input_file")"; then
    log "Input no longer exists: $input_file"
    exit 0
fi

source_root="$(realpath --canonicalize-existing -- "$SOURCE_ROOT")"

# Prevent paths outside the source directory.
case "$input_file" in
    "$source_root"/*)
        ;;
    *)
        log "Refusing path outside source directory: $input_file"
        exit 1
        ;;
esac

# Only process known video extensions.
case "${input_file,,}" in
    *.mkv|*.mp4|*.mov|*.m4v|*.avi|*.wmv|*.webm|*.mpg|*.mpeg|*.ts|*.m2ts)
        ;;
    *)
        log "Ignoring unsupported extension: $input_file"
        exit 0
        ;;
esac

relative_path="${input_file#"$source_root"/}"
relative_dir="$(dirname -- "$relative_path")"
base_name="$(basename -- "$relative_path")"
stem="${base_name%.*}"
container_input="/input/$relative_path"

output_dir="$OUTPUT_ROOT"

if [[ "$relative_dir" != "." ]]; then
    output_dir="$OUTPUT_ROOT/$relative_dir"
fi

output_file="$output_dir/${stem}.av1.mkv"
temp_file="$output_file.partial.mkv"
done_file="$output_file.done"
log_file="$LOG_DIR/$(printf '%s' "$relative_path" | sha256sum | cut -d' ' -f1).log"

mkdir -p -- "$output_dir"
mkdir -p -- "$LOG_DIR"

if [[ -f "$output_file" && -f "$done_file" ]]; then
    log "Already encoded: $relative_path"
    exit 0
fi

# Skip files whose first video stream is already encoded with AV1. Use the
# ffprobe shipped in the encoding image so the host needs no media packages.
if ! video_codec="$(podman run --rm \
    --network=none \
    --volume "$SOURCE_ROOT:/input:ro,z" \
    --entrypoint ffprobe \
    "$FFMPEG_IMAGE" \
    -v error \
    -select_streams v:0 \
    -show_entries stream=codec_name \
    -of default=noprint_wrappers=1:nokey=1 \
    "$container_input")"
then
    log "Unable to determine video codec: $relative_path"
    exit 1
fi

if [[ "$video_codec" == "av1" ]]; then
    log "Already encoded as AV1: $relative_path"
    exit 0
fi

# Ensure a copied or downloaded file has stopped changing.
previous_size=-1
stable_checks=0

while (( stable_checks < 3 )); do
    current_size="$(stat --format='%s' -- "$input_file")"

    if [[ "$current_size" -eq "$previous_size" ]]; then
        (( stable_checks += 1 ))
    else
        stable_checks=0
        previous_size="$current_size"
    fi

    sleep 10
done

log "Encoding: $relative_path"
log "Output:   $output_file"

rm -f -- "$temp_file"

temp_relative="${temp_file#"$OUTPUT_ROOT"/}"
container_output="/output/$temp_relative"

video_options=(
    -c:v "$VIDEO_CODEC"
    -preset "$AV1_PRESET"
    -crf "$AV1_CRF"
    -pix_fmt "$VIDEO_PIXEL_FORMAT"
)

if [[ -n "$VIDEO_ENCODER_PARAMS" ]]; then
    video_options+=( -svtav1-params "$VIDEO_ENCODER_PARAMS" )
fi

audio_options=( -c:a "$AUDIO_CODEC" )

if [[ -n "$AUDIO_BITRATE" ]]; then
    audio_options+=( -b:a "$AUDIO_BITRATE" )
fi

# Run the encoding in a container to avoid polluting the host with dependencies.
if podman run --rm \
    --name "av1-encode-$(printf '%s' "$relative_path" | sha256sum | cut -c1-12)" \
    --network=none \
    --volume "$SOURCE_ROOT:/input:ro,z" \
    --volume "$OUTPUT_ROOT:/output:z" \
    --entrypoint ffmpeg \
    "$FFMPEG_IMAGE" \
    -hide_banner \
    -nostdin \
    -y \
    -i "$container_input" \
    -map 0 \
    -map_metadata 0 \
    -map_chapters 0 \
    "${video_options[@]}" \
    "${audio_options[@]}" \
    -c:s "$SUBTITLE_CODEC" \
    -c:d "$DATA_CODEC" \
    "$container_output" >>"$log_file" 2>&1
then
    mv -- "$temp_file" "$output_file"
    touch -- "$done_file"
else
    exit_code=$?
    rm -f -- "$temp_file"
    log "Encoding failed: $relative_path; see $log_file"
    exit "$exit_code"
fi
