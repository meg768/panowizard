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

A new AI mask starts with every transparent pixel in the captured panorama
view selected and remains independent of source-image masks. The initial mask
can be painted, erased, or cleared like any other mask. An existing AI mask is
restored during Edit. Opaque black pixels remain ordinary image content.

Little Planet export creates a stereographic PNG from the completed panorama.
The projection always fills the square output. Pan the wrapping 2:1 panorama to
set the planet's orientation, click it to choose the geometric center, and use
the unlabeled slider below the two previews to resize the result.

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

- Xcode 26.5 and macOS 26.5 or newer
- Apple Silicon (the original pinned OpenCV binaries are arm64)
- Your Apple Developer team configured in Xcode for automatic signing

Open `PanoWizard/PanoWizard.xcodeproj` and choose the shared `PanoWizard`
scheme. Build or run normally in Xcode. The native `OpenCVBridge` static-library
target builds the original C++17 engine. Xcode links, embeds and signs the pinned
OpenCV dynamic libraries from `PanoWizard/Vendor/OpenCV`; no system-wide OpenCV
installation is needed. The app uses App Sandbox, user-selected read/write file
access, app-scoped security bookmarks and outgoing network access for AI retouch.

From the repository root:

```sh
xcodebuild -project PanoWizard/PanoWizard.xcodeproj \
  -scheme PanoWizard -configuration Debug \
  -destination 'platform=macOS,arch=arm64' build

xcodebuild -project PanoWizard/PanoWizard.xcodeproj \
  -scheme PanoWizard -configuration Release \
  -destination 'platform=macOS,arch=arm64' build
```

The latest successful app builds are available at `Build/Debug/PanoWizard.app`
and `Build/Release/PanoWizard.app` through the repository’s Git-ignored `Build` link.
Xcode stores the products in `~/Library/Developer/Xcode/PanoWizardBuilds` to keep
iCloud metadata from invalidating code signing. On a new checkout, create a
`Build` symlink to that directory if desired.

Archive and distribute using Xcode's standard Organizer workflow. This repository
has no Swift package manifest or custom bundle/signing/distribution scripts.
The App Store version and build number remain managed in the Xcode project.

### Source-image access in the sandbox

Original images remain external files, as in the existing application. Selected
files are remembered using security-scoped bookmarks in the app's preferences.
When opening an existing project without a saved access grant, macOS may ask you
to choose the folder containing its source images. The project format remains 10.
The sandboxed app has separate preferences from the old app; enter the OpenAI
API key again in its existing API-key dialog if needed.

### Tests

The original 13 Swift Testing suites are included in the native hosted
`PanoWizardTests` target. Run them in Xcode or with:

```sh
xcodebuild -project PanoWizard/PanoWizard.xcodeproj \
  -scheme PanoWizard -destination 'platform=macOS,arch=arm64' test
```

The optional real-panorama fixture test requires the explicit
`PANOWIZARD_PANORAMA_PROJECT` environment variable in the scheme's test action.
Without it, that test returns without processing a fixture. Visual image
regressions remain separate from normal builds.

## Repository layout

- `PanoWizard/PanoWizard.xcodeproj` — native app, bridge and hosted test targets
- `PanoWizard/PanoWizard/Application` — application and document lifecycle
- `PanoWizard/PanoWizard/Models` — project, source-image and mask models
- `PanoWizard/PanoWizard/Services` — engine adapter, import, export, retouch and sandbox access
- `PanoWizard/PanoWizard/Views` — SwiftUI interface and panorama viewer
- `PanoWizard/PanoWizard/ViewModels` — application state and workflow orchestration
- `PanoWizard/PanoWizard/Assets.xcassets` — original app icon and accent color
- `PanoWizard/OpenCVBridge` — original C API and native panorama implementation
- `PanoWizard/Resources` — welcome backgrounds, project icon and third-party licenses
- `PanoWizard/PanoWizardTests` — original focused unit and engine tests
- `PanoWizard/Vendor/OpenCV` — original pinned headers and dynamic libraries
- `docs` — self-contained GitHub Pages help, illustrated guides and images
- `CONTEXT.md` — current technical context and verification limits
