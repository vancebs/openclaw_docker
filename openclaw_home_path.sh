#! /bin/bash
set -euo pipefail

source utils.sh

VOLUME_NAME="${OPENCLAW_HOME_VOLUME:-openclaw_home}"

# Verify the volume exists before inspecting
if ! docker volume inspect "${VOLUME_NAME}" > /dev/null 2>&1; then
    echo "Error: volume '${VOLUME_NAME}' not found. Has the container been started?" >&2
    exit 1
fi

docker volume inspect --format '{{.Mountpoint}}' "${VOLUME_NAME}" 
