#!/bin/zsh

set -euo pipefail

repo_directory=${0:A:h:h}
tools_directory="$repo_directory/Vendor/Hugin/MacOS"
libraries_directory="$repo_directory/Vendor/Hugin/Libraries"
input_directory="/Users/magnus/Desktop/Lundalogik"
output_directory="$repo_directory/Experiments/output/lundalogik-band"

export DYLD_LIBRARY_PATH="$libraries_directory"
export OMP_NUM_THREADS=1

mkdir -p "$output_directory"
find "$output_directory" -mindepth 1 -maxdepth 1 -delete

"$tools_directory/pto_gen" \
    -p 3 \
    -f 120 \
    -o "$output_directory/01-base.pto" \
    "$input_directory/1.tiff" \
    "$input_directory/2.tiff" \
    "$input_directory/3.tiff" \
    "$input_directory/4.tiff"

awk '
BEGIN {
    yaw[0] = "0.0"
    yaw[1] = "90.0"
    yaw[2] = "180.0"
    yaw[3] = "270.0"
    image = 0
}
/^i / {
    sub(/ y[^ ]+/, " y" yaw[image])
    sub(/ p[^ ]+/, " p0.0")
    image++
}
{ print }
' "$output_directory/01-base.pto" > "$output_directory/02-seeded.pto"

python3 "$repo_directory/Experiments/generate_control_points.py" \
    --input-project "$output_directory/02-seeded.pto" \
    --output-project "$output_directory/03-control-points.pto" \
    --horizontal-fov 120 \
    "$input_directory/1.tiff" \
    "$input_directory/2.tiff" \
    "$input_directory/3.tiff" \
    "$input_directory/4.tiff"

"$tools_directory/cpclean" \
    -o "$output_directory/04-cleaned.pto" \
    "$output_directory/03-control-points.pto"

"$tools_directory/autooptimiser" \
    -a \
    -l \
    -s \
    -o "$output_directory/05-optimized.pto" \
    "$output_directory/04-cleaned.pto"

python3 "$repo_directory/Experiments/prepare_fisheye_sources.py" \
    --output-directory "$output_directory/prepared-sources" \
    "$input_directory/1.tiff" \
    "$input_directory/2.tiff" \
    "$input_directory/3.tiff" \
    "$input_directory/4.tiff"

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
' "$output_directory/05-optimized.pto" > "$output_directory/05-render-sources.pto"

"$tools_directory/pano_modify" \
    -o "$output_directory/06-render.pto" \
    -p 2 \
    --fov=360x180 \
    --canvas=4000x2000 \
    --blender=ENBLEND \
    --ldr-file=JPG \
    --ldr-compression=92 \
    "$output_directory/05-render-sources.pto"

"$tools_directory/nona" \
    -r ldr \
    -m TIFF_m \
    -o "$output_directory/layer" \
    "$output_directory/06-render.pto"

"$tools_directory/enblend" \
    -f 4000x2000+0+0 \
    --wrap=horizontal \
    --compression=92 \
    --output="$output_directory/panorama.jpg" \
    "$output_directory"/layer*.tif

echo "$output_directory/panorama.jpg"
