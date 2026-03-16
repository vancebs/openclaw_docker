#! /bin/bash

source utils.sh
pushd ${DOCKER_DIR} > /dev/null 2>&1

if [ $# -eq 0 ]; then
    docker_compose exec openclaw-gateway /bin/bash
else
    docker_compose exec openclaw-gateway $@
fi

popd > /dev/null 2>&1
