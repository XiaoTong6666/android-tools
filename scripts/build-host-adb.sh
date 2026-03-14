#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUILD_DIR="${ANDROID_TOOLS_BUILD_DIR:-${ROOT_DIR}/build/host-adb}"
OUTPUT_DIR="${ANDROID_TOOLS_OUTPUT_DIR:-${ROOT_DIR}/out/host/adb}"
HOST_DEPS_PREFIX="${ROOT_DIR}/build/host-deps/prefix"
HOST_DEPS_BUILD_DIR="${ROOT_DIR}/build/host-deps/build"
HOST_CMAKE_ARGS=()

resolve_deps_root() {
    local candidate

    if [[ -n "${ANDROID_TOOLS_DEPS_ROOT:-}" ]]; then
        printf '%s\n' "${ANDROID_TOOLS_DEPS_ROOT}"
        return
    fi

    for candidate in \
        "${ROOT_DIR}/third_party/android-deps" \
        "${ROOT_DIR}/android-deps" \
        "${ROOT_DIR}/../android-deps" \
        "${ROOT_DIR}/../third_party/android-deps"; do
        if [[ -d "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return
        fi
    done

    printf 'Unable to locate android-deps. Set ANDROID_TOOLS_DEPS_ROOT to the dependency root.\n' >&2
    exit 1
}

num_jobs() {
    if command -v nproc >/dev/null 2>&1; then
        nproc
        return
    fi

    if command -v getconf >/dev/null 2>&1; then
        getconf _NPROCESSORS_ONLN
        return
    fi

    if command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.ncpu
        return
    fi

    printf '4\n'
}

host_adb_binary_name() {
    case "$(uname -s)" in
        CYGWIN*|MINGW*|MSYS*)
            printf 'adb.exe\n'
            ;;
        *)
            printf 'adb\n'
            ;;
    esac
}

ensure_dir() {
    local path=$1
    local hint=$2
    if [[ ! -d "${path}" ]]; then
        printf 'Missing required source directory: %s\n%s\n' "${path}" "${hint}" >&2
        exit 1
    fi
}

find_host_tool() {
    local label=$1
    shift

    local tool
    for tool in "$@"; do
        if command -v "${tool}" >/dev/null 2>&1; then
            command -v "${tool}"
            return
        fi
    done

    printf 'Unable to locate a native %s. Install a host toolchain or override HOST_CC/HOST_CXX.\n' "${label}" >&2
    exit 1
}

run_cmake_install() {
    local source_dir=$1
    local build_dir=$2
    shift 2

    rm -rf "${build_dir}"
    cmake -S "${source_dir}" -B "${build_dir}" "${HOST_CMAKE_ARGS[@]}" "$@"
    cmake --build "${build_dir}" -j"$(num_jobs)"
    cmake --build "${build_dir}" --target install -j"$(num_jobs)"
}

DEPS_ROOT=$(resolve_deps_root)
ABSL_SRC="${DEPS_ROOT}/abseil-cpp"
PROTOBUF_SRC="${DEPS_ROOT}/protobuf"
BROTLI_SRC="${DEPS_ROOT}/brotli"
LZ4_SRC="${DEPS_ROOT}/lz4"
ZSTD_SRC="${DEPS_ROOT}/zstd"
ADB_BIN_NAME=$(host_adb_binary_name)
HOST_CC=${HOST_CC:-$(find_host_tool "C compiler" clang cc gcc)}
HOST_CXX=${HOST_CXX:-$(find_host_tool "C++ compiler" clang++ c++ g++)}
HOST_AR=${HOST_AR:-$(find_host_tool "archiver" ar llvm-ar)}
HOST_RANLIB=${HOST_RANLIB:-$(find_host_tool "ranlib" ranlib llvm-ranlib)}

HOST_CMAKE_ARGS=(
    -DCMAKE_C_COMPILER="${HOST_CC}"
    -DCMAKE_CXX_COMPILER="${HOST_CXX}"
    -DCMAKE_AR="${HOST_AR}"
    -DCMAKE_RANLIB="${HOST_RANLIB}"
)

