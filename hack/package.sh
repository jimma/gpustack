#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "${ROOT_DIR}/hack/lib/init.sh"

PACKAGE_NAMESPACE=${PACKAGE_NAMESPACE:-gpustack}
PACKAGE_REPOSITORY=${PACKAGE_REPOSITORY:-gpustack}
PACKAGE_ARCH=${PACKAGE_ARCH:-$(uname -m | sed 's/aarch64/arm64/' | sed 's/x86_64/amd64/')}
PACKAGE_TAG=${PACKAGE_TAG:-dev}
PACKAGE_WITH_CACHE=${PACKAGE_WITH_CACHE:-true}
PACKAGE_PUSH=${PACKAGE_PUSH:-false}
PACKAGE_UI_DOWNLOAD=${PACKAGE_UI_DOWNLOAD:-true}
PACKAGE_UI_LOCAL_PATH=${UI_LOCAL_PATH:-}
PACKAGE_BINFMT_IMAGE=${PACKAGE_BINFMT_IMAGE:-docker.1panel.live/tonistiigi/binfmt:qemu-v9.2.2-52}
UI_STAGING_DIR="${ROOT_DIR}/pack/.ui-local"

# Detect container runtime: "docker", "podman-docker", "podman", or "none"
function detect_runtime() {
    if command -v docker &>/dev/null; then
        if docker --version 2>/dev/null | grep -qi podman; then
            echo "podman-docker"
        elif docker info &>/dev/null; then
            echo "docker"
        elif command -v podman &>/dev/null; then
            # Docker CLI is installed but no daemon is reachable; fall back to Podman.
            echo "podman"
        else
            echo "none"
        fi
    elif command -v podman &>/dev/null; then
        echo "podman"
    else
        echo "none"
    fi
}

function pack() {
    local runtime
    runtime=$(detect_runtime)

    if [[ "${runtime}" == "none" ]]; then
        gpustack::log::fatal "Neither Docker nor Podman is installed. Please install one to use this target."
    fi

    gpustack::log::info "using container runtime: ${runtime}"

    LABELS=("org.opencontainers.image.source=https://github.com/gpustack/gpustack" "org.opencontainers.image.version=main" "org.opencontainers.image.revision=$(git rev-parse HEAD 2>/dev/null || echo "unknown")" "org.opencontainers.image.created=$(date +"%Y-%m-%dT%H:%M:%S.%s")");
    TAG="${PACKAGE_NAMESPACE}/${PACKAGE_REPOSITORY}:${PACKAGE_TAG}"

    # Stage local UI assets if PACKAGE_UI_LOCAL_PATH is set
    UI_LOCAL_FLAG=""
    if [[ -n "${PACKAGE_UI_LOCAL_PATH}" ]]; then
        gpustack::log::info "staging local UI assets from '${PACKAGE_UI_LOCAL_PATH}'"
        if [[ ! -d "${PACKAGE_UI_LOCAL_PATH}" ]]; then
            gpustack::log::fatal "local UI path '${PACKAGE_UI_LOCAL_PATH}' does not exist or is not a directory"
        fi
        rm -rf "${UI_STAGING_DIR}"
        mkdir -p "${UI_STAGING_DIR}"
        cp -a "${PACKAGE_UI_LOCAL_PATH}/." "${UI_STAGING_DIR}/"
        UI_LOCAL_FLAG="--build-arg UI_LOCAL_PATH=/workspace/gpustack/pack/.ui-local"
    fi

    local build_cmd
    local build_cmd_label=""

    if [[ "${runtime}" == "docker" ]]; then
        # --- Docker (with buildx) ---
        if ! docker buildx inspect --builder "gpustack" &>/dev/null; then
            gpustack::log::info "Creating new buildx builder 'gpustack'"
            docker run --rm --privileged "${PACKAGE_BINFMT_IMAGE}" --uninstall qemu-*
            docker run --rm --privileged "${PACKAGE_BINFMT_IMAGE}" --install all
            docker buildx create \
                --name "gpustack" \
                --driver "docker-container" \
                --driver-opt "network=host,default-load=true,env.BUILDKIT_STEP_LOG_MAX_SIZE=-1,env.BUILDKIT_STEP_LOG_MAX_SPEED=-1" \
                --buildkitd-flags "--allow-insecure-entitlement=security.insecure --allow-insecure-entitlement=network.host --oci-worker-net=host --oci-worker-gc-keepstorage=204800" \
                --bootstrap
        fi

        local docker_extra_args=()
        if [[ "${PACKAGE_WITH_CACHE}" == "true" ]]; then
            docker_extra_args+=("--cache-from=type=registry,ref=gpustack/build-cache:gpustack-main")
        fi
        if [[ "${PACKAGE_PUSH}" == "true" ]]; then
            docker_extra_args+=("--push")
        fi
        for label in "${LABELS[@]}"; do
            docker_extra_args+=("--label" "${label}")
        done
        build_cmd_label="docker buildx"
    else
        # --- Podman (native or via podman-docker) ---
        build_cmd="podman"
        local podman_extra_args=()
        for label in "${LABELS[@]}"; do
            podman_extra_args+=("--label" "${label}")
        done
        build_cmd_label="podman"
    fi

    gpustack::log::info "Building '${TAG}' platform 'linux/${PACKAGE_ARCH}'"
    set -x
    if [[ "${runtime}" == "docker" ]]; then
        docker buildx build \
            --pull \
            --allow network.host \
            --allow security.insecure \
            --builder "gpustack" \
            --platform "linux/${PACKAGE_ARCH}" \
            --tag "${TAG}" \
            --file "${ROOT_DIR}/pack/Dockerfile" \
            --ulimit nofile=65536:65536 \
            --shm-size 16G \
            --progress plain \
            --build-arg "GPUSTACK_RUNTIME_DOCKER_MIRRORED_NAME_FILTER_LABELS=$(printf "%s;" "${LABELS[@]}")" \
            --build-arg "UI_DOWNLOAD=${PACKAGE_UI_DOWNLOAD}" \
            ${UI_LOCAL_FLAG} \
            "${docker_extra_args[@]}" \
            "${ROOT_DIR}"
    else
        podman build \
            --pull \
            --platform "linux/${PACKAGE_ARCH}" \
            --tag "${TAG}" \
            --file "${ROOT_DIR}/pack/Dockerfile" \
            --ulimit nofile=65536:65536 \
            --shm-size 16G \
            --build-arg "GPUSTACK_RUNTIME_DOCKER_MIRRORED_NAME_FILTER_LABELS=$(printf "%s;" "${LABELS[@]}")" \
            --build-arg "UI_DOWNLOAD=${PACKAGE_UI_DOWNLOAD}" \
            ${UI_LOCAL_FLAG} \
            "${podman_extra_args[@]}" \
            "${ROOT_DIR}"
    fi
    set +x

    # Push if requested (podman uses separate push step)
    if [[ "${runtime}" != "docker" ]] && [[ "${PACKAGE_PUSH}" == "true" ]]; then
        gpustack::log::info "Pushing '${TAG}'"
        podman push "${TAG}"
    fi

    # Clean up staged UI assets
    if [[ -n "${PACKAGE_UI_LOCAL_PATH}" ]]; then
        rm -rf "${UI_STAGING_DIR}"
    fi
}

gpustack::log::info "+++ PACKAGE +++"
pack
gpustack::log::info "--- PACKAGE ---"
