#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT_DIR/builds"
LOG_DIR="$BUILD_DIR/logs"
MODE="release"
TARGET="all"
CLEAN=false

usage() {
  cat <<'EOF'
Build LemonShooter dedicated servers.

Usage:
  ./build.sh [all|linux|windows|macos] [--release|--debug] [--clean]

Environment:
  GODOT_BIN  Optional path to the Godot 4.7 executable
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

for argument in "$@"; do
  case "$argument" in
    all|linux|windows|macos)
      TARGET="$argument"
      ;;
    --release)
      MODE="release"
      ;;
    --debug)
      MODE="debug"
      ;;
    --clean)
      CLEAN=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "Unknown argument: $argument"
      ;;
  esac
done

find_godot() {
  if [[ -n "${GODOT_BIN:-}" ]]; then
    [[ -x "$GODOT_BIN" ]] || die "GODOT_BIN is not executable: $GODOT_BIN"
    printf '%s\n' "$GODOT_BIN"
    return
  fi
  local candidate
  for candidate in \
    "$(command -v godot 2>/dev/null || true)" \
    "$(command -v godot4 2>/dev/null || true)" \
    "/Applications/Godot_mono.app/Contents/MacOS/Godot" \
    "/Applications/Godot.app/Contents/MacOS/Godot"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done
  die "Godot 4.7 was not found. Install it or set GODOT_BIN."
}

GODOT="$(find_godot)"
EXPORT_FLAG="--export-$MODE"

mkdir -p "$LOG_DIR"
if [[ "$CLEAN" == true ]]; then
  case "$TARGET" in
    all)
      rm -rf "$BUILD_DIR/server-linux" "$BUILD_DIR/server-windows" "$BUILD_DIR/server-macos" "$LOG_DIR"
      mkdir -p "$LOG_DIR"
      ;;
    *)
      rm -rf "$BUILD_DIR/server-$TARGET"
      ;;
  esac
fi

run_export() {
  local preset="$1"
  local output="$2"
  local log_file="$3"

  mkdir -p "$(dirname "$output")" "$(dirname "$log_file")"
  rm -f "$output"
  echo "==> $preset ($MODE)"
  set +e
  "$GODOT" --headless --path "$ROOT_DIR" "$EXPORT_FLAG" "$preset" "$output" >"$log_file" 2>&1
  local export_status=$?
  set -e
  if [[ $export_status -ne 0 || ! -s "$output" ]]; then
    tail -n 100 "$log_file" >&2
    die "$preset did not produce an artifact."
  fi
}

verify_zip() {
  local archive="$1"
  unzip -tq "$archive" >/dev/null || die "ZIP verification failed: $archive"
}

smoke_server_package() {
  local package="$1"
  local label="$2"
  local map_id
  local port=17600
  local log_file

  for map_id in training_arena warehouse twin_bastion highrise city suburban_test_site; do
    log_file="$LOG_DIR/$label-smoke-$map_id.log"
    set +e
    "$GODOT" --headless --main-pack "$package" --quit-after 600 -- \
      --server-config="$ROOT_DIR/server/server.cfg" --private --port="$port" \
      --smoke-match --smoke-map="$map_id" >"$log_file" 2>&1
    local smoke_status=$?
    set -e
    if [[ $smoke_status -ne 0 ]] \
      || grep -Eq "SCRIPT ERROR|Parse Error|ERROR:" "$log_file" \
      || ! grep -q "Match smoke passed for $map_id" "$log_file"; then
      tail -n 120 "$log_file" >&2
      die "Packaged server smoke failed for $map_id. Log: $log_file"
    fi
    port=$((port + 1))
  done
  echo "    Smoked all core maps from the packaged server data."
}

package_server() {
  local directory="$1"
  local executable="$2"
  local package="$3"
  local archive="$4"

  [[ -s "$executable" ]] || die "Missing server executable: $executable"
  [[ -s "$package" ]] || die "Missing server data package: $package"
  cp "$ROOT_DIR/server/server.cfg" "$directory/server.cfg"
  cp "$ROOT_DIR/server/README.md" "$directory/HOSTING.md"
  cp "$ROOT_DIR/LICENSE" "$directory/LICENSE"
  (
    cd "$directory"
    zip -q -9 "$(basename "$archive")" \
      "$(basename "$executable")" "$(basename "$package")" server.cfg HOSTING.md LICENSE
  )
  verify_zip "$archive"
}

build_linux() {
  local directory="$BUILD_DIR/server-linux"
  local executable="$directory/LemonShooterServer.x86_64"
  local package="$directory/LemonShooterServer.pck"
  local archive="$directory/LemonShooter-Server-Linux-x86_64.zip"

  mkdir -p "$directory"
  rm -f "$executable" "$package" "$archive"
  run_export "Linux Dedicated Server" "$executable" "$LOG_DIR/server-linux-$MODE.log"
  chmod +x "$executable"
  smoke_server_package "$package" "server-linux-$MODE"
  package_server "$directory" "$executable" "$package" "$archive"
  echo "    Verified $archive"
}

build_windows() {
  local directory="$BUILD_DIR/server-windows"
  local executable="$directory/LemonShooterServer.exe"
  local package="$directory/LemonShooterServer.pck"
  local archive="$directory/LemonShooter-Server-Windows-x86_64.zip"

  mkdir -p "$directory"
  rm -f "$executable" "$package" "$archive"
  run_export "Windows Dedicated Server" "$executable" "$LOG_DIR/server-windows-$MODE.log"
  smoke_server_package "$package" "server-windows-$MODE"
  package_server "$directory" "$executable" "$package" "$archive"
  echo "    Verified $archive"
}

build_macos() {
  local directory="$BUILD_DIR/server-macos"
  local archive="$directory/LemonShooter-Server-macOS-Universal.zip"
  local app_prefix="LemonShooter.app/Contents"
  local smoke_directory

  mkdir -p "$directory"
  rm -f "$archive"
  run_export "macOS Dedicated Server" "$archive" "$LOG_DIR/server-macos-$MODE.log"
  verify_zip "$archive"
  unzip -Z1 "$archive" | grep -qx "$app_prefix/MacOS/LemonShooter" \
    || die "macOS archive is missing its executable."
  unzip -Z1 "$archive" | grep -qx "$app_prefix/Resources/LemonShooter.pck" \
    || die "macOS archive is missing its data package."
  smoke_directory="$(mktemp -d)"
  unzip -p "$archive" "$app_prefix/Resources/LemonShooter.pck" >"$smoke_directory/LemonShooter.pck"
  smoke_server_package "$smoke_directory/LemonShooter.pck" "server-macos-$MODE"
  rm -rf -- "$smoke_directory"
  (
    cd "$ROOT_DIR"
    zip -q -9 "$archive" server/server.cfg server/README.md LICENSE
  )
  verify_zip "$archive"
  echo "    Verified $archive"
}

echo "LemonShooter dedicated-server build"
echo "Godot: $GODOT"
echo "Mode: $MODE"
echo "Target: $TARGET"

case "$TARGET" in
  all)
    build_linux
    build_windows
    build_macos
    ;;
  linux) build_linux ;;
  windows) build_windows ;;
  macos) build_macos ;;
esac

echo "Build complete."
