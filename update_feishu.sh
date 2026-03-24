#! /bin/bash

source utils.sh
pushd ${DOCKER_DIR} > /dev/null 2>&1

echo "==> Updating Feishu ..."
docker_compose run --rm openclaw-gateway \
    pnpx @larksuite/openclaw-lark update

popd > /dev/null 2>&1