ensure_dir "${ABSL_SRC}" "Clone it with: git clone --depth=1 --branch 20250127.0 https://github.com/abseil/abseil-cpp.git ${ABSL_SRC}"
ensure_dir "${PROTOBUF_SRC}" "Clone it under ${DEPS_ROOT}"
ensure_dir "${BROTLI_SRC}" "Clone it under ${DEPS_ROOT}"
ensure_dir "${LZ4_SRC}" "Clone it under ${DEPS_ROOT}"
ensure_dir "${ZSTD_SRC}" "Clone it under ${DEPS_ROOT}"

cleanup_vendor_submodules() {
    local repo_dir

    for repo_dir in "${ROOT_DIR}/vendor/adb"; do
        git -C "${repo_dir}" reset --hard HEAD >/dev/null 2>&1 || true
        git -C "${repo_dir}" clean -fd >/dev/null 2>&1 || true
    done
}

apply_host_patch() {
    local patch_path=$1
    local strip_components=$2

    if git -C "${ROOT_DIR}/vendor/adb" apply --check "-p${strip_components}" "${patch_path}" >/dev/null 2>&1; then
        git -C "${ROOT_DIR}/vendor/adb" apply "-p${strip_components}" "${patch_path}"
        return
    fi

    if git -C "${ROOT_DIR}/vendor/adb" apply -R --check "-p${strip_components}" "${patch_path}" >/dev/null 2>&1; then
        return
    fi

    printf 'Failed to apply host adb patch: %s\n' "${patch_path}" >&2
    exit 1
}

trap cleanup_vendor_submodules EXIT

apply_host_patch "${ROOT_DIR}/patches/adb/1001-add-mdns-disabled-stub.patch" 3
apply_host_patch "${ROOT_DIR}/patches/adb/1002-gate-openscreen-header-when-mdns-disabled.patch" 3
apply_host_patch "${ROOT_DIR}/patches/adb/1003-add-explicit-mdns-std-includes.patch" 3
apply_host_patch "${ROOT_DIR}/patches/adb/1004-drop-block-standard-layout-assert.patch" 3
apply_host_patch "${ROOT_DIR}/patches/adb/0013-adb-disable-fastdeploy-support.patch" 1
apply_host_patch "${ROOT_DIR}/patches/adb/0016-adb-disable-mDNS.patch" 1
apply_host_patch "${ROOT_DIR}/patches/adb/0017-adb_wifi-remove-mDNS.patch" 1

run_cmake_install \
    "${ABSL_SRC}" \
    "${HOST_DEPS_BUILD_DIR}/absl" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${HOST_DEPS_PREFIX}" \
    -DABSL_BUILD_TESTING=OFF \
    -DABSL_PROPAGATE_CXX_STD=ON \
    -DCMAKE_CXX_STANDARD=17

run_cmake_install \
    "${BROTLI_SRC}" \
    "${HOST_DEPS_BUILD_DIR}/brotli" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${HOST_DEPS_PREFIX}" \
    -DBUILD_SHARED_LIBS=OFF \
    -DBROTLI_BUILD_TOOLS=OFF \
    -DBROTLI_DISABLE_TESTS=ON

rm -rf "${HOST_DEPS_BUILD_DIR}/lz4"
cmake \
    -S "${LZ4_SRC}/build/cmake" \
    -B "${HOST_DEPS_BUILD_DIR}/lz4" \
    "${HOST_CMAKE_ARGS[@]}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DLZ4_BUILD_CLI=OFF \
    -DLZ4_BUNDLED_MODE=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_STATIC_LIBS=ON
cmake --build "${HOST_DEPS_BUILD_DIR}/lz4" -j"$(num_jobs)"
install -Dm644 "${HOST_DEPS_BUILD_DIR}/lz4/liblz4.a" "${HOST_DEPS_PREFIX}/lib/liblz4.a"
install -Dm644 "${LZ4_SRC}/lib/lz4.h" "${HOST_DEPS_PREFIX}/include/lz4.h"
install -Dm644 "${LZ4_SRC}/lib/lz4frame.h" "${HOST_DEPS_PREFIX}/include/lz4frame.h"
install -Dm644 "${LZ4_SRC}/lib/lz4file.h" "${HOST_DEPS_PREFIX}/include/lz4file.h"
install -Dm644 "${LZ4_SRC}/lib/lz4hc.h" "${HOST_DEPS_PREFIX}/include/lz4hc.h"
mkdir -p "${HOST_DEPS_PREFIX}/lib/pkgconfig"
cat > "${HOST_DEPS_PREFIX}/lib/pkgconfig/liblz4.pc" <<EOF
prefix=${HOST_DEPS_PREFIX}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: liblz4
Description: LZ4 compression library
Version: 1.10.0
Libs: -L\${libdir} -llz4
Cflags: -I\${includedir}
EOF

run_cmake_install \
    "${ZSTD_SRC}/build/cmake" \
    "${HOST_DEPS_BUILD_DIR}/zstd" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${HOST_DEPS_PREFIX}" \
    -DZSTD_BUILD_PROGRAMS=OFF \
    -DZSTD_BUILD_TESTS=OFF \
    -DZSTD_BUILD_CONTRIB=OFF \
    -DZSTD_BUILD_SHARED=OFF \
    -DZSTD_BUILD_STATIC=ON

run_cmake_install \
    "${PROTOBUF_SRC}" \
    "${HOST_DEPS_BUILD_DIR}/protobuf" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${HOST_DEPS_PREFIX}" \
    -DCMAKE_PREFIX_PATH="${HOST_DEPS_PREFIX}" \
    -Dabsl_DIR="${HOST_DEPS_PREFIX}/lib/cmake/absl" \
    -Dprotobuf_BUILD_TESTS=OFF \
    -Dprotobuf_BUILD_CONFORMANCE=OFF \
    -Dprotobuf_BUILD_EXAMPLES=OFF \
    -Dprotobuf_BUILD_SHARED_LIBS=OFF \
    -Dprotobuf_LOCAL_DEPENDENCIES_ONLY=ON

export PKG_CONFIG_DIR=
export PKG_CONFIG_LIBDIR="${HOST_DEPS_PREFIX}/lib/pkgconfig:${HOST_DEPS_PREFIX}/share/pkgconfig"
export PKG_CONFIG_PATH="${PKG_CONFIG_LIBDIR}"

rm -rf "${BUILD_DIR}"
cmake \
    -S "${ROOT_DIR}" \
    -B "${BUILD_DIR}" \
    "${HOST_CMAKE_ARGS[@]}" \
    -DANDROID_TOOLS_PATCH_VENDOR=OFF \
    -DANDROID_TOOLS_USE_BUNDLED_FMT=ON \
    -DANDROID_TOOLS_USE_BUNDLED_LIBUSB=ON \
    -DANDROID_TOOLS_BUILD_ONLY_ADB=ON \
    -DCMAKE_PREFIX_PATH="${HOST_DEPS_PREFIX}" \
    -Dabsl_DIR="${HOST_DEPS_PREFIX}/lib/cmake/absl" \
    -DProtobuf_DIR="${HOST_DEPS_PREFIX}/lib/cmake/protobuf" \
    -DProtobuf_PROTOC_EXECUTABLE="${HOST_DEPS_PREFIX}/bin/protoc"

cmake --build "${BUILD_DIR}" --target adb -j"$(num_jobs)"

install -Dm755 "${BUILD_DIR}/vendor/${ADB_BIN_NAME}" "${OUTPUT_DIR}/${ADB_BIN_NAME}"
printf 'Staged host adb: %s\n' "${OUTPUT_DIR}/${ADB_BIN_NAME}"
