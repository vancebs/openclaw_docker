#! /bin/bash

source utils.sh
pushd ${DOCKER_DIR} > /dev/null 2>&1

echo "==> Restarting openclaw ..."
docker_compose restart

popd > /dev/null 2>&1
