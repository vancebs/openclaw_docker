#! /bin/bash

source utils.sh
pushd ${DOCKER_DIR} > /dev/null 2>&1

if [ $# -eq 0 ]; then
    docker_compose logs -f -t openclaw-gateway
else
    docker_compose logs -f -t $@
fi

popd > /dev/null 2>&1
