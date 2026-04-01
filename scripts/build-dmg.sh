#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <release-tag>" >&2
  exit 1
fi

release_tag="$1"
version="${release_tag#v}"
arch="$(uname -m)"
repo_root="$(pwd)"
derived_data_path="${repo_root}/.build/xcode-release"
dist_dir="${repo_root}/dist"
bundle_dir="${dist_dir}/Pub.app"
staging_dir="${dist_dir}/dmg-root"
dmg_name="Pub-${version}-macos-${arch}.dmg"
dmg_path="${dist_dir}/${dmg_name}"
checksum_path="${dmg_path}.sha256"

rm -rf "${derived_data_path}" "${bundle_dir}" "${staging_dir}" "${dmg_path}" "${checksum_path}"
mkdir -p "${bundle_dir}/Contents/MacOS" "${staging_dir}"

xcodebuild \
  -scheme Pub \
  -configuration Release \
  -destination "platform=macOS,arch=${arch}" \
  -derivedDataPath "${derived_data_path}" \
  CODE_SIGNING_ALLOWED=NO \
  build

cp "${derived_data_path}/Build/Products/Release/Pub" "${bundle_dir}/Contents/MacOS/Pub"
chmod 755 "${bundle_dir}/Contents/MacOS/Pub"

cat > "${bundle_dir}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>Pub</string>
  <key>CFBundleIdentifier</key>
  <string>io.github.cengle.pub</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Pub</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${version}</string>
  <key>CFBundleVersion</key>
  <string>${version}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

printf 'APPL????' > "${bundle_dir}/Contents/PkgInfo"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "${bundle_dir}"
fi

cp -R "${bundle_dir}" "${staging_dir}/Pub.app"
ln -s /Applications "${staging_dir}/Applications"
cp README.md "${staging_dir}/README.md"

hdiutil create \
  -volname "Pub" \
  -srcfolder "${staging_dir}" \
  -ov \
  -format UDZO \
  "${dmg_path}"

(
  cd "${dist_dir}"
  shasum -a 256 "${dmg_name}" > "${dmg_name}.sha256"
)
