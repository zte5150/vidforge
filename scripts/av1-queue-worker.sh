#!/usr/bin/env bash

set -Eeuo pipefail

QUEUE_DIR="/var/lib/av1-encoder/queue"
FAILED_DIR="/var/lib/av1-encoder/failed"

mkdir -p -- "$QUEUE_DIR" "$FAILED_DIR"

while true; do
    queue_file="$(find "$QUEUE_DIR" \
        -maxdepth 1 \
        -type f \
        -name '*.queue' \
        -print \
        -quit)"

    if [[ -z "$queue_file" ]]; then
        sleep 5
        continue
    fi

    input_file="$(cat -- "$queue_file")"

    if /usr/local/bin/encode-av1-file "$input_file"; then
        rm -f -- "$queue_file"
    else
        failed_name="$(basename -- "$queue_file")"
        mv -- "$queue_file" "$FAILED_DIR/$failed_name"
    fi
done