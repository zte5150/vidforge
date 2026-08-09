Name:           vidforge
Version:        0.1.0
Release:        1%{?dist}
Summary:        Vidforge directory-watching video encoding service

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
install -Dpm 0755 scripts/vidforge-worker.sh \
    "%{buildroot}%{_bindir}/vidforge-worker"
install -Dpm 0755 scripts/vidforge-encode.sh \
    "%{buildroot}%{_bindir}/vidforge-encode"
install -Dpm 0755 scripts/vidforge-queue.sh \
    "%{buildroot}%{_bindir}/vidforge-queue"
install -Dpm 0755 scripts/vidforge-watch.sh \
    "%{buildroot}%{_bindir}/vidforge-watch"
install -Dpm 0644 config/vidforge.conf.example \
    "%{buildroot}%{_sysconfdir}/vidforge.conf"
install -Dpm 0644 service/vidforge-watcher.service \
    "%{buildroot}%{_unitdir}/vidforge-watcher.service"
install -Dpm 0644 service/vidforge-worker.service \
    "%{buildroot}%{_unitdir}/vidforge-worker.service"
install -Dpm 0644 "%{SOURCE1}" \
    "%{buildroot}%{_sysusersdir}/vidforge.conf"

%pre
%sysusers_create_compat %{SOURCE1}

%post
%systemd_post vidforge-watcher.service vidforge-worker.service

%preun
%systemd_preun vidforge-watcher.service vidforge-worker.service

%postun
%systemd_postun_with_restart vidforge-watcher.service vidforge-worker.service

%files
%doc README.md
%license LICENSE
%config(noreplace) %{_sysconfdir}/vidforge.conf
%{_bindir}/vidforge-worker
%{_bindir}/vidforge-encode
%{_bindir}/vidforge-queue
%{_bindir}/vidforge-watch
%{_unitdir}/vidforge-watcher.service
%{_unitdir}/vidforge-worker.service
%{_sysusersdir}/vidforge.conf

%changelog
* Sat Aug 08 2026 Package Maintainer <zte5150@icloud.com> - 0.1.0-1
- Initial RPM package
