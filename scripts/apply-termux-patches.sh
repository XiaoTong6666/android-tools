#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PATCH_ROOT="${ROOT_DIR}/patches/local-build"

apply_submodule_patch() {
    local submodule_path=$1
    local patch_path=$2
    local strip_components=$3

    if git -C "${ROOT_DIR}/${submodule_path}" apply --check "-p${strip_components}" "${patch_path}" >/dev/null 2>&1; then
        git -C "${ROOT_DIR}/${submodule_path}" apply "-p${strip_components}" "${patch_path}"
        return
    fi

    if git -C "${ROOT_DIR}/${submodule_path}" apply -R --check "-p${strip_components}" "${patch_path}" >/dev/null 2>&1; then
        printf 'Skipping %s: already applied\n' "${patch_path}"
        return
    fi

    printf 'Failed to apply %s to %s\n' "${patch_path}" "${submodule_path}" >&2
    return 1
}

require_repo_paths() {
    local repo_dir=$1
    shift

    local path
    for path in "$@"; do
        if [[ ! -e "${ROOT_DIR}/${repo_dir}/${path}" ]]; then
            printf 'Expected patched path is missing in %s: %s\n' "${repo_dir}" "${path}" >&2
            exit 1
        fi
    done
}

"${ROOT_DIR}/scripts/apply-vendor-patches.sh"
git -C "${ROOT_DIR}" submodule update --init vendor/libbase vendor/libziparchive vendor/logging

apply_submodule_patch vendor/adb "${PATCH_ROOT}/vendor-adb/0001-termux-adb-tcp-only.patch" 1
apply_submodule_patch vendor/adb "${PATCH_ROOT}/termux/vendor_adb_sysdeps.h.patch" 3
require_repo_paths vendor/adb \
    "client/adb_wifi_termux_stub.cpp" \
    "client/usb_termux_stub.cpp" \
    "client/fastdeploy_termux_stub.cpp" \
    "client/mdns_disabled.cpp" \
    "client/termux_adb.h"

apply_submodule_patch vendor/core "${PATCH_ROOT}/vendor-core/0001-guard-fdsan-for-api-29.patch" 1
apply_submodule_patch vendor/libbase "${PATCH_ROOT}/vendor-libbase/0001-guard-fdsan-for-api-29.patch" 1
apply_submodule_patch vendor/libziparchive "${PATCH_ROOT}/vendor-libziparchive/0001-guard-fdsan-for-api-29.patch" 1
apply_submodule_patch vendor/logging "${PATCH_ROOT}/vendor-logging/0001-lower-liblog-api-gates.patch" 1
apply_submodule_patch vendor/logging "${PATCH_ROOT}/vendor-logging/0002-disable-android-logd-backend.patch" 1
