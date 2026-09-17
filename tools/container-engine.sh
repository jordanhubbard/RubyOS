#!/usr/bin/env bash
set -euo pipefail

engine="${RUBYOS_CONTAINER_ENGINE:-docker}"
if "$engine" info >/dev/null 2>&1; then
    exec "$engine" "$@"
fi
if [[ "$(uname -s)" == Linux ]] && command -v sudo >/dev/null 2>&1 && sudo "$engine" info >/dev/null 2>&1; then
    exec sudo "$engine" "$@"
fi
exec "$engine" "$@"
