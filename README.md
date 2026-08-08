# AV1 Video Encoding Service

A small Linux service that watches a directory tree for video files and
encodes them to AV1 in a Podman container. Files are placed in a persistent
queue and encoded one at a time, so a restart does not lose pending work.

The output directory mirrors the source directory structure. For example:

```text
/srv/video/incoming/movies/example.mp4
    -> /srv/video/av1/movies/example.av1.mkv
```

## How it works

1. `av1-watcher.service` scans existing files and watches for new or moved
   files with `inotifywait`.
2. `queue-av1-file` creates one queue entry per source path.
3. `av1-worker.service` processes queue entries sequentially.
4. `encode-av1-file` waits until the source file has stopped growing, then
   runs FFmpeg from `lscr.io/linuxserver/ffmpeg:latest` with Podman.
5. A successful encode creates both an `.av1.mkv` file and a `.done` marker.
   Failed queue entries are moved to the configured failed directory.

Video is encoded with SVT-AV1 as 10-bit 4:2:0, audio is converted to Opus at
160 kb/s, and subtitle and data streams are copied. Metadata and chapters are
preserved.

## Requirements

- Linux with systemd
- Bash 4 or newer
- Podman
- `inotifywait` from `inotify-tools`
- Standard GNU utilities including `find`, `realpath`, `sha256sum`, and `stat`
- Read access to the source tree and write access to the output, queue,
  failed, and log directories

The container image must be downloaded before the worker can run without
network access. The encoding container itself is started with networking
disabled.

## Installation

### RPM package (Fedora/RHEL family)

Install the RPM build tools and build from a committed revision:

```bash
sudo dnf install git make rpm-build systemd-rpm-macros
make rpm
sudo dnf install ./build/rpmbuild/RPMS/noarch/av1-encoder-*.noarch.rpm
```

The build uses `git archive`, so commit the files you want included first.
After installation, edit `/etc/av1-encoder.conf`, create and grant access to
the configured media directories, pull the container image, and enable the
services:

```bash
sudoedit /etc/av1-encoder.conf
sudo mkdir -p /srv/video/incoming /srv/video/av1
sudo chown -R av1-encoder:av1-encoder /srv/video/incoming /srv/video/av1
sudo -u av1-encoder -H podman pull lscr.io/linuxserver/ffmpeg:latest
sudo systemctl enable --now av1-watcher.service av1-worker.service
```

The RPM preserves a locally edited configuration during upgrades. Before
publishing the package, replace the placeholder maintainer identity in
`packaging/av1-encoder.spec`.

### Manual installation

Run these commands from the repository root. The units use a dedicated system
account named `av1-encoder`.

1. Create the service account. Its home directory is also used by rootless
   Podman for persistent container storage:

   ```bash
   sudo useradd --system --user-group \
     --home-dir /var/lib/av1-encoder --create-home \
     --shell /usr/sbin/nologin av1-encoder
   ```

   If you use different media mount points, update each `RequiresMountsFor`
   line in `service/` before installing the units.

2. Install the scripts, configuration, and systemd units:

   ```bash
   sudo install -m 0755 scripts/av1-queue-worker.sh /usr/bin/av1-queue-worker
   sudo install -m 0755 scripts/encode-av1-file.sh /usr/bin/encode-av1-file
   sudo install -m 0755 scripts/queue-av1-file.sh /usr/bin/queue-av1-file
   sudo install -m 0755 scripts/watch-av1-folder.sh /usr/bin/watch-av1-folder
   sudo install -m 0644 config/av1-encoder.conf.example /etc/av1-encoder.conf
   sudo install -m 0644 service/av1-watcher.service /etc/systemd/system/av1-watcher.service
   sudo install -m 0644 service/av1-worker.service /etc/systemd/system/av1-worker.service
   ```

3. Edit `/etc/av1-encoder.conf` to match your directories and desired encoder
   settings:

   ```bash
   sudoedit /etc/av1-encoder.conf
   ```

