# Vidforge

A small Linux service that watches a directory tree for video files and
encodes them to AV1 in a Podman container. Files are placed in a persistent
queue and encoded one at a time, so a restart does not lose pending work.

The output directory mirrors the source directory structure. For example:

```text
/srv/video/incoming/movies/example.mp4
    -> /srv/video/av1/movies/example.av1.mkv
```

## How it works

1. `vidforge-watcher.service` scans existing files and watches for new or moved
   files with `inotifywait`.
2. `vidforge-queue` creates one queue entry per source path.
3. `vidforge-worker.service` processes queue entries sequentially.
4. `vidforge-encode` waits until the source file has stopped growing, then
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
sudo dnf install ./build/rpmbuild/RPMS/noarch/vidforge-*.noarch.rpm
```

The build uses `git archive`, so commit the files you want included first.
After installation, edit `/etc/vidforge.conf`, create and grant access to
the configured media directories, pull the container image, and enable the
services:

```bash
sudoedit /etc/vidforge.conf
sudo mkdir -p /srv/video/incoming /srv/video/av1
sudo chown -R vidforge:vidforge /srv/video/incoming /srv/video/av1
sudo -u vidforge -H podman pull lscr.io/linuxserver/ffmpeg:latest
sudo systemctl enable --now vidforge-watcher.service vidforge-worker.service
```

The RPM preserves a locally edited configuration during upgrades. Before
publishing the package, replace the placeholder maintainer identity in
`packaging/vidforge.spec`.

### Manual installation

Run these commands from the repository root. The units use a dedicated system
account named `vidforge`.

1. Create the service account. Its home directory is also used by rootless
   Podman for persistent container storage:

   ```bash
   sudo useradd --system --user-group \
     --home-dir /var/lib/vidforge --create-home \
     --shell /usr/sbin/nologin vidforge
   ```

   If you use different media mount points, update each `RequiresMountsFor`
   line in `service/` before installing the units.

2. Install the scripts, configuration, and systemd units:

   ```bash
   sudo install -m 0755 scripts/vidforge-worker.sh /usr/bin/vidforge-worker
   sudo install -m 0755 scripts/vidforge-encode.sh /usr/bin/vidforge-encode
   sudo install -m 0755 scripts/vidforge-queue.sh /usr/bin/vidforge-queue
   sudo install -m 0755 scripts/vidforge-watch.sh /usr/bin/vidforge-watch
   sudo install -m 0644 config/vidforge.conf.example /etc/vidforge.conf
   sudo install -m 0644 service/vidforge-watcher.service /etc/systemd/system/vidforge-watcher.service
   sudo install -m 0644 service/vidforge-worker.service /etc/systemd/system/vidforge-worker.service
   ```

3. Edit `/etc/vidforge.conf` to match your directories and desired encoder
   settings:

   ```bash
   sudoedit /etc/vidforge.conf
   ```

4. Create the media directories and grant the service account access. systemd
   creates `/var/lib/vidforge`, `/var/log/vidforge`, and the runtime
   directory with the correct ownership:

   ```bash
   sudo mkdir -p /srv/video/incoming /srv/video/av1
   sudo chown -R vidforge:vidforge /srv/video/incoming /srv/video/av1
   ```

5. Pull the FFmpeg image as the service account:

   ```bash
   sudo -u vidforge -H podman pull lscr.io/linuxserver/ffmpeg:latest
   ```

6. Enable and start both services:

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now vidforge-watcher.service vidforge-worker.service
   ```

### Migrating an existing installation

After creating the account and installing the updated units, transfer the
service-owned data and media permissions, then pull the image into the new
account's rootless Podman storage:

```bash
sudo systemctl stop vidforge-watcher.service vidforge-worker.service
sudo chown -R vidforge:vidforge /var/lib/vidforge /var/log/vidforge
sudo chown -R vidforge:vidforge /srv/video/incoming /srv/video/av1
sudo -u vidforge -H podman pull lscr.io/linuxserver/ffmpeg:latest
sudo systemctl daemon-reload
sudo systemctl start vidforge-watcher.service vidforge-worker.service
```

The old user's rootless Podman image is not reused because rootless container
storage belongs to the account that created it.

## Configuration

The default configuration file is `/etc/vidforge.conf`. Set
`VIDFORGE_CONFIG_FILE` in both systemd units if you want to load it from another
location.

| Setting | Purpose | Example |
| --- | --- | --- |
| `SOURCE_ROOT` | Recursively watched source directory | `/srv/video/incoming` |
| `OUTPUT_ROOT` | Root of the mirrored encoded tree | `/srv/video/av1` |
| `QUEUE_DIR` | Pending queue entries | `/var/lib/vidforge/queue` |
| `FAILED_DIR` | Queue entries whose encode failed | `/var/lib/vidforge/failed` |
| `LOG_DIR` | Per-file FFmpeg logs | `/var/log/vidforge` |
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
systemctl status vidforge-watcher.service vidforge-worker.service
journalctl -u vidforge-watcher.service -u vidforge-worker.service -f
```

Detailed FFmpeg output is written to `LOG_DIR`. Log filenames are SHA-256
hashes of paths relative to `SOURCE_ROOT`.

To retry a failed item, move its `.queue` file from `FAILED_DIR` back into
`QUEUE_DIR`:

```bash
sudo mv /var/lib/vidforge/failed/ENTRY.queue /var/lib/vidforge/queue/
```

To force a successfully encoded source to run again, remove both its output
file and adjacent `.done` marker, then restart the watcher or queue the source
manually:

```bash
sudo -u vidforge -H \
  /usr/bin/vidforge-queue /srv/video/incoming/path/to/video.mp4
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
