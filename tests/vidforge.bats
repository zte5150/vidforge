#!/usr/bin/env bats

setup()
{
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_ROOT="$BATS_TEST_TMPDIR/test"
    SOURCE_ROOT="$TEST_ROOT/source"
    OUTPUT_ROOT="$TEST_ROOT/output"
    QUEUE_DIR="$TEST_ROOT/queue"
    FAILED_DIR="$TEST_ROOT/failed"
    LOG_DIR="$TEST_ROOT/log"
    CONFIG_FILE="$TEST_ROOT/vidforge.conf"
    MOCK_BIN="$TEST_ROOT/bin"

    mkdir -p "$SOURCE_ROOT" "$OUTPUT_ROOT" "$QUEUE_DIR" \
        "$FAILED_DIR" "$LOG_DIR" "$MOCK_BIN"

    cat >"$CONFIG_FILE" <<EOF
SOURCE_ROOT="$SOURCE_ROOT"
OUTPUT_ROOT="$OUTPUT_ROOT"
QUEUE_DIR="$QUEUE_DIR"
FAILED_DIR="$FAILED_DIR"
LOG_DIR="$LOG_DIR"
FFMPEG_IMAGE="lscr.io/linuxserver/ffmpeg:latest"
VIDEO_CODEC="libsvtav1"
AV1_PRESET="6"
AV1_CRF="28"
VIDEO_PIXEL_FORMAT="yuv420p10le"
VIDEO_ENCODER_PARAMS="tune=0"
AUDIO_CODEC="libopus"
AUDIO_BITRATE="160k"
SUBTITLE_CODEC="copy"
DATA_CODEC="copy"
EOF
}

@test "queueing a supported video creates one queue entry" {
    input_file="$SOURCE_ROOT/a video.MP4"
    touch "$input_file"

    run env VIDFORGE_CONFIG_FILE="$CONFIG_FILE" \
        bash "$REPO_ROOT/scripts/vidforge-queue.sh" "$input_file"

    [ "$status" -eq 0 ]
    [ "$(find "$QUEUE_DIR" -name '*.queue' -type f | wc -l)" -eq 1 ]
    [ "$(cat "$QUEUE_DIR"/*.queue)" = "$input_file" ]
}

@test "queueing the same video twice is deduplicated" {
    input_file="$SOURCE_ROOT/video.mkv"
    touch "$input_file"

    env VIDFORGE_CONFIG_FILE="$CONFIG_FILE" \
        bash "$REPO_ROOT/scripts/vidforge-queue.sh" "$input_file"
    env VIDFORGE_CONFIG_FILE="$CONFIG_FILE" \
        bash "$REPO_ROOT/scripts/vidforge-queue.sh" "$input_file"

    [ "$(find "$QUEUE_DIR" -name '*.queue' -type f | wc -l)" -eq 1 ]
}

@test "unsupported and missing files are not queued" {
    touch "$SOURCE_ROOT/notes.txt"

    env VIDFORGE_CONFIG_FILE="$CONFIG_FILE" \
        bash "$REPO_ROOT/scripts/vidforge-queue.sh" "$SOURCE_ROOT/notes.txt"
    env VIDFORGE_CONFIG_FILE="$CONFIG_FILE" \
        bash "$REPO_ROOT/scripts/vidforge-queue.sh" "$SOURCE_ROOT/missing.mp4"

    [ -z "$(find "$QUEUE_DIR" -name '*.queue' -type f -print -quit)" ]
}

@test "encoder treats a vanished input as completed work" {
    run env VIDFORGE_CONFIG_FILE="$CONFIG_FILE" \
        bash "$REPO_ROOT/scripts/vidforge-encode.sh" "$SOURCE_ROOT/missing.mp4"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Input no longer exists"* ]]
}

@test "encoder refuses a path outside the source root" {
    outside_file="$TEST_ROOT/outside.mp4"
    touch "$outside_file"

    run env VIDFORGE_CONFIG_FILE="$CONFIG_FILE" \
        bash "$REPO_ROOT/scripts/vidforge-encode.sh" "$outside_file"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Refusing path outside source directory"* ]]
}

