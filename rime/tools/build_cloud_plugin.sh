#!/usr/bin/env bash
# Build against the exact librime source and Boost headers used by the app.
set -euo pipefail
dotfiles_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="${dotfiles_root}/rime/.build"
source_dir="${build_dir}/squirrel"
boost_archive="${build_dir}/boost-1.89.0-cmake.tar.gz"
boost_source="${build_dir}/boost-1.89.0"
boost_include="${build_dir}/boost-include"
boost_sha='954a01219bf818c7fb850fa610c2c8c71a4fa28fa32a1900056bcb6ff58cf908'
if [[ ! -f "${boost_archive}" ]]; then
    curl -fL --retry 2 --connect-timeout 10 \
        -o "${boost_archive}.partial" \
        'https://github.com/boostorg/boost/releases/download/boost-1.89.0/boost-1.89.0-cmake.tar.gz'
    mv "${boost_archive}.partial" "${boost_archive}"
fi
printf '%s  %s\n' "${boost_sha}" "${boost_archive}" | shasum -a 256 -c
if [[ ! -d "${boost_source}" ]]; then tar -xzf "${boost_archive}" -C "${build_dir}"; fi
if [[ ! -f "${boost_include}/boost/version.hpp" ]]; then
    mkdir -p "${boost_include}"
    while IFS= read -r include_dir; do
        if [[ -d "${include_dir}/boost" ]]; then
            ditto "${include_dir}/boost" "${boost_include}/boost"
        fi
    done < <(find "${boost_source}/libs" -type d -name include)
fi
plugin_build="${build_dir}/cloud-pinyin"
mkdir -p "${plugin_build}/include/rime"
printf '#pragma once\n' > "${plugin_build}/include/rime/build_config.h"
output="${plugin_build}/librime-cloud-pinyin.dylib"
compiler_args=(
    -std=c++17 -O2 -fobjc-arc -fblocks -dynamiclib
    -arch arm64 -arch x86_64 -mmacosx-version-min=13.0
)
if [[ "${RIME_CLOUD_TESTING:-0}" == 1 ]]; then
    compiler_args+=(-DRIME_CLOUD_TESTING)
    output="${plugin_build}/librime-cloud-pinyin-test.dylib"
fi
xcrun clang++ "${compiler_args[@]}" \
    -I"${plugin_build}/include" -I"${boost_include}" \
    -I"${source_dir}/librime/src" -I"${source_dir}/download/include" \
    "${dotfiles_root}/rime/native/cloud_pinyin/cloud_pinyin.mm" \
    -L"${source_dir}/librime/dist/lib" -lrime -framework Foundation \
    -Wl,-rpath,@loader_path/.. \
    -install_name '@rpath/rime-plugins/librime-cloud-pinyin.dylib' \
    -o "${output}"
codesign --force --sign - "${output}"
printf 'Cloud plugin: %s\n' "${output}"
