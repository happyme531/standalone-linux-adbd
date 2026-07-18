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

# NFS and container bind mounts often expose the checkout with a different
# numeric owner. Scope Git's ownership exceptions to this script process and
# only to the repositories that the build is expected to touch.
git_safe_directories=("${repo_dir}")
for path in "${required_submodules[@]}"; do
    git_safe_directories+=("${repo_dir}/${path}")
done
export GIT_CONFIG_COUNT=${#git_safe_directories[@]}
for index in "${!git_safe_directories[@]}"; do
    export "GIT_CONFIG_KEY_${index}=safe.directory"
    export "GIT_CONFIG_VALUE_${index}=${git_safe_directories[$index]}"
done

missing_submodules=()
for path in "${required_submodules[@]}"; do
    if ! git -C "${repo_dir}/${path}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        missing_submodules+=("${path}")
    fi
done
if (( ${#missing_submodules[@]} != 0 )); then
    git -C "${repo_dir}" submodule update --init --depth 1 "${missing_submodules[@]}"
fi

# CMake applies each patch series with git-am. Detect a prepared checkout from
# the resulting source content, not from commit subjects or generated hashes.
patch_state_specs=(
    "vendor/adb:patches/adb/0030-adb-enable-FunctionFS-USB-on-standalone-Linux.patch"
    "vendor/core:patches/core/0012-Add-explicit-import-for-algorithm.patch"
    "vendor/libbase:patches/libbase/0007-Include-missing-cstdint-header.patch"
    "vendor/logging:patches/logging/0001-Don-t-use-the-internal-glibc-header-sys-cdefs.h.patch"
)
prepared_submodules=0
unprepared_submodules=0
for spec in "${patch_state_specs[@]}"; do
    submodule=${spec%%:*}
    patch=${spec#*:}
    if git -C "${repo_dir}/${submodule}" apply --reverse --check \
            "${repo_dir}/${patch}" >/dev/null 2>&1; then
        ((prepared_submodules += 1))
        continue
    fi

    if ! git -C "${repo_dir}/${submodule}" diff --quiet ||
            ! git -C "${repo_dir}/${submodule}" diff --cached --quiet; then
        printf 'Refusing to patch modified submodule: %s\n' "${submodule}" >&2
        exit 1
    fi

    expected_head=$(git -C "${repo_dir}" rev-parse "HEAD:${submodule}")
    actual_head=$(git -C "${repo_dir}/${submodule}" rev-parse HEAD)
    if [[ "${actual_head}" != "${expected_head}" ]]; then
        printf 'Submodule is neither at its recorded base nor fully patched: %s\n' \
            "${submodule}" >&2
        exit 1
    fi
    ((unprepared_submodules += 1))
done

if (( prepared_submodules != 0 && unprepared_submodules != 0 )); then
    printf 'Vendored submodules are only partially patched; use a consistent checkout.\n' >&2
    exit 1
fi

if (( prepared_submodules != 0 )); then
    patch_vendor=OFF
else
    patch_vendor=ON
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
    -DANDROID_TOOLS_ADBD_USB="${ANDROID_TOOLS_ADBD_USB:-ON}"
)

if [[ -n "${CMAKE_TOOLCHAIN_FILE:-}" ]]; then
    cmake_args+=("-DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}")
fi

cmake "${cmake_args[@]}"
cmake --build "${build_dir}" --target adbd -j "${ANDROID_TOOLS_BUILD_JOBS:-$(nproc)}"

printf 'Built %s\n' "${build_dir}/vendor/adbd"
