#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
build_dir=${1:-"${repo_dir}/build/linux-adbd"}

required_submodules=(
    vendor/adb
    vendor/core
    vendor/fmtlib
    vendor/libbase
    vendor/logging
    vendor/third_party/brotli
    vendor/third_party/lz4
    vendor/third_party/zstd
)

missing_submodules=()
for path in "${required_submodules[@]}"; do
    if ! git -C "${repo_dir}/${path}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        missing_submodules+=("${path}")
    fi
done
if (( ${#missing_submodules[@]} != 0 )); then
    git -C "${repo_dir}" submodule update --init --depth 1 "${missing_submodules[@]}"
fi

# CMake applies the patch series by creating commits in the AOSP submodules.
# Skip that step on subsequent builds from the same prepared checkout.
patch_vendor=ON
adb_head_subject=$(git -C "${repo_dir}/vendor/adb" log -1 --format=%s)
if [[ "${adb_head_subject}" == "adb: add Linux TCP-only daemon support" ]]; then
    patch_vendor=OFF
fi

cmake_args=(
    -S "${repo_dir}"
    -B "${build_dir}"
    -G Ninja
    -DCMAKE_BUILD_TYPE=Release
    -DANDROID_TOOLS_PATCH_VENDOR="${patch_vendor}"
    -DANDROID_TOOLS_USE_BUNDLED_FMT=ON
    -DANDROID_TOOLS_BUILD_ADBD_ONLY=ON
    -DANDROID_TOOLS_ADBD_FULLY_STATIC=ON
)

if [[ -n "${CMAKE_TOOLCHAIN_FILE:-}" ]]; then
    cmake_args+=("-DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}")
fi

cmake "${cmake_args[@]}"
cmake --build "${build_dir}" --target adbd -j "${ANDROID_TOOLS_BUILD_JOBS:-$(nproc)}"

printf 'Built %s\n' "${build_dir}/vendor/adbd"
