#!/usr/bin/env bash

set -Eeuo pipefail

SOURCE_ROOT="/srv/video/incoming"
OUTPUT_ROOT="/srv/video/av1"
LOG_DIR="/var/log/av1-encoder"

# SVT-AV1 settings
AV1_PRESET="6"
AV1_CRF="28"

input_file="${1:?Usage: encode-av1-file INPUT_FILE}"

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

container_input="/input/$relative_path"
temp_relative="${temp_file#"$OUTPUT_ROOT"/}"
container_output="/output/$temp_relative"

# Run the encoding in a container to avoid polluting the host with dependencies.
if podman run --rm \
    --name "av1-encode-$(printf '%s' "$relative_path" | sha256sum | cut -c1-12)" \
    --network=none \
    --volume "$SOURCE_ROOT:/input:ro,Z" \
    --volume "$OUTPUT_ROOT:/output:Z" \
    lscr.io/linuxserver/ffmpeg:latest \
    -hide_banner \
    -nostdin \
    -y \
    -i "$container_input" \
    -map 0 \
    -map_metadata 0 \
    -map_chapters 0 \
    -c:v libsvtav1 \
    -preset "$AV1_PRESET" \
    -crf "$AV1_CRF" \
    -pix_fmt yuv420p10le \
    -svtav1-params "tune=0" \
    -c:a libopus \
    -b:a 160k \
    -c:s copy \
    -c:d copy \
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