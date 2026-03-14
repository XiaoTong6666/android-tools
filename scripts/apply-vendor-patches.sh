#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

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

reset_submodule_to_head() {
    local submodule_path=$1

    git -C "${ROOT_DIR}/${submodule_path}" reset --hard HEAD >/dev/null
    git -C "${ROOT_DIR}/${submodule_path}" clean -fd >/dev/null
}

git -C "${ROOT_DIR}" submodule update --init vendor/adb vendor/core

reset_submodule_to_head vendor/adb
reset_submodule_to_head vendor/core

apply_submodule_patch vendor/adb "${ROOT_DIR}/patches/adb/1000-termux-adb.patch" 3
apply_submodule_patch vendor/adb "${ROOT_DIR}/patches/adb/1001-add-mdns-disabled-stub.patch" 3
apply_submodule_patch vendor/adb "${ROOT_DIR}/patches/adb/1002-gate-openscreen-header-when-mdns-disabled.patch" 3
apply_submodule_patch vendor/adb "${ROOT_DIR}/patches/adb/1003-add-explicit-mdns-std-includes.patch" 3
apply_submodule_patch vendor/adb "${ROOT_DIR}/patches/adb/1004-drop-block-standard-layout-assert.patch" 3
apply_submodule_patch vendor/adb "${ROOT_DIR}/patches/adb/1005-avoid-internal-sys-cdefs-header.patch" 3
apply_submodule_patch vendor/core "${ROOT_DIR}/patches/core/1000-termux-fastboot.patch" 3
