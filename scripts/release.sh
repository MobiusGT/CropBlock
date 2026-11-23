#!/bin/zsh
# Builds a Universal Binary (arm64 + x86_64) CropBlock.app and packages a versioned
# GitHub Releases DMG + SHA-256 checksum in dist/.
#
# Default mode (no Apple Developer account required):
#   ./scripts/release.sh
#   -> Ad-hoc signs CropBlock.app and outputs:
#      dist/CropBlock-<version>-universal.dmg
#      dist/CropBlock-<version>-universal.dmg.sha256
#
# Optional environment variables:
#   VERSION=0.1.0                   Override version (defaults to CFBundleShortVersionString in Info.plist.in)
#   BUNDLE_HELPERS_DIR=/path/dir    Bundle self-contained ffmpeg, ffprobe, mkvpropedit into Contents/Helpers/
#   DEVELOPER_ID="Developer ID..."  Sign with Hardened Runtime (--options runtime --timestamp) instead of ad-hoc
#   NOTARY_PROFILE="cropblock"      Submit signed DMG to Apple notarytool and staple (requires DEVELOPER_ID)
set -euo pipefail

here=${0:A:h:h}
name="CropBlock"
dist_dir="$here/dist"
scratch="$HOME/Library/Developer/$name/release-build"

version="${VERSION:-}"
if [[ -z "$version" ]]; then
  version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$here/Info.plist.in")
fi

build_number="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
dmg_name="${name}-${version}-universal.dmg"
dmg_path="$dist_dir/$dmg_name"
sha_path="${dmg_path}.sha256"
app_path="$dist_dir/${name}.app"
staging_dir=$(mktemp -d)
trap 'rm -rf "$staging_dir"' EXIT

echo "==> Building Universal Binary (arm64 + x86_64) for ${name} ${version}..."
swift build -c release --arch arm64 --arch x86_64 \
  --package-path "$here" \
  --scratch-path "$scratch"

bin_dir=$(swift build -c release --arch arm64 --arch x86_64 \
  --package-path "$here" \
  --scratch-path "$scratch" \
  --show-bin-path)
bin="$bin_dir/$name"
[[ -x "$bin" ]] || { echo "error: universal binary not found at $bin"; exit 1; }

archs=$(lipo -info "$bin")
echo "==> Binary architectures: $archs"
[[ "$archs" == *"arm64"* && "$archs" == *"x86_64"* ]] || {
  echo "error: expected universal binary containing both arm64 and x86_64"
  exit 1
}

echo "==> Assembling ${name}.app bundle..."
mkdir -p "$dist_dir"
rm -rf "$app_path" "$dmg_path" "$sha_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin" "$app_path/Contents/MacOS/$name"

sed -e "s/__BUILD__/${build_number}/" "$here/Info.plist.in" > "$app_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app_path/Contents/Info.plist"

if [[ -d "$here/Icon/AppIcon.icon" ]]; then
  car="$here/Resources/Assets.car"
  if [[ ! -f "$car" || -n "$(find "$here/Icon/AppIcon.icon" -newer "$car" | head -1)" ]]; then
    "$here/tools/make_icon.sh"
  fi
  cp -X "$car" "$here/Resources/AppIcon.icns" "$app_path/Contents/Resources/"
fi

# Optional self-contained helper binaries (Contents/Helpers/)
if [[ -n "${BUNDLE_HELPERS_DIR:-}" ]]; then
  [[ -d "$BUNDLE_HELPERS_DIR" ]] || { echo "error: BUNDLE_HELPERS_DIR not found: $BUNDLE_HELPERS_DIR"; exit 1; }
  mkdir -p "$app_path/Contents/Helpers"
  for tool in ffmpeg ffprobe mkvpropedit; do
    if [[ -x "$BUNDLE_HELPERS_DIR/$tool" ]]; then
      cp -X "$BUNDLE_HELPERS_DIR/$tool" "$app_path/Contents/Helpers/$tool"
      chmod +x "$app_path/Contents/Helpers/$tool"
    fi
  done
  for lib in "$BUNDLE_HELPERS_DIR"/*.dylib(N); do
    cp -X "$lib" "$app_path/Contents/Helpers/"
  done
fi

xattr -cr "$app_path"

# Signing: ad-hoc by default, Hardened Runtime when DEVELOPER_ID is provided.
sign_binary() {
  local target="$1"
  if [[ -n "${DEVELOPER_ID:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$target"
  else
    codesign --force --sign - "$target"
  fi
}

if [[ -d "$app_path/Contents/Helpers" ]]; then
  echo "==> Signing bundled helpers..."
  for helper in "$app_path/Contents/Helpers"/*(N); do
    sign_binary "$helper"
  done
fi

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  echo "==> Signing ${name}.app with Developer ID (Hardened Runtime)..."
else
  echo "==> Ad-hoc signing ${name}.app (no Apple Developer account required)..."
fi
sign_binary "$app_path"
codesign --verify --deep --strict "$app_path"

echo "==> Creating DMG: $dmg_path"
cp -R "$app_path" "$staging_dir/${name}.app"
ln -s /Applications "$staging_dir/Applications"

hdiutil create \
  -volname "Crop Block" \
  -srcfolder "$staging_dir" \
  -ov \
  -format UDZO \
  "$dmg_path"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  echo "==> Signing DMG with Developer ID..."
  codesign --force --timestamp --sign "$DEVELOPER_ID" "$dmg_path"
fi

if [[ -n "${DEVELOPER_ID:-}" && -n "${NOTARY_PROFILE:-}" ]]; then
  echo "==> Submitting DMG for Apple notarization (profile: $NOTARY_PROFILE)..."
  xcrun notarytool submit "$dmg_path" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "==> Stapling notarization ticket..."
  xcrun stapler staple "$dmg_path"
fi

echo "==> Verifying DMG integrity..."
verified=0
for attempt in 1 2 3; do
  sleep 1
  if hdiutil verify "$dmg_path"; then
    verified=1
    break
  fi
  echo "  retrying hdiutil verify ($attempt/3)..."
done
[[ "$verified" == 1 ]] || { echo "error: hdiutil verify failed"; exit 1; }

echo "==> Generating SHA-256 checksum..."
(cd "$dist_dir" && shasum -a 256 "$dmg_name" > "$(basename "$sha_path")")
(cd "$dist_dir" && shasum -a 256 -c "$(basename "$sha_path")")

echo ""
echo "Release artifacts ready:"
echo "  App:      $app_path"
echo "  DMG:      $dmg_path"
echo "  SHA-256:  $sha_path"
cat "$sha_path"
