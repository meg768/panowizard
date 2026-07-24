#!/bin/zsh

set -euo pipefail

project_directory=${0:A:h:h}
cache_directory="$project_directory/.vendor-cache"
archive="$cache_directory/opencv-5.0.0.tar.gz"
source_directory="$cache_directory/opencv-5.0.0"
build_directory="$cache_directory/opencv-build"
install_directory="$project_directory/Vendor/OpenCV"

mkdir -p "$cache_directory" "$project_directory/Vendor"

if [[ ! -f "$archive" ]]; then
    curl \
        --location \
        --fail \
        --silent \
        --show-error \
        "https://github.com/opencv/opencv/archive/refs/tags/5.0.0.tar.gz" \
        --output "$archive"
fi

if [[ ! -d "$source_directory" ]]; then
    tar -xzf "$archive" -C "$cache_directory"
fi

cmake \
    -S "$source_directory" \
    -B "$build_directory" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_INSTALL_PREFIX="$install_directory" \
    -DBUILD_LIST=core,imgproc,imgcodecs,features,flann,calib,stitching \
    -DBUILD_SHARED_LIBS=ON \
    -DBUILD_TESTS=OFF \
    -DBUILD_PERF_TESTS=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_opencv_apps=OFF \
    -DBUILD_JAVA=OFF \
    -DBUILD_opencv_python3=OFF \
    -DWITH_FFMPEG=OFF \
    -DWITH_GSTREAMER=OFF \
    -DWITH_OPENCL=OFF \
    -DWITH_OPENGL=OFF \
    -DWITH_QT=OFF \
    -DWITH_VTK=OFF \
    -DWITH_WEBP=OFF \
    -DWITH_OPENEXR=OFF \
    -DWITH_TIFF=ON \
    -DBUILD_TIFF=ON \
    -DWITH_JPEG=ON \
    -DBUILD_JPEG=ON \
    -DWITH_PNG=ON \
    -DBUILD_PNG=ON

cmake \
    --build "$build_directory" \
    --target install \
    --parallel "$(sysctl -n hw.ncpu)"
