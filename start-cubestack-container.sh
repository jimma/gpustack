#!/bin/bash
set -e

podman run -d --name gpustack --restart=unless-stopped \
  -e GPUSTACK_RUNTIME_DOCKER_PAUSE_IMAGE=swr.cn-south-1.myhuaweicloud.com/gpustack/runtime:pause \
  -e GPUSTACK_RUNTIME_DOCKER_UNHEALTHY_RESTART_IMAGE=swr.cn-south-1.myhuaweicloud.com/gpustack/runtime:health \
  -e GPUSTACK_IMAGE_NAME_OVERRIDE=harbor.isuanova.com/cubestack/cubestack-express:latest \
  -p 9080:80 \
  --volume gpustack-data:/var/lib/gpustack \
  harbor.isuanova.com/cubestack/cubestack-express:dev \
  --debug --bootstrap-password 'srongpassword'
