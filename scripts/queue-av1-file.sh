#!/usr/bin/env bash

set -Eeuo pipefail

CONFIG_FILE="${AV1_CONFIG_FILE:-/etc/av1-encoder.conf}"

if [[ ! -r "$CONFIG_FILE" ]]; then
    printf 'Configuration file is not readable: %s\n' "$CONFIG_FILE" >&2
    exit 1
fi

# shellcheck source=/etc/av1-encoder.conf
source "$CONFIG_FILE"

: "${QUEUE_DIR:?QUEUE_DIR is not configured}"

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