4. Create the media directories and grant the service account access. systemd
   creates `/var/lib/av1-encoder`, `/var/log/av1-encoder`, and the runtime
   directory with the correct ownership:

   ```bash
   sudo mkdir -p /srv/video/incoming /srv/video/av1
   sudo chown -R av1-encoder:av1-encoder /srv/video/incoming /srv/video/av1
   ```

5. Pull the FFmpeg image as the service account:

   ```bash
   sudo -u av1-encoder -H podman pull lscr.io/linuxserver/ffmpeg:latest
   ```

6. Enable and start both services:

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now av1-watcher.service av1-worker.service
   ```

### Migrating an existing installation

After creating the account and installing the updated units, transfer the
service-owned data and media permissions, then pull the image into the new
account's rootless Podman storage:

```bash
sudo systemctl stop av1-watcher.service av1-worker.service
sudo chown -R av1-encoder:av1-encoder /var/lib/av1-encoder /var/log/av1-encoder
sudo chown -R av1-encoder:av1-encoder /srv/video/incoming /srv/video/av1
sudo -u av1-encoder -H podman pull lscr.io/linuxserver/ffmpeg:latest
sudo systemctl daemon-reload
sudo systemctl start av1-watcher.service av1-worker.service
```

The old user's rootless Podman image is not reused because rootless container
storage belongs to the account that created it.

## Configuration

The default configuration file is `/etc/av1-encoder.conf`. Set
`AV1_CONFIG_FILE` in both systemd units if you want to load it from another
location.

| Setting | Purpose | Example |
| --- | --- | --- |
| `SOURCE_ROOT` | Recursively watched source directory | `/srv/video/incoming` |
| `OUTPUT_ROOT` | Root of the mirrored encoded tree | `/srv/video/av1` |
| `QUEUE_DIR` | Pending queue entries | `/var/lib/av1-encoder/queue` |
| `FAILED_DIR` | Queue entries whose encode failed | `/var/lib/av1-encoder/failed` |
| `LOG_DIR` | Per-file FFmpeg logs | `/var/log/av1-encoder` |
| `AV1_PRESET` | SVT-AV1 speed/efficiency preset | `6` |
| `AV1_CRF` | SVT-AV1 quality target; lower is higher quality | `28` |

Keep this file owned by root and not writable by the service account because
the scripts load it as shell code.

## Usage and monitoring

Copy or move supported videos anywhere below `SOURCE_ROOT`. Existing videos
are also queued whenever the watcher starts. Supported extensions are MKV,
MP4, MOV, M4V, AVI, WMV, WebM, MPG, MPEG, TS, and M2TS.

Check service status and follow journal output with:

```bash
systemctl status av1-watcher.service av1-worker.service
journalctl -u av1-watcher.service -u av1-worker.service -f
```

Detailed FFmpeg output is written to `LOG_DIR`. Log filenames are SHA-256
hashes of paths relative to `SOURCE_ROOT`.

To retry a failed item, move its `.queue` file from `FAILED_DIR` back into
`QUEUE_DIR`:

```bash
sudo mv /var/lib/av1-encoder/failed/ENTRY.queue /var/lib/av1-encoder/queue/
```

To force a successfully encoded source to run again, remove both its output
file and adjacent `.done` marker, then restart the watcher or queue the source
manually:

```bash
sudo -u av1-encoder -H \
  /usr/bin/queue-av1-file /srv/video/incoming/path/to/video.mp4
```

## Operational notes

- The worker processes one video at a time.
- Queue entries are deduplicated by a hash of the full input path.
- A source file must report the same size for three checks, ten seconds apart,
  before encoding starts.
- Partial output is removed after an encoding failure.
- Source files are mounted read-only inside the container and are never
  deleted by these scripts.
- Because the image tag is `latest`, pull it deliberately when you want to
  update FFmpeg. Restart the worker after pulling if an encode is active.

## License

This project is licensed under the GNU General Public License, version 3. See
[LICENSE](LICENSE) for the full license text.
