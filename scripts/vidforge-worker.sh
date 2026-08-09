#!/usr/bin/env bash

set -Eeuo pipefail

CONFIG_FILE="${VIDFORGE_CONFIG_FILE:-/etc/vidforge.conf}"

if [[ ! -r "$CONFIG_FILE" ]]; then
    printf 'Configuration file is not readable: %s\n' "$CONFIG_FILE" >&2
    exit 1
fi

# shellcheck source=/etc/vidforge.conf
source "$CONFIG_FILE"

: "${QUEUE_DIR:?QUEUE_DIR is not configured}"
: "${FAILED_DIR:?FAILED_DIR is not configured}"

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

    if vidforge-encode "$input_file"; then
        rm -f -- "$queue_file"
    else
        failed_name="$(basename -- "$queue_file")"
        mv -- "$queue_file" "$FAILED_DIR/$failed_name"
    fi
done
