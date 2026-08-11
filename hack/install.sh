#!/usr/bin/env bash

# Set error handling
set -o errexit
set -o nounset
set -o pipefail

# Get the root directory and third_party directory
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# Include the common functions
source "${ROOT_DIR}/hack/lib/init.sh"

function download_deps() {
  if ! command -v uv &> /dev/null; then
    pip install uv
  fi
  # uv sync --all-extras to install all dependencies
  uv sync --locked
  if [[ "${DEPS_ONLY:-false}" == "false" ]]; then
    uv pip install pre-commit==3.7.1
    uv run pre-commit install
  fi
}

function download_ui() {
  if [[ "${UI_DOWNLOAD:-true}" != "true" ]]; then
    gpustack::log::info "skipping UI assets download"
    return
  fi

  local default_tag="latest"
  local ui_path="${ROOT_DIR}/gpustack/ui"
  local tmp_ui_path="${ui_path}/tmp"
  local tag="latest"

  if [[ "${GIT_VERSION}" != "v0.0.0" ]]; then
    tag="${GIT_VERSION}"
  fi

  rm -rf "${ui_path}"
  mkdir -p "${tmp_ui_path}/ui"

  # If UI_LOCAL_PATH is set, copy UI assets from local path instead of downloading
  if [[ -n "${UI_LOCAL_PATH:-}" ]]; then
    gpustack::log::info "using local UI assets from '${UI_LOCAL_PATH}'"
    if [[ ! -d "${UI_LOCAL_PATH}" ]]; then
      gpustack::log::fatal "local UI path '${UI_LOCAL_PATH}' does not exist or is not a directory"
    fi
    cp -a "${UI_LOCAL_PATH}/." "${ui_path}"
    rm -rf "${tmp_ui_path}"
    return
  fi

  gpustack::log::info "downloading '${tag}' UI assets"

  if ! curl --retry 3 --retry-connrefused --retry-delay 3 -sSfL "https://gpustack-ui-1303613262.cos.accelerate.myqcloud.com/releases/${tag}.tar.gz" 2>/dev/null |
    tar -xzf - --directory "${tmp_ui_path}/ui" 2>/dev/null; then

    if [[ "${tag:-}" =~ ^v([0-9]+)\.([0-9]+)(\.[0-9]+)?(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
      gpustack::log::fatal "failed to download '${tag}' ui archive"
    fi

    gpustack::log::warn "failed to download '${tag}' ui archive, fallback to '${default_tag}' ui archive"
    if ! curl --retry 3 --retry-connrefused --retry-delay 3 -sSfL "https://gpustack-ui-1303613262.cos.accelerate.myqcloud.com/releases/${default_tag}.tar.gz" |
      tar -xzf - --directory "${tmp_ui_path}/ui" 2>/dev/null; then
      gpustack::log::fatal "failed to download '${default_tag}' ui archive"
    fi
  fi
  cp -a "${tmp_ui_path}/ui/dist/." "${ui_path}"

  rm -rf "${tmp_ui_path}"
}

# Copy extra static files to ui including catalog icons
function copy_extra_static() {
  local extra_static_path="${ROOT_DIR}/static"
  local ui_static_path="${ROOT_DIR}/gpustack/ui/static"
  if [ -d "${extra_static_path}" ]; then
    cp -a "${extra_static_path}/." "${ui_static_path}"
  fi
}

# Update community backends
function make_community_backends() {
  local target_dir="${ROOT_DIR}/gpustack/assets/"
  local cache_dir="${COMMUNITY_BACKENDS_CACHE_DIR:-${ROOT_DIR}/pack/downloads/community-inference-backends}"
  local force_update="${COMMUNITY_BACKENDS_FORCE_UPDATE:-false}"

  gpustack::log::info "pulling community backends"

  # If cache exists and force update is not requested, use cached copy
  if [[ -d "${cache_dir}/.git" ]] && [[ "${force_update}" != "true" ]]; then
    gpustack::log::info "using cached community backends from '${cache_dir}'"
    (
      cd "${cache_dir}"
      # Pull latest changes
      git pull --ff-only origin main 2>/dev/null || gpustack::log::warn "failed to update community backends cache, using existing copy"
    )
  else
    # Clone or update the repository
    if [[ -d "${cache_dir}/.git" ]]; then
      gpustack::log::info "force updating community backends cache"
      rm -rf "${cache_dir}"
    fi
    gpustack::log::info "cloning community backends to cache '${cache_dir}'"
    git clone https://github.com/gpustack/community-inference-backends "${cache_dir}"
  fi

  # Build the community backends from cache
  (
    cd "${cache_dir}"
    if [[ "${UV_SYSTEM_PYTHON:-}" == "1" ]]; then
      # In Docker build, use system Python directly
      uv pip install PyYAML && uv run make
    else
      # For local development, use virtual environment
      uv venv && source .venv/bin/activate && uv pip install PyYAML && uv run make
    fi
  )

  # Create target directory and copy the yaml file
  mkdir -p "${target_dir}"
  cp "${cache_dir}/dist/community-inference-backends.yaml" "${target_dir}/community-inference-backends.yaml"

  gpustack::log::info "community backends updated successfully"
}

#
# main
#

gpustack::log::info "+++ DEPENDENCIES +++"
download_deps
download_ui
copy_extra_static
make_community_backends
gpustack::log::info "--- DEPENDENCIES ---"
