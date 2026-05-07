#! /bin/bash
set -euo pipefail

# load env
source utils.sh

DOCKER_REGISTRY="${OPENCLAW_DOCKER_REGISTRY:-harbor.t2mobile.com/library/}"

# get parameters
while [ $# -ge 1 ]; do
    case $1 in
        -p | --push)
            PARAM_PUSH=1
            ;;
        *)
            # assume it's version
            PARAM_PUSH=0
    esac

    # next
    shift
done

PARAM_PUSH=${PARAM_PUSH:-0}
OPENCLAW_IMG_VERSION="${OPENCLAW_IMG_VERSION:-latest}"
OPENCLAW_IMAGE="${OPENCLAW_IMAGE:-openclaw-hf}"

# build images
echo "==> Building images ..."
IMAGE_NAME="${OPENCLAW_IMAGE}:${OPENCLAW_IMG_VERSION}"
docker build \
    -f "${DOCKER_DIR}/openclaw/Dockerfile" \
    -t "${IMAGE_NAME}" \
    --build-arg OPENCLAW_BASE_IMAGE="${OPENCLAW_BASE_IMAGE:-ghcr.io/openclaw/openclaw}:${OPENCLAW_IMG_VERSION}" \
    "${DOCKER_DIR}/openclaw"
if [ $? -ne 0 ]; then
    echo "    Building images ...Failed"
    exit 1
fi
echo "    Building images ...Done"

echo "==> Tagging images ..."
REMOTE_NAME="${DOCKER_REGISTRY}${OPENCLAW_IMAGE}:${OPENCLAW_IMG_VERSION}"
REMOTE_NAME_LATEST="${DOCKER_REGISTRY}${OPENCLAW_IMAGE}:latest"

echo -e "\e[32mremote: ${REMOTE_NAME}\e[0m"
echo -e "\e[32mremote: ${REMOTE_NAME_LATEST}\e[0m"

docker tag "${IMAGE_NAME}" "${REMOTE_NAME}"
docker tag "${IMAGE_NAME}" "${REMOTE_NAME_LATEST}"
echo "    Tagging images ...Done"

if [ $PARAM_PUSH -eq 1 ]; then
    echo "==> Pushing images ..."
    docker push "${REMOTE_NAME}"
    docker push "${REMOTE_NAME_LATEST}"
    echo "    Pushing images ...Done"
fi



