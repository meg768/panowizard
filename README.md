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
- Add AI or manually edited retouch patches anywhere in the panorama.
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
7. Optionally add AI or manually edited patches to local panorama areas.
8. Open the Adjustments panel in Preview to tune the finished panorama's
   light and color non-destructively.
9. Export the panorama or create a Little Planet image.

### Navigation

Source-image and panorama views use the same controls. Drag or two-finger
scroll to pan. Pressing Command captures the point under the pointer as the
zoom anchor until Command is released; vertical scroll while holding Command
zooms around that fixed point. Pinch zooms at the pointer, and Command-Plus,
Command-Minus, or Command-0 zooms in, zooms out, or resets the view. A panorama
wraps horizontally; ordinary images stop at their edges.

In a mask-editable image, Option-drag paints the selected Include or Exclude
mask and Command-Option-drag erases. A plain drag never changes a mask. The
interactive HTML export uses the same navigation controls without mask editing.

### Source masks

Red masks exclude source pixels before geometry estimation, radiometric
correction, and compositing. Green masks are passed separately to the panorama
engine and influence seam priority; they never create new image content.

Changing an exclusion mask invalidates the relevant alignment cache, so the
next panorama build uses the updated source data. Inclusion masks influence
seam selection without changing the underlying source pixels.

### Retouching and alternative exports

Retouching is an optional post-processing step and does not affect panorama
alignment or seam selection. Retouch contains a square panorama viewfinder
that starts at the direction and zoom last shown in Preview. Position the exact
area there, then choose `Add manual patch` or `Add AI patch` to capture that
fixed view. In the AI dialog, drag or two-finger scroll pans within the captured
image, Command-scroll or pinch zooms, Option-drag paints the mask, and
Command-Option-drag erases. Manual Patch is a modal export, external edit,
import, and Apply workflow using a
2048 × 2048 PNG named `patch.png` by default. The project stores only the
finished manual patch and the projection needed to place it.

Applied patches form a simple ordered list that is displayed oldest first.
Newer patches appear over older ones where they overlap. Each patch can be
located in Preview, enabled or disabled with its switch, edited, or deleted.

A new patch starts from the currently rendered panorama, including earlier
enabled patches. Editing a patch keeps its position in the list and rebuilds
its source from the panorama and the enabled patches below it, so a patch is
never applied over itself. AI Edit restores the saved viewpoint, instruction,
mask, and previous result. Manual Edit shows and exports the previous imported
patch so it can be adjusted externally and imported again.

A new AI mask starts empty and is independent of panorama transparency and
source-image masks. An existing AI mask is restored during Edit. Only the
explicitly painted mask is sent as editable; opaque black pixels remain
ordinary image content.

Little Planet export creates a stereographic PNG with a transparent background
from the completed panorama. Rotation, horizon height, and edge feather can be
adjusted in a live preview. Clicking a visible part of the planet moves that
direction to the 12 o'clock position. The planet uses the largest circle that
fits with a two-pixel safety margin.

Global adjustments are saved as project settings and applied after local
retouching. They appear in the spherical preview and in JPEG, PNG, interactive
HTML, and Little Planet exports.

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
10. Writes a complete 2:1 alpha-preserving equirectangular PNG and reports
    coverage and hole statistics.

The alignment cache is keyed by the engine format, source identity and
metadata, image role, orientation, and red exclusion masks.

## Project files

The project format is version 10. It stores source images, roles, manual
rotation, masks, the completed panorama, preview state, ordered retouch
patches, and global panorama adjustments in one project package. PanoWizard
accepts version 10 projects only; other project-format versions are rejected.

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

### Build a macOS distribution

The standard distribution is a compressed DMG containing `PanoWizard.app` and
an Applications-folder shortcut. First build the app, then create a local
development DMG with:

```sh
./Scripts/build-app.sh
./Scripts/build-distribution.sh --local
```

The local DMG is ad hoc signed and is not suitable for public distribution.
For a Gatekeeper-ready release, install a **Developer ID Application**
certificate and save notarization credentials with `notarytool`. Then run:

```sh
PANOWIZARD_SIGN_IDENTITY="Developer ID Application: Example (TEAMID)" \
PANOWIZARD_NOTARY_PROFILE="PanoWizard" \
./Scripts/build-distribution.sh
```

Production mode signs the embedded OpenCV libraries and app with hardened
runtime, signs and submits the DMG for Apple notarization, staples the ticket,
validates the result, and writes a matching SHA-256 file beside the DMG.

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
