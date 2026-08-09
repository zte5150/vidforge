Name:           av1-encoder
Version:        0.1.0
Release:        1%{?dist}
Summary:        Directory-watching AV1 video encoding service

License:        GPL-3.0-only
URL:            https://github.com/zte5150/encode_videos_service
Source0:        %{name}-%{version}.tar.gz
Source1:        %{name}.sysusers

BuildArch:      noarch
BuildRequires:  systemd-rpm-macros
Requires:       bash
Requires:       coreutils
Requires:       findutils
Requires:       inotify-tools
Requires:       podman
%{?systemd_requires}

%description
A pair of service units that watch a directory tree, persistently queue video
files, and encode them to AV1 one at a time using FFmpeg in Podman.

%prep
%autosetup

%build

%install
install -Dpm 0755 scripts/av1-queue-worker.sh \
    "%{buildroot}%{_bindir}/av1-queue-worker"
install -Dpm 0755 scripts/encode-av1-file.sh \
    "%{buildroot}%{_bindir}/encode-av1-file"
install -Dpm 0755 scripts/queue-av1-file.sh \
    "%{buildroot}%{_bindir}/queue-av1-file"
install -Dpm 0755 scripts/watch-av1-folder.sh \
    "%{buildroot}%{_bindir}/watch-av1-folder"
install -Dpm 0644 config/av1-encoder.conf.example \
    "%{buildroot}%{_sysconfdir}/av1-encoder.conf"
install -Dpm 0644 service/av1-watcher.service \
    "%{buildroot}%{_unitdir}/av1-watcher.service"
install -Dpm 0644 service/av1-worker.service \
    "%{buildroot}%{_unitdir}/av1-worker.service"
install -Dpm 0644 "%{SOURCE1}" \
    "%{buildroot}%{_sysusersdir}/av1-encoder.conf"

%pre
%sysusers_create_compat %{SOURCE1}

%post
%systemd_post av1-watcher.service av1-worker.service

%preun
%systemd_preun av1-watcher.service av1-worker.service

%postun
%systemd_postun_with_restart av1-watcher.service av1-worker.service

%files
%doc README.md
%license LICENSE
%config(noreplace) %{_sysconfdir}/av1-encoder.conf
%{_bindir}/av1-queue-worker
%{_bindir}/encode-av1-file
%{_bindir}/queue-av1-file
%{_bindir}/watch-av1-folder
%{_unitdir}/av1-watcher.service
%{_unitdir}/av1-worker.service
%{_sysusersdir}/av1-encoder.conf

%changelog
* Sat Aug 08 2026 Package Maintainer <zte5150@icloud.com> - 0.1.0-1
- Initial RPM package
