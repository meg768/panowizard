#!/bin/zsh

set -euo pipefail

project_directory=${0:A:h:h}
app_bundle="$project_directory/build/PanoWizard.app"
local_distribution=false

usage() {
    cat <<'EOF'
Usage: ./Scripts/build-distribution.sh [--local]

Creates a PanoWizard DMG from build/PanoWizard.app.

Production mode requires:
  PANOWIZARD_SIGN_IDENTITY  Developer ID Application identity or SHA-1 hash
  PANOWIZARD_NOTARY_PROFILE notarytool keychain profile name

Use --local to create an explicitly unnotarized development DMG.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --local)
            local_distribution=true
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if [[ ! -d "$app_bundle" ]]; then
    echo "Missing $app_bundle" >&2
    echo "Run ./Scripts/build-app.sh first." >&2
    exit 1
fi

sign_identity=${PANOWIZARD_SIGN_IDENTITY:-}
notary_profile=${PANOWIZARD_NOTARY_PROFILE:-}
if [[ "$local_distribution" != true ]]; then
    if [[ -z "$sign_identity" || -z "$notary_profile" ]]; then
        echo "Production distribution requires both signing variables." >&2
        usage >&2
        exit 1
    fi
    if ! security find-identity -v -p codesigning \
        | grep -Fq "$sign_identity"; then
        echo "Signing identity not found: $sign_identity" >&2
        exit 1
    fi
fi

version=$(/usr/libexec/PlistBuddy \
    -c 'Print :CFBundleShortVersionString' \
    "$app_bundle/Contents/Info.plist")
architecture=$(lipo -archs "$app_bundle/Contents/MacOS/PanoWizard" \
    | tr ' ' '-')
distribution_name="PanoWizard-$version-$architecture"
output_dmg="$project_directory/build/$distribution_name.dmg"
output_checksum="$output_dmg.sha256"
staging_directory=$(mktemp -d "${TMPDIR:-/tmp}/PanoWizard-distribution.XXXXXX")
staging_app="$staging_directory/PanoWizard.app"
disk_root="$staging_directory/disk"
staging_dmg="$staging_directory/$distribution_name.dmg"

cleanup() {
    rm -rf "$staging_directory"
}
trap cleanup EXIT

mkdir -p "$disk_root"
ditto --norsrc --noextattr "$app_bundle" "$staging_app"
xattr -cr "$staging_app"

if [[ "$local_distribution" == true ]]; then
    codesign --force --deep --sign - --timestamp=none "$staging_app"
else
    for library in "$staging_app"/Contents/Frameworks/*.dylib; do
        codesign --force \
            --sign "$sign_identity" \
            --options runtime \
            --timestamp \
            "$library"
    done
    codesign --force \
        --sign "$sign_identity" \
        --options runtime \
        --timestamp \
        "$staging_app"
fi
codesign --verify --deep --strict --verbose=2 "$staging_app"

ditto --norsrc --noextattr "$staging_app" "$disk_root/PanoWizard.app"
ln -s /Applications "$disk_root/Applications"
hdiutil create \
    -volname "PanoWizard $version" \
    -srcfolder "$disk_root" \
    -format UDZO \
    -ov \
    "$staging_dmg"
hdiutil verify "$staging_dmg"

if [[ "$local_distribution" != true ]]; then
    codesign --force \
        --sign "$sign_identity" \
        --timestamp \
        "$staging_dmg"
    xcrun notarytool submit "$staging_dmg" \
        --keychain-profile "$notary_profile" \
        --wait
    xcrun stapler staple "$staging_dmg"
    xcrun stapler validate "$staging_dmg"
    spctl --assess \
        --type open \
        --context context:primary-signature \
        --verbose=2 \
        "$staging_dmg"
fi

install -m 644 "$staging_dmg" "$output_dmg"
(
    cd "${output_dmg:h}"
    shasum -a 256 "${output_dmg:t}" > "${output_checksum:t}"
)

if [[ "$local_distribution" == true ]]; then
    echo "Created local, unnotarized distribution:"
else
    echo "Created signed and notarized distribution:"
fi
echo "$output_dmg"
echo "$output_checksum"
