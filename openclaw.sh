#! /bin/bash

source utils.sh

docker_compose exec openclaw-gateway openclaw $@
