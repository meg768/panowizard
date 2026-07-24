#!/bin/zsh

set -euo pipefail

project_directory=${0:A:h:h}
cache_directory="$project_directory/.vendor-cache/hugin"
disk_image="$cache_directory/Hugin-2019.2.0.dmg"
install_directory="$project_directory/Vendor/Hugin"
mount_point="/Volumes/Hugin-2019.2.0"

mkdir -p "$cache_directory" "$install_directory/MacOS" "$install_directory/Libraries"

if [[ ! -f "$disk_image" ]]; then
    curl \
        --location \
        --fail \
        --silent \
        --show-error \
        "https://downloads.sourceforge.net/hugin/Hugin-2019.2.0.dmg" \
        --output "$disk_image"
fi

if [[ ! -d "$mount_point" ]]; then
    hdiutil attach "$disk_image" -nobrowse -readonly
fi

hugin_contents="$mount_point/Hugin/Hugin.app/Contents"
stitch_contents="$mount_point/Hugin/HuginStitchProject.app/Contents"

ditto "$hugin_contents/Libraries" "$install_directory/Libraries"
ditto "$stitch_contents/Libraries" "$install_directory/Libraries"

for tool in pto_gen cpfind cpclean autooptimiser pano_modify; do
    install -m 755 \
        "$hugin_contents/MacOS/$tool" \
        "$install_directory/MacOS/$tool"
done

install -m 755 \
    "$stitch_contents/MacOS/nona" \
    "$install_directory/MacOS/nona"
install -m 755 \
    "$stitch_contents/MacOS/enblend" \
    "$install_directory/MacOS/enblend"

hdiutil detach "$mount_point"