@test "encoder ignores an unsupported extension" {
    input_file="$SOURCE_ROOT/notes.txt"
    touch "$input_file"

    run env VIDFORGE_CONFIG_FILE="$CONFIG_FILE" \
        bash "$REPO_ROOT/scripts/vidforge-encode.sh" "$input_file"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Ignoring unsupported extension"* ]]
}

@test "encoder skips an output that has its done marker" {
    input_file="$SOURCE_ROOT/movie.mp4"
    output_file="$OUTPUT_ROOT/movie.av1.mkv"
    touch "$input_file" "$output_file" "$output_file.done"

    run env VIDFORGE_CONFIG_FILE="$CONFIG_FILE" \
        bash "$REPO_ROOT/scripts/vidforge-encode.sh" "$input_file"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Already encoded: movie.mp4"* ]]
}

@test "encoder mirrors nested directories and creates a done marker" {
    input_file="$SOURCE_ROOT/movies/example.mp4"
    output_file="$OUTPUT_ROOT/movies/example.av1.mkv"
    mkdir -p "$(dirname "$input_file")"
    touch "$input_file"

    cat >"$MOCK_BIN/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat >"$MOCK_BIN/podman" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" --entrypoint ffprobe "* ]]; then
    printf 'h264\n'
    exit 0
fi

container_output="${!#}"
relative_output="${container_output#/output/}"
host_output="$TEST_OUTPUT_ROOT/$relative_output"
mkdir -p "$(dirname "$host_output")"
touch "$host_output"
EOF
    chmod +x "$MOCK_BIN/sleep" "$MOCK_BIN/podman"

    run env VIDFORGE_CONFIG_FILE="$CONFIG_FILE" \
        TEST_OUTPUT_ROOT="$OUTPUT_ROOT" \
        PATH="$MOCK_BIN:$PATH" \
        bash "$REPO_ROOT/scripts/vidforge-encode.sh" "$input_file"

    [ "$status" -eq 0 ]
    [ -f "$output_file" ]
    [ -f "$output_file.done" ]
    [ ! -e "$output_file.partial.mkv" ]
}

@test "encoder passes configured encoding options to FFmpeg" {
    input_file="$SOURCE_ROOT/example.mp4"
    touch "$input_file"

    cat >>"$CONFIG_FILE" <<'EOF'
VIDEO_CODEC="libaom-av1"
AV1_PRESET="4"
AV1_CRF="31"
VIDEO_PIXEL_FORMAT="yuv420p"
VIDEO_ENCODER_PARAMS=""
AUDIO_CODEC="copy"
AUDIO_BITRATE=""
SUBTITLE_CODEC="webvtt"
DATA_CODEC="bin_data"
EOF

    cat >"$MOCK_BIN/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat >"$MOCK_BIN/podman" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" --entrypoint ffprobe "* ]]; then
    printf 'h264\n'
    exit 0
fi

printf '%s\n' "$@" >"$TEST_ARGS_FILE"
container_output="${!#}"
relative_output="${container_output#/output/}"
touch "$TEST_OUTPUT_ROOT/$relative_output"
EOF
    chmod +x "$MOCK_BIN/sleep" "$MOCK_BIN/podman"

    run env VIDFORGE_CONFIG_FILE="$CONFIG_FILE" \
        TEST_OUTPUT_ROOT="$OUTPUT_ROOT" \
        TEST_ARGS_FILE="$TEST_ROOT/ffmpeg.args" \
        PATH="$MOCK_BIN:$PATH" \
        bash "$REPO_ROOT/scripts/vidforge-encode.sh" "$input_file"

    [ "$status" -eq 0 ]
    grep -Fxq 'libaom-av1' "$TEST_ROOT/ffmpeg.args"
    grep -Fxq '4' "$TEST_ROOT/ffmpeg.args"
    grep -Fxq '31' "$TEST_ROOT/ffmpeg.args"
    grep -Fxq 'yuv420p' "$TEST_ROOT/ffmpeg.args"
    grep -Fxq 'copy' "$TEST_ROOT/ffmpeg.args"
    grep -Fxq 'webvtt' "$TEST_ROOT/ffmpeg.args"
    grep -Fxq 'bin_data' "$TEST_ROOT/ffmpeg.args"
    ! grep -Fxq -- '-svtav1-params' "$TEST_ROOT/ffmpeg.args"
    ! grep -Fxq -- '-b:a' "$TEST_ROOT/ffmpeg.args"
}
