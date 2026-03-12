#! /bin/bash

source utils.sh
pushd ${DOCKER_DIR} > /dev/null 2>&1

docker_compose exec openclaw-gateway openclaw $@

popd > /dev/null 2>&1
