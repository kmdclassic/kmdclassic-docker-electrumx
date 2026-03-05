#!/bin/sh
# Compact ElectrumX history DB (resets flush_count), then restart the server.
# Use when you hit: struct.error: 'H' format requires 0 <= number <= 65535

set -e

COMPOSE_DIR="${COMPOSE_DIR:-$(cd "$(dirname "$0")" && pwd)}"
cd "$COMPOSE_DIR"

echo "Stopping electrumx..."
docker compose stop electrumx

echo "Running electrumx_compact_history (same env/volumes as service)..."
if ! docker compose run --rm electrumx electrumx_compact_history; then
    echo "Compact failed. Not restarting electrumx. Fix and run: docker compose start electrumx"
    exit 1
fi

echo "Starting electrumx..."
docker compose start electrumx

echo "Done. electrumx is running again."
