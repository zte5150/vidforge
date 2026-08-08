#!/usr/bin/env bash

set -Eeuo pipefail

QUEUE_DIR="/var/lib/av1-encoder/queue"

input_file="${1:?Usage: queue-av1-file INPUT_FILE}"

[[ -f "$input_file" ]] || exit 0

case "${input_file,,}" in
    *.mkv|*.mp4|*.mov|*.m4v|*.avi|*.wmv|*.webm|*.mpg|*.mpeg|*.ts|*.m2ts)
        ;;
    *)
        exit 0
        ;;
esac

mkdir -p -- "$QUEUE_DIR"

queue_id="$(printf '%s' "$input_file" | sha256sum | cut -d' ' -f1)"
temp_file="$QUEUE_DIR/.${queue_id}.tmp"
queue_file="$QUEUE_DIR/${queue_id}.queue"

printf '%s\n' "$input_file" > "$temp_file"
mv -- "$temp_file" "$queue_file"