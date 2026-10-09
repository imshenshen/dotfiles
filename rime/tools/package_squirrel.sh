#!/usr/bin/env bash
# Package a signed app with precompiled data; avoid changing signed resources at install time.
set -euo pipefail

dotfiles_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_dir="${dotfiles_root}/rime/.build/squirrel"
app_dir="${source_dir}/build/Build/Products/Release/Squirrel.app"
package_dir="${source_dir}/package"
scripts_dir="${dotfiles_root}/rime/.build/install-scripts"
[[ -f "${app_dir}/Contents/SharedSupport/build/default.yaml" ]] || {
    echo 'Precompile the shared Rime data before packaging' >&2
    exit 1
}
codesign --verify --deep --strict "${app_dir}"
mkdir -p "${scripts_dir}"
{
    printf '#!/bin/bash\nexport RIME_NO_PREBUILD=1\n'
    tail -n +2 "${source_dir}/scripts/postinstall"
} > "${scripts_dir}/postinstall"
chmod +x "${scripts_dir}/postinstall"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${app_dir}/Contents/Info.plist")"
pkgbuild --root "${source_dir}/build/Build/Products/Release" \
    --filter '.*\.swiftmodule$' \
    --component-plist "${package_dir}/Squirrel-component.plist" \
    --identifier im.rime.inputmethod.Squirrel --version "${version}" \
    --install-location '/Library/Input Methods' --scripts "${scripts_dir}" \
    "${package_dir}/Squirrel-component.pkg"
sed "s/@VERSION@/${version}/" "${package_dir}/Distribution" > "${scripts_dir}/Distribution.xml"
productbuild --distribution "${scripts_dir}/Distribution.xml" \
    --package-path "${package_dir}" --resources "${package_dir}" \
    "${package_dir}/Squirrel.pkg"
rm "${package_dir}/Squirrel-component.pkg"
