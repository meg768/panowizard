#!/bin/zsh

set -euo pipefail

repo_directory=${0:A:h:h}
tools_directory="$repo_directory/Vendor/Hugin/MacOS"
libraries_directory="$repo_directory/Vendor/Hugin/Libraries"
input_directory="/Users/magnus/Desktop/Lundalogik"
ring_directory="$repo_directory/Experiments/output/lundalogik-band"
output_directory="$repo_directory/Experiments/output/lundalogik-full"

export DYLD_LIBRARY_PATH="$libraries_directory"
export OMP_NUM_THREADS=1

"$repo_directory/Experiments/stitch-lundalogik-band.sh"

mkdir -p "$output_directory"
find "$output_directory" -mindepth 1 -maxdepth 1 -delete

python3 "$repo_directory/Experiments/add_zenith.py" \
    --ring-project "$ring_directory/05-optimized.pto" \
    --output-project "$output_directory/01-with-zenith.pto" \
    "$input_directory/1.tiff" \
    "$input_directory/2.tiff" \
    "$input_directory/3.tiff" \
    "$input_directory/4.tiff" \
    --zenith-image "$input_directory/5.tiff"

"$tools_directory/cpclean" \
    -o "$output_directory/02-cleaned.pto" \
    "$output_directory/01-with-zenith.pto"

"$tools_directory/autooptimiser" \
    -n \
    -o "$output_directory/03-optimized.pto" \
    "$output_directory/02-cleaned.pto"

ring_geometry=$(
    grep '^i ' "$ring_directory/05-optimized.pto" | head -4
)
full_ring_geometry=$(
    grep '^i ' "$output_directory/03-optimized.pto" | head -4
)
if [[ "$ring_geometry" != "$full_ring_geometry" ]]; then
    echo "Zenith optimization changed the frozen ring geometry." >&2
    exit 1
fi

python3 "$repo_directory/Experiments/prepare_fisheye_sources.py" \
    --output-directory "$output_directory/prepared-sources" \
    "$input_directory/1.tiff" \
    "$input_directory/2.tiff" \
    "$input_directory/3.tiff" \
    "$input_directory/4.tiff" \
    "$input_directory/5.tiff"

awk -v directory="$output_directory/prepared-sources" '
BEGIN {
    image = 0
}
/^i / {
    replacement = " n\"" directory "/source" sprintf("%04d", image) ".tif\""
    sub(/ n"[^"]+"/, replacement)
    image++
}
{ print }
' "$output_directory/03-optimized.pto" > "$output_directory/04-render-sources.pto"

"$tools_directory/pano_modify" \
    -o "$output_directory/05-render.pto" \
    -p 2 \
    --fov=360x180 \
    --canvas=4000x2000 \
    --blender=ENBLEND \
    --ldr-file=JPG \
    --ldr-compression=92 \
    "$output_directory/04-render-sources.pto"

"$tools_directory/nona" \
    -r ldr \
    -m TIFF_m \
    -o "$output_directory/layer" \
    "$output_directory/05-render.pto"

"$tools_directory/enblend" \
    -f 4000x2000+0+0 \
    --wrap=horizontal \
    --compression=92 \
    --output="$output_directory/panorama.jpg" \
    "$output_directory"/layer*.tif

echo "$output_directory/panorama.jpg"
