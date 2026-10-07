#!/usr/bin/env bash
# Pull new images and recreate changed containers.
set -euo pipefail
cd "$(dirname "$0")/../stack"
docker compose pull
docker compose up -d --remove-orphans
docker image prune -f
