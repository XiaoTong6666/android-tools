#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

apply_submodule_patch() {
    local submodule_path=$1
    local patch_path=$2
    local strip_components=$3

    if git -C "${ROOT_DIR}/${submodule_path}" apply --check "-p${strip_components}" "${ROOT_DIR}/${patch_path}" >/dev/null 2>&1; then
        git -C "${ROOT_DIR}/${submodule_path}" apply -3 --index "-p${strip_components}" "${ROOT_DIR}/${patch_path}"
        return
    fi

    if git -C "${ROOT_DIR}/${submodule_path}" apply -R --check "-p${strip_components}" "${ROOT_DIR}/${patch_path}" >/dev/null 2>&1; then
        printf 'Skipping %s: already applied\n' "${patch_path}"
        return
    fi

    printf 'Failed to apply %s to %s\n' "${patch_path}" "${submodule_path}" >&2
    return 1
}

git -C "${ROOT_DIR}" submodule update --init vendor/adb vendor/core

apply_submodule_patch vendor/adb patches/vendor-adb/fb3e081c-termux-adb.patch 3
apply_submodule_patch vendor/core patches/vendor-core/fb3e081c-termux-fastboot.patch 3
