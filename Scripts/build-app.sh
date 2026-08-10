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

swift build --configuration release --arch arm64

resources_directory="$contents_directory/Resources"
mkdir -p "$macos_directory" "$frameworks_directory" "$resources_directory"
install -m 755 \
    "$project_directory/.build/arm64-apple-macosx/release/PanoWizard" \
    "$macos_directory/PanoWizard"
install -m 644 \
    "$project_directory/Resources/Info.plist" \
    "$contents_directory/Info.plist"
install -m 644 \
    "$project_directory/Resources/Icons/PanoWizardProject.icns" \
    "$resources_directory/PanoWizardProject.icns"
install -m 644 \
    "$project_directory/Resources/Icons/PanoWizardApp.icns" \
    "$resources_directory/PanoWizardApp.icns"

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

verified=false
for attempt in {1..5}; do
    xattr -cr "$app_bundle"
    xattr -d com.apple.FinderInfo "$app_bundle" 2>/dev/null || true
    if codesign --verify --deep --strict "$app_bundle"; then
        verified=true
        break
    fi
    sleep 0.1
done
if [[ "$verified" != true ]]; then
    echo "Apppaketets signatur kunde inte verifieras." >&2
    exit 1
fi

echo "$app_bundle"
