# The image behind `make linux-smoke`: Ubuntu, the Flutter desktop build prerequisites, a virtual display, Rust.
# Build it with `make linux-smoke-image` (tools/linux-smoke.sh image); the run itself then needs no network except `flutter pub get`
# and the Rust crates of notes_rust (both cached in two named volumes).
#
# Pins (everything is pinned by version and checked against a hash; the source of each is written to /opt/linux-smoke-pins.txt):
#   Flutter 3.41.9  git tag 3.41.9 = commit 00b0c91f06209d9e4a41f71b7a512d6eb3b9c694, the version of the maintainer's host.
#                   Flutter publishes no Linux arm64 archive, so it is cloned at the tag (the commit is checked) and its engine
#                   artifacts are downloaded by `flutter precache`; the Dart SDK zip for the engine hash is checked by sha256.
#   Rust 1.98.1     through rustup-init 1.29.2 (sha256 checked), profile minimal. notes_rust needs Rust 1.94 or later.
# Tested on linux/arm64 (Docker on Apple silicon). The linux/amd64 hashes are included but that path was not run.
FROM ubuntu:24.04

ARG TARGETARCH
ARG PIN_FLUTTER_VERSION=3.41.9
ARG PIN_FLUTTER_COMMIT=00b0c91f06209d9e4a41f71b7a512d6eb3b9c694
# engine revision as bin/internal/engine.version says (the host's `flutter --version` prints the engine content hash 9161402dc0e1...; the Dart SDK zip is
# byte-identical under both ids, checked)
# (named PIN_*, not FLUTTER_*: the Flutter tool reads a FLUTTER_ENGINE variable as the path of a local engine build)
ARG PIN_ENGINE_REV=42d3d75a56efe1a2e9902f52dc8006099c45d937
ARG DART_SDK_SHA256_ARM64=30eb1852d922ad02bf8e922ae82f7b5f20eab48e148a6eaf3c98309ccc75b5aa
ARG DART_SDK_SHA256_AMD64=16a40e0db2351260380f832078aeee71124382fbc7ba4c8201b0b49801b6f710
ARG PIN_RUST_VERSION=1.98.1
ARG PIN_RUSTUP_VERSION=1.29.2
ARG PIN_RUSTUP_INIT_SHA256_ARM64=a9c168dbea81a84671c6b7a5c1795cb0eb699020110d107ddfca427bd797e697
ARG PIN_RUSTUP_INIT_SHA256_AMD64=5be191e8c70a5007074254cb74d78dbfdd25cd5a61c27de7b8e5410122ec24f4

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

# Desktop build prerequisites (what `flutter doctor` asks for on Linux), then the virtual display and screenshot tools.
# libgl1-mesa-dri / libegl1 give Flutter's GTK embedder a software OpenGL (llvmpipe) under Xvfb; fonts-dejavu-core is there because
# without any font installed Flutter draws no text at all. dbus-x11 gives GTK a session bus.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip xz-utils zip file python3 \
      clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-13-dev build-essential \
      xvfb xauth x11-utils x11-apps x11-xserver-utils xdotool imagemagick dbus-x11 \
      libgl1-mesa-dri libglx-mesa0 libegl1 libegl-mesa0 libgles2 fonts-dejavu-core \
 && rm -rf /var/lib/apt/lists/*

# An unprivileged user: the real thing a person would build as, and Flutter warns about root.
# (Ubuntu 24.04 ships a user `ubuntu` with uid 1000; removed so the unprivileged user can have uid 1000, which owns files on most Linux hosts.)
RUN (userdel -r ubuntu 2>/dev/null || true) \
 && useradd --create-home --home-dir /srv/smoke --uid 1000 --shell /bin/bash smoke \
 && mkdir -p /opt/rustup /opt/cargo/registry /opt/cargo/git /opt/flutter /srv/smoke/.pub-cache /work /out \
 && touch /opt/linux-smoke-pins.txt \
 && chown -R smoke:smoke /opt/rustup /opt/cargo /opt/flutter /opt/linux-smoke-pins.txt /srv/smoke /work /out

USER smoke
ENV HOME=/srv/smoke \
    RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo \
    PUB_CACHE=/srv/smoke/.pub-cache \
    FLUTTER_ROOT=/opt/flutter \
    PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:/opt/cargo/bin:/usr/local/bin:/usr/bin:/bin

RUN set -eu; \
    git clone --quiet --branch "$PIN_FLUTTER_VERSION" --depth 1 https://github.com/flutter/flutter.git /opt/flutter; \
    [ "$(git -C /opt/flutter rev-parse HEAD)" = "$PIN_FLUTTER_COMMIT" ] || { echo "Flutter tag $PIN_FLUTTER_VERSION is not commit $PIN_FLUTTER_COMMIT" >&2; exit 1; }; \
    [ "$(cat /opt/flutter/bin/internal/engine.version)" = "$PIN_ENGINE_REV" ] || { echo "unexpected engine hash" >&2; exit 1; }; \
    case "$TARGETARCH" in arm64) da=arm64; dsha=$DART_SDK_SHA256_ARM64 ;; amd64) da=x64; dsha=$DART_SDK_SHA256_AMD64 ;; *) echo "unsupported arch $TARGETARCH" >&2; exit 1 ;; esac; \
    dart_url="https://storage.googleapis.com/flutter_infra_release/flutter/$PIN_ENGINE_REV/dart-sdk-linux-$da.zip"; \
    got=$(curl -fsSL "$dart_url" | sha256sum | cut -d' ' -f1); \
    [ "$got" = "$dsha" ] || { echo "Dart SDK zip sha256 $got, expected $dsha" >&2; exit 1; }; \
    flutter config --no-analytics --no-cli-animations --enable-linux-desktop; \
    flutter precache --linux; \
    { echo "flutter $PIN_FLUTTER_VERSION"; \
      echo "  source: https://github.com/flutter/flutter.git tag $PIN_FLUTTER_VERSION"; \
      echo "  commit: $PIN_FLUTTER_COMMIT"; \
      echo "  engine: $PIN_ENGINE_REV"; \
      echo "  dart sdk: $dart_url"; \
      echo "  dart sdk sha256: $dsha"; } > /opt/linux-smoke-pins.txt

RUN set -eu; \
    case "$TARGETARCH" in arm64) triple=aarch64-unknown-linux-gnu; rsha=$PIN_RUSTUP_INIT_SHA256_ARM64 ;; amd64) triple=x86_64-unknown-linux-gnu; rsha=$PIN_RUSTUP_INIT_SHA256_AMD64 ;; *) echo "unsupported arch $TARGETARCH" >&2; exit 1 ;; esac; \
    url="https://static.rust-lang.org/rustup/archive/$PIN_RUSTUP_VERSION/$triple/rustup-init"; \
    curl -fsSL "$url" -o /tmp/rustup-init; \
    echo "$rsha  /tmp/rustup-init" | sha256sum -c -; \
    chmod +x /tmp/rustup-init; \
    /tmp/rustup-init -y --no-modify-path --profile minimal --default-toolchain "$PIN_RUST_VERSION"; \
    rm /tmp/rustup-init; \
    { echo "rustup-init $PIN_RUSTUP_VERSION"; echo "  source: $url"; echo "  sha256: $rsha"; echo "rust $PIN_RUST_VERSION (rustup profile minimal)"; } >> /opt/linux-smoke-pins.txt; \
    rustc --version; cargo --version; flutter --version; cat /opt/linux-smoke-pins.txt

WORKDIR /work
