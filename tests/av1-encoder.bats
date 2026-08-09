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
    CONFIG_FILE="$TEST_ROOT/av1-encoder.conf"
    MOCK_BIN="$TEST_ROOT/bin"

    mkdir -p "$SOURCE_ROOT" "$OUTPUT_ROOT" "$QUEUE_DIR" \
        "$FAILED_DIR" "$LOG_DIR" "$MOCK_BIN"

    cat >"$CONFIG_FILE" <<EOF
SOURCE_ROOT="$SOURCE_ROOT"
OUTPUT_ROOT="$OUTPUT_ROOT"
QUEUE_DIR="$QUEUE_DIR"
FAILED_DIR="$FAILED_DIR"
LOG_DIR="$LOG_DIR"
AV1_PRESET="6"
AV1_CRF="28"
EOF
}

@test "queueing a supported video creates one queue entry" {
    input_file="$SOURCE_ROOT/a video.MP4"
    touch "$input_file"

    run env AV1_CONFIG_FILE="$CONFIG_FILE" \
        "$REPO_ROOT/scripts/queue-av1-file.sh" "$input_file"

    [ "$status" -eq 0 ]
    [ "$(find "$QUEUE_DIR" -name '*.queue' -type f | wc -l)" -eq 1 ]
    [ "$(cat "$QUEUE_DIR"/*.queue)" = "$input_file" ]
}

@test "queueing the same video twice is deduplicated" {
    input_file="$SOURCE_ROOT/video.mkv"
    touch "$input_file"

    env AV1_CONFIG_FILE="$CONFIG_FILE" \
        "$REPO_ROOT/scripts/queue-av1-file.sh" "$input_file"
    env AV1_CONFIG_FILE="$CONFIG_FILE" \
        "$REPO_ROOT/scripts/queue-av1-file.sh" "$input_file"

    [ "$(find "$QUEUE_DIR" -name '*.queue' -type f | wc -l)" -eq 1 ]
}

@test "unsupported and missing files are not queued" {
    touch "$SOURCE_ROOT/notes.txt"

    env AV1_CONFIG_FILE="$CONFIG_FILE" \
        "$REPO_ROOT/scripts/queue-av1-file.sh" "$SOURCE_ROOT/notes.txt"
    env AV1_CONFIG_FILE="$CONFIG_FILE" \
        "$REPO_ROOT/scripts/queue-av1-file.sh" "$SOURCE_ROOT/missing.mp4"

    [ -z "$(find "$QUEUE_DIR" -name '*.queue' -type f -print -quit)" ]
}

@test "encoder treats a vanished input as completed work" {
    run env AV1_CONFIG_FILE="$CONFIG_FILE" \
        "$REPO_ROOT/scripts/encode-av1-file.sh" "$SOURCE_ROOT/missing.mp4"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Input no longer exists"* ]]
}

@test "encoder refuses a path outside the source root" {
    outside_file="$TEST_ROOT/outside.mp4"
    touch "$outside_file"

    run env AV1_CONFIG_FILE="$CONFIG_FILE" \
        "$REPO_ROOT/scripts/encode-av1-file.sh" "$outside_file"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Refusing path outside source directory"* ]]
}

@test "encoder ignores an unsupported extension" {
    input_file="$SOURCE_ROOT/notes.txt"
    touch "$input_file"

    run env AV1_CONFIG_FILE="$CONFIG_FILE" \
        "$REPO_ROOT/scripts/encode-av1-file.sh" "$input_file"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Ignoring unsupported extension"* ]]
}

@test "encoder skips an output that has its done marker" {
    input_file="$SOURCE_ROOT/movie.mp4"
    output_file="$OUTPUT_ROOT/movie.av1.mkv"
    touch "$input_file" "$output_file" "$output_file.done"

    run env AV1_CONFIG_FILE="$CONFIG_FILE" \
        "$REPO_ROOT/scripts/encode-av1-file.sh" "$input_file"

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

    run env AV1_CONFIG_FILE="$CONFIG_FILE" \
        TEST_OUTPUT_ROOT="$OUTPUT_ROOT" \
        PATH="$MOCK_BIN:$PATH" \
        "$REPO_ROOT/scripts/encode-av1-file.sh" "$input_file"

    [ "$status" -eq 0 ]
    [ -f "$output_file" ]
    [ -f "$output_file.done" ]
    [ ! -e "$output_file.partial.mkv" ]
}
