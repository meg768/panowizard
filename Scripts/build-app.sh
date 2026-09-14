#!/bin/zsh

set -euo pipefail

project_directory=${0:A:h:h}
app_bundle="$project_directory/build/PanoWizard.app"
info_plist="$project_directory/Resources/Info.plist"
version_file="$project_directory/VERSION"
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

current_version=$(<"$version_file")
if [[ ! "$current_version" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "Appversionen måste ha formatet major.minor: $current_version" >&2
    exit 1
fi
version_major=${current_version%%.*}
version_minor=${current_version##*.}
next_version="$version_major.$((version_minor + 1))"
print -r -- "$next_version" > "$version_file"

echo "Bygger PanoWizard $next_version"
swift build --configuration release --arch arm64

resources_directory="$contents_directory/Resources"
mkdir -p "$macos_directory" "$frameworks_directory" "$resources_directory"
install -m 755 \
    "$project_directory/.build/arm64-apple-macosx/release/PanoWizard" \
    "$macos_directory/PanoWizard"
install -m 644 \
    "$info_plist" \
    "$contents_directory/Info.plist"
/usr/libexec/PlistBuddy -c \
    "Set :CFBundleShortVersionString $next_version" \
    "$contents_directory/Info.plist"
/usr/libexec/PlistBuddy -c \
    "Set :CFBundleVersion $next_version" \
    "$contents_directory/Info.plist"
build_timestamp=$(date '+%Y-%m-%d %H:%M')
/usr/libexec/PlistBuddy -c \
    "Add :NSHumanReadableCopyright string Byggd $build_timestamp" \
    "$contents_directory/Info.plist"
install -m 644 \
    "$project_directory/Resources/Icons/PanoWizardProject.icns" \
    "$resources_directory/PanoWizardProject.icns"
install -m 644 \
    "$project_directory/Resources/Icons/PanoWizardApp.icns" \
    "$resources_directory/PanoWizardApp.icns"

resource_bundle="$project_directory/.build/arm64-apple-macosx/release/PanoWizard_PanoWizard.bundle"
if [[ -d "$resource_bundle" ]]; then
    ditto "$resource_bundle" "$resources_directory/PanoWizard_PanoWizard.bundle"
fi

for library in "$project_directory"/Vendor/OpenCV/lib/*.500.dylib; do
    install -m 755 "$library" "$frameworks_directory/${library:t}"
done

xattr -cr "$staging_app_bundle"
codesign --force --deep --sign - --timestamp=none "$staging_app_bundle"
codesign --verify --deep --strict "$staging_app_bundle"

if [[ -d "$app_bundle" ]]; then
    rm -rf "$app_bundle"
fi
mkdir -p "${app_bundle:h}"
ditto --norsrc --noextattr "$staging_app_bundle" "$app_bundle"

verified=false
for attempt in {1..40}; do
    xattr -cr "$app_bundle"
    find "$app_bundle" -exec xattr -d com.apple.FinderInfo {} + \
        2>/dev/null || true
    codesign --force --deep --sign - --timestamp=none "$app_bundle"
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
