# PanoWizard

The automatic control-point generator's principles and deliberate limits are
documented in [CONTROL_POINT_STRATEGY.md](CONTROL_POINT_STRATEGY.md).

PanoWizard is a native macOS application for automatic panorama stitching,
with an emphasis on full-spherical fisheye panoramas and an efficient manual
control-point workflow when a difficult handheld set needs refinement.

The product goal is fully automatic output at least as good as the matching
PTGui reference, starting from source images and metadata only. Manual control
points and corrections remain diagnostic tools, not part of the acceptance
path.

Each document window contains one panorama. Projects are saved as `.pw` file
packages and can be reopened with the standard macOS document commands. A
package contains `project.json`, the user's PNG masks, and the most recently
stitched panorama. Original source images remain at their existing locations
and are not embedded in the project.

## Requirements

- macOS 26
- Apple Silicon
- Xcode 16 or later
- Swift 6

## Build and run

Open `Package.swift` in Xcode and select **PanoWizard** as the run target. The
project can also be verified from Terminal:

```sh
swift build
swift test
```

Build an ad hoc-signed application with:

```sh
./Scripts/build-app.sh
```

The application is written to `build/PanoWizard.app`.

## Panorama workflow

PanoWizard provides calibrated profiles for the Sigma 8 mm Circular Fisheye
and Nikon 10.5 mm Fisheye on DX sensors. Images can be assigned as horizontal,
zenith, or nadir views and can participate either in alignment or only in
repair/fill rendering.

The automatic control-point pipeline uses OpenCV feature matching, mutual
ratio filtering, robust geometric validation, and spatially balanced point
selection. For four-image circular-fisheye rings it builds the four real ring
transitions rather than introducing contradictory diagonal links. The Sigma
optimization can refine radial distortion and optical centre after the camera
poses have been established. Internal per-pair diagnostics record feature,
match, geometric-inlier, selected-point, reprojection, and spatial-coverage
statistics for benchmarking.

This pipeline has produced a nearly seamless handheld four-image Sigma
panorama in a demanding near-nadir scene with strong parallax and regular
ground detail. That result is a useful regression target, not a guarantee that
every handheld set can be solved automatically; difficult pairs can still be
completed or corrected manually.

## Control-point editor

The control-point editor is designed to make manual refinement practical:

- the two image panels keep independent zoom and pan positions;
- two-finger scrolling and pinch gestures zoom around the pointer;
- click-dragging the background pans the active panel;
- control-point markers remain a constant on-screen size and can be moved at
  every zoom level;
- each panel uses the source image at its native pixel resolution for detailed
  inspection;
- `Esc` leaves add/move mode and cancels the active control-point interaction;
- points can be suggested for one pair or regenerated for the complete ring.

## Masks and repair images

Every source image has a manual, non-destructive pixel mask. Select an image
in the sidebar and paint red over people, tripods, or other pixels that should
not be used in the final blend. Before rendering, the mask is transferred to
the source alpha channel; Nona transforms it with the image and Enblend uses
the remaining unmasked overlaps.

Control-point exclusion masks are stored separately and are applied during
automatic feature matching. They do not alter the source image or the final
blend.

A handheld nadir or repair image can be marked as **Fill only**. Alignment
images establish and freeze the panorama geometry first; fill-only images are
registered afterwards and cannot move the base panorama. Image roles and a
successful alignment are stored in the project. PanoWizard does not assume a
special role from an image's position in the source list.

## External pole retouch

A stitched panorama can export its nadir and zenith as 90-degree cube faces
at 2048×2048 pixels for editing in an external image editor. Importing an
edited PNG stores it non-destructively in the `.pw` package and previews it
in the spherical viewer. Each plate keeps a soft transparent perimeter and
is baked into JPEG and HTML exports; no source-image registration or control
points are used.

## Architecture

The application uses MVVM with small services and protocol-based dependencies:

- `Views` contains the SwiftUI interface and native AppKit-backed image and
  panorama viewports.
- `ViewModels` owns the observable state for each document window.
- `PanoProjectDocument` reads and writes the versioned `.pw` format.
- `ImageImportService` discovers images in files and folders.
- `ImageMetadataReader` reads EXIF metadata through ImageIO.
- `PanoramaGroupingService` sorts imported image sequences.
- `OpenCVBridge` performs feature matching and geometry operations.
- `PanoramaEngine` coordinates OpenCV, Hugin, Nona, and Enblend.
- `PanoramaExporting` defines the export boundary.

OpenCV 5 is built locally for ARM64/macOS 26 with:

```sh
./Scripts/build-opencv.sh
```

This requires `cmake` and `ninja`. `build-app.sh` runs the OpenCV build on the
first invocation and embeds the required libraries in the application.

The Hugin command-line tools are fetched and prepared with:

```sh
./Scripts/build-hugin-tools.sh
```
