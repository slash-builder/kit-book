#!/bin/sh
# Build the demo apps for Linux in a container and launch each under a virtual display (make linux-smoke-image, make linux-smoke).
#
#   tools/linux-smoke.sh image   build the Docker image (Ubuntu, Flutter and Rust pinned, Xvfb, ImageMagick, xdotool); slow once, cached
#   tools/linux-smoke.sh run     the smoke test; results in build/linux-smoke/results.md, screenshots beside it
#
# The repository is mounted read-only at /src; everything the container builds is in its own disk, and only build/linux-smoke is
# written back. Two named volumes cache the Dart packages and the Rust crates between runs (LINUX_SMOKE_NOCACHE=1 does without).
# Variables: LINUX_SMOKE_APPS (space separated app folders; default every app that can be built here), LINUX_SMOKE_IMAGE (image name),
# LINUX_SMOKE_PLATFORM (docker --platform, default the daemon's own), LINUX_SMOKE_UP / LINUX_SMOKE_SHOT_AT (seconds), LINUX_SMOKE_PEERS
# (apps for the two-copies check; default "stopwatch notepad").
# What the run proves and does not prove is in book/90-reference/make-targets.md and book/20-guides/demo-apps.md.
set -u
. "$(dirname "$0")/common.sh"
cd "$ROOT"

MODE=${1:-run}
IMAGE=${LINUX_SMOKE_IMAGE:-kit-book-linux-smoke:flutter-3.41.9}
OUT="$ROOT/build/linux-smoke"

have docker || die "docker is not installed (https://docs.docker.com/get-docker/)"
docker info >/dev/null 2>&1 || die "the docker daemon is not running"

PLATFORM_ARGS=""
[ -n "${LINUX_SMOKE_PLATFORM:-}" ] && PLATFORM_ARGS="--platform $LINUX_SMOKE_PLATFORM"

case "$MODE" in
  image)
    mkdir -p "$OUT"
    say "==> building $IMAGE (first time: several minutes, a few GB; log: build/linux-smoke/image-build.log)"
    # shellcheck disable=SC2086
    if docker build $PLATFORM_ARGS -t "$IMAGE" -f tools/linux-smoke/Dockerfile tools/linux-smoke > "$OUT/image-build.log" 2>&1; then
      say "built $IMAGE"
      docker run --rm "$IMAGE" cat /opt/linux-smoke-pins.txt
    else
      tail -n 30 "$OUT/image-build.log" >&2
      die "the image build failed; the whole log is build/linux-smoke/image-build.log"
    fi
    ;;
  run)
    docker image inspect "$IMAGE" >/dev/null 2>&1 || die "the image $IMAGE is not built. Run: make linux-smoke-image"
    [ -d "$KITS_DIR/app-context-kit" ] || die "the App Context Kit is not fetched. Run: make setup (KITS=all while it is private)"
    for k in "$KITS_DIR"/*; do
      [ -L "$k" ] && die "$k is a link (kits.override): the container sees only this repository, so a link out of it would dangle. Use the pinned Kits (empty kits.override)."
    done
    apps=${LINUX_SMOKE_APPS:-}
    if [ -z "$apps" ]; then
      for d in "$ROOT"/apps/*/; do
        a=$(basename "$d")
        why=$(app_skip_reason "$d")
        if [ -n "$why" ]; then say "skipped apps/$a: $why"; continue; fi
        apps="$apps $a"
      done
    fi
    apps=$(printf '%s' "$apps" | sed 's/^ *//')
    [ -n "$apps" ] || die "no app to test"
    # a fresh result set; keep the image build log
    mkdir -p "$OUT"
    for a in $apps; do rm -rf "$OUT/$a" "$OUT/$a"-*.png; done
    rm -f "$OUT/results.md" "$OUT/image-pins.txt"
    chmod a+rwx "$OUT" 2>/dev/null || true
    cache=""
    if [ -z "${LINUX_SMOKE_NOCACHE:-}" ]; then
      cache="-v kit-book-linux-smoke-pub:/srv/smoke/.pub-cache -v kit-book-linux-smoke-cargo-registry:/opt/cargo/registry -v kit-book-linux-smoke-cargo-git:/opt/cargo/git"
    fi
    say "==> linux-smoke: $apps  (image $IMAGE)"
    # shellcheck disable=SC2086
    docker run --rm --init --shm-size=512m $PLATFORM_ARGS \
      -v "$ROOT:/src:ro" -v "$OUT:/out" $cache \
      -e "LINUX_SMOKE_APPS=$apps" \
      -e "LINUX_SMOKE_UP=${LINUX_SMOKE_UP:-10}" -e "LINUX_SMOKE_SHOT_AT=${LINUX_SMOKE_SHOT_AT:-6}" \
      -e "LINUX_SMOKE_PEERS=${LINUX_SMOKE_PEERS:-stopwatch notepad}" \
      "$IMAGE" bash /src/tools/linux-smoke/in-container.sh
    rc=$?
    say ""
    say "results: build/linux-smoke/results.md   screenshots: build/linux-smoke/*.png"
    exit $rc
    ;;
  *) die "usage: linux-smoke.sh image|run" ;;
esac
