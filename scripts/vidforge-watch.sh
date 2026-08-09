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

mkdir -p -- "$SOURCE_ROOT"

# Queue video files that already exist when the service starts.
find "$SOURCE_ROOT" -type f \
    \( \
        -iname '*.mkv'  -o \
        -iname '*.mp4'  -o \
        -iname '*.mov'  -o \
        -iname '*.m4v'  -o \
        -iname '*.avi'  -o \
        -iname '*.wmv'  -o \
        -iname '*.webm' -o \
        -iname '*.mpg'  -o \
        -iname '*.mpeg' -o \
        -iname '*.ts'   -o \
        -iname '*.m2ts' \
    \) -print0 |
while IFS= read -r -d '' video_file; do
    vidforge-queue "$video_file"
done

# close_write handles files written directly into the folder.
# moved_to handles files copied using a temporary file and renamed afterward.
inotifywait \
    --monitor \
    --recursive \
    --quiet \
    --event close_write,moved_to \
    --format '%w%f%0' \
    --no-newline \
    "$SOURCE_ROOT" |
while IFS= read -r -d '' video_file; do
    vidforge-queue "$video_file"
done
