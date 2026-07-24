#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEFAULT_CONFIG="$SCRIPT_DIR/server.cfg"
if [ ! -f "$DEFAULT_CONFIG" ] && [ -f "$SCRIPT_DIR/server/server.cfg" ]; then
	DEFAULT_CONFIG="$SCRIPT_DIR/server/server.cfg"
fi
HAS_CONFIG=false

for argument in "$@"; do
	case "$argument" in
		--server-config|--server-config=*)
			HAS_CONFIG=true
			;;
	esac
done

if [ "$HAS_CONFIG" = false ]; then
	if [ ! -f "$DEFAULT_CONFIG" ]; then
		echo "ERROR: Default server config not found: $DEFAULT_CONFIG" >&2
		exit 1
	fi
	set -- --server-config "$DEFAULT_CONFIG" "$@"
fi

case "$(uname -s)" in
	Darwin)
		SERVER_BINARY="$SCRIPT_DIR/LemonShooter.app/Contents/MacOS/LemonShooter"
		;;
	Linux)
		SERVER_BINARY="$SCRIPT_DIR/LemonShooterServer.x86_64"
		;;
	*)
		echo "ERROR: run-server.sh supports macOS and Linux." >&2
		exit 1
		;;
esac

if [ ! -x "$SERVER_BINARY" ]; then
	echo "ERROR: Server binary not found or not executable: $SERVER_BINARY" >&2
	exit 1
fi

exec "$SERVER_BINARY" "$@"
