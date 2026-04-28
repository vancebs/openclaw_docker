#! /bin/bash

source utils.sh
pushd ${DOCKER_DIR} > /dev/null 2>&1

echo "==> Stopping OpenClaw ..."
docker_compose down

popd > /dev/null 2>&1
