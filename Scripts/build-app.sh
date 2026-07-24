#!/bin/zsh

set -euo pipefail

project_directory=${0:A:h:h}
app_bundle="$project_directory/build/PanoWizard.app"
staging_directory=$(mktemp -d "${TMPDIR:-/tmp}/PanoWizard-build.XXXXXX")
staging_app_bundle="$staging_directory/PanoWizard.app"
contents_directory="$staging_app_bundle/Contents"
macos_directory="$contents_directory/MacOS"
frameworks_directory="$contents_directory/Frameworks"

cleanup() {
    rm -rf "$staging_directory"
}
trap cleanup EXIT

cd "$project_directory"

if [[ ! -f "$project_directory/Vendor/OpenCV/lib/libopencv_stitching.500.dylib" ]]; then
    "$project_directory/Scripts/build-opencv.sh"
fi

if [[ ! -x "$project_directory/Vendor/Hugin/MacOS/cpfind" ]]; then
    "$project_directory/Scripts/build-hugin-tools.sh"
fi

swift build --configuration release --arch arm64

resources_directory="$contents_directory/Resources"
mkdir -p "$macos_directory" "$frameworks_directory" "$resources_directory"
install -m 755 \
    "$project_directory/.build/arm64-apple-macosx/release/PanoWizard" \
    "$macos_directory/PanoWizard"
install -m 644 \
    "$project_directory/Resources/Info.plist" \
    "$contents_directory/Info.plist"

for library in "$project_directory"/Vendor/OpenCV/lib/*.500.dylib; do
    install -m 755 "$library" "$frameworks_directory/${library:t}"
done

ditto \
    "$project_directory/Vendor/Hugin" \
    "$resources_directory/Hugin"

xattr -cr "$staging_app_bundle"
codesign --force --deep --sign - --timestamp=none "$staging_app_bundle"
codesign --verify --deep --strict "$staging_app_bundle"

if [[ -d "$app_bundle" ]]; then
    rm -rf "$app_bundle"
fi
mkdir -p "${app_bundle:h}"
ditto --norsrc --noextattr "$staging_app_bundle" "$app_bundle"
xattr -cr "$app_bundle"

echo "$app_bundle"
