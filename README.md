# PanoWizard

PanoWizard is a native macOS application for creating complete 360° × 180°
panoramas from one horizontal ring of overlapping fisheye photographs. The
single-row source ring must cover the entire 360° sweep and provide enough
vertical coverage for the finished sphere. PanoWizard is not a multi-row
panorama stitcher. It combines source-image management, masking, automatic
geometric alignment, seam selection, color and exposure balancing, interactive
preview, retouching, and export in one project.

## What PanoWizard can do

- Build a full 2:1 equirectangular panorama from one complete, overlapping 360°
  ring of fisheye images.
- Detect and optimize the shared camera and lens geometry automatically.
- Treat images as part of the single panorama ring or as separate repair images
  used only to fill local missing coverage, never as additional rows.
- Apply editable exclusion masks and seam-priority masks to individual source
  images.
- Correct source orientation in 90-degree steps without modifying the original
  files.
- Balance color and exposure across overlaps while preserving image detail.
- Preview the result interactively as a spherical 360° panorama.
- Retouch the nadir or zenith with an optional OpenAI-powered workflow.
- Export and re-import a lossless cube map for editing in an external image
  editor.
- Apply non-destructive global light and color adjustments after retouching.
- Create a configurable Little Planet image from the completed panorama.
- Export the finished panorama as JPEG or PNG, or as a self-contained
  interactive HTML file.

PanoWizard never synthesizes missing scene content during stitching. Areas with
no valid source coverage remain empty until they are repaired or retouched.

## Using PanoWizard

1. Create a project and import the complete single-row image ring for the full
   360° panorama. Two or three source images are not sufficient, and multi-row
   capture sets are not supported. All images in the panorama must have the
   same pixel dimensions.
2. Review the image order. If necessary, classify an image as **Automatic**,
   **Panorama Ring**, or **Repair Image**.
3. Select a source image to open its mask editor automatically.
4. Paint a red exclusion mask over source content that must not be used. Paint a
   green inclusion mask where that source should be preferred during seam
   selection.
5. If necessary, rotate the selected source image counterclockwise in
   90-degree steps with the rotation button at the end of the mask toolbar.
6. Choose **Create Panorama** and inspect the equirectangular result in the
   interactive 360° preview.
7. Optionally retouch the nadir or zenith or exchange a cube map with an
   external editor.
8. Adjust the finished panorama's light and color non-destructively.
9. Export the panorama or create a Little Planet image.

### Source masks

Red masks exclude source pixels before geometry estimation, radiometric
correction, and compositing. Green masks are passed separately to the panorama
engine and influence seam priority; they never create new image content.

Changing an exclusion mask invalidates the relevant alignment cache, so the
next panorama build uses the updated source data. Inclusion masks influence
seam selection without changing the underlying source pixels.

### Retouching and alternative exports

AI retouching is an optional post-processing step and does not affect panorama
alignment or seam selection. PanoWizard stores the prompt, working mask, raw AI
result, and accepted local patch in the project. Transparent pixels
automatically become an editable starting mask for AI retouching. Opaque black
pixels remain ordinary image content and are never inferred to be holes.

For manual external retouching, PanoWizard can export the currently visible
panorama as a lossless PNG cube map. Its six 2048 × 2048 faces use a standard
4 × 3 cross layout. An imported cube map is stored separately and can become
the base for later local AI retouching.

Little Planet export creates a stereographic PNG from the completed panorama.
Rotation, output size, horizon height, and background can be adjusted in a live
preview.

Global adjustments are saved as project settings and applied after local
retouching. They appear in the spherical preview and in JPEG, PNG, interactive
HTML, and Little Planet exports. Cube-map export for external retouching stays
unadjusted so imported edits remain below the global adjustment layer.

Building a new panorama removes downstream retouch results while preserving the
source images and source masks.

## How it works

PanoWizard uses a single in-process C++17/OpenCV panorama engine behind a small
C bridge to Swift. It does not launch external stitching tools.

The engine:

1. Writes oriented source images as TIFF files with exclusion masks stored in
   alpha.
2. Detects a common optical image circle.
3. Matches SIFT features and filters them with rotation-based RANSAC.
4. Jointly optimizes camera rotations and the fisheye lens model, then levels
   the horizon.
5. Projects panorama-ring images onto spherical equirectangular layers and
   registers repair images separately.
6. Computes global overlap radiometry, redundancy suppression, and central
   coverage priority.
7. Uses GraphCut to choose source ownership and seam geometry, including
   protection-mask and conflict information.
8. Applies validated, seam-local, low-frequency color and tone correction to
   the warped source layers without changing ownership.
9. Combines narrow detail transitions with wider low-frequency balancing in
   consistent regions while protecting structure and high-conflict areas.
10. Writes a complete 2:1 equirectangular JPEG and reports coverage and hole
    statistics.

The alignment cache is keyed by the engine format, source identity and
metadata, image role, orientation, and red exclusion masks.

## Project files

The project format is version 8. It stores source images, roles, manual
rotation, masks, the completed panorama, preview state, pole retouches, and an
imported cube-map retouch, plus global panorama adjustments, in one project
package. PanoWizard accepts version 8
projects only; other project-format versions are rejected.

## Building from source

### Requirements

- macOS 26 SDK
- Swift 6.2
- The pinned OpenCV headers and dynamic libraries in `Vendor/OpenCV`

The OpenCV dependencies are expected to be present in the repository. No
system-wide OpenCV installation is required.

### Development build

From the repository root, build and run the Swift package:

```sh
swift build
swift run PanoWizard
```

### Build a macOS application bundle

Create a locally signed application bundle with:

```sh
./Scripts/build-app.sh
open build/PanoWizard.app
```

The script derives the app version from the local build start time using
`YY.MM.DD.HH.MM` (year, month, day, hour, minute), creates
`build/PanoWizard.app`, embeds the OpenCV dynamic libraries, and applies an ad
hoc signature. Background images in
`Sources/PanoWizard/Resources/Backgrounds` with a `jpg`, `jpeg`, or `png`
extension are bundled automatically and rotated in the welcome view.

## Tests

Run the smallest relevant test suite while developing:

```sh
swift test --filter OpenCVPanoramaEngineTests
swift test --filter PanoProjectTests
swift test --filter LittlePlanetRendererTests
```

The engine tests cover behavior such as 2:1 output, alignment-cache reuse, mask
transfer, and source selection. Visual image regressions use explicitly chosen
original projects and are run separately; they are not part of a normal build.

## Repository layout

- `Sources/PanoWizard/Application` — application and document lifecycle
- `Sources/PanoWizard/Models` — project, source-image, and mask models
- `Sources/PanoWizard/Services` — engine adapter, import, export, and retouching
- `Sources/PanoWizard/Views` — SwiftUI interface and panorama viewer
- `Sources/OpenCVBridge` — C API and native panorama implementation
- `Sources/PanoWizard/Resources` — resources bundled by Swift Package Manager
- `Resources` — application icons and `Info.plist` for the app bundle
- `Scripts` — reproducible application packaging
- `Tests/PanoWizardTests` — focused unit and engine tests
- `Vendor/OpenCV` — pinned OpenCV headers and dynamic libraries
- `CONTEXT.md` — canonical technical context and maintenance rules
