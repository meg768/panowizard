# PanoWizard — Project Context

This file is the canonical technical context for maintaining PanoWizard. Keep
it current when the architecture, invariants, project format, verification
requirements, or release workflow changes. User-facing behavior and build
instructions belong in `README.md`.

## Product and engineering principles

- PanoWizard is a native SwiftUI application for macOS with one built-in
  C++17/OpenCV engine.
- Follow KISS: make the smallest clear change that solves the explicit task. Do
  not add parallel engine paths, hidden feature flags, or panorama-specific
  special cases.
- Engine output must be a complete equirectangular 360° × 180° panorama with a
  2:1 aspect ratio.
- PanoWizard is designed for one complete horizontal ring of overlapping
  fisheye images covering the full 360° sweep and the required vertical field.
  It is not a multi-row panorama stitcher. Separate repair images may fill
  local missing coverage but must not be treated as additional geometry rows.
  The engine's two-source minimum is only defensive input validation; it must
  not be documented as a sufficient capture workflow. Two or three source
  images are not sufficient for a complete panorama.
- The `best-ever` tag is the manually verified visual reference for panoramas
  A–S. Do not change verified image behavior without a clear reason and an
  explicitly scoped validation plan.
- AI retouching, cube-map retouching, and Little Planet rendering are
  post-processing steps that read the completed panorama. They must never be
  connected to geometry, ownership, seam selection, or blending.
- Global panorama adjustments are a final non-destructive post-processing
  layer after repair overlays, pole retouching, and imported cube-map retouch.
  They affect preview and finished exports, but cube-map export for external
  retouching intentionally remains unadjusted.
- The flat pole image used by AI retouching preserves alpha and automatically
  creates an editable base mask from fully transparent pixels only. RGB values
  must never be used to infer missing coverage: opaque black is ordinary image
  content. The base mask is merged with the saved brush mask and never changes
  panorama masks or engine behavior.

## Architecture

- `Sources/PanoWizard/Models/PanoProject.swift` defines project format version
  8. The document reader accepts that version only.
- `Sources/PanoWizard/Services/OpenCVPanoramaEngine.swift` prepares oriented
  TIFF sources and masks, selects the cache file, and forwards progress and
  cancellation through the C API.
- `Sources/PanoWizard/Services/SourceImageRaster.swift` applies ImageIO metadata
  orientation followed by the user's manual quarter turns in the same way for
  thumbnails, source previews, and engine sources.
- `Sources/PanoWizard/Services/MaskedSourceImageWriter.swift` stores the red
  exclusion mask in source alpha. Masked pixels must not be used later by the
  engine.
- `Sources/OpenCVBridge/PanoramaBridge.cpp` contains the entire panorama
  algorithm. Keep it independent of SwiftUI, document storage, and test-project
  names.
- Green protection masks are passed separately to the engine and affect seam
  priority; they never create image content.
- `Sources/PanoWizard/Services/CubeMapService.swift` exports and imports a
  lossless 4 × 3 cross layout containing six cube faces as an isolated
  post-processing step.
- `Sources/PanoWizard/ViewModels/AppModel.swift` connects the document, engine,
  preview, retouching, and export behavior to the UI lifecycle.
- The `Images` application menu mirrors source-image order in the sidebar. Its
  first nine items use Option-1 through Option-9 to select images; selection
  never changes whether an image participates in stitching.

## Sensitive panorama pipeline

Always read the implementation before changing the engine. The current order
is:

1. Optical image circle and valid source coverage
2. SIFT and mutual feature matching
3. Rotation RANSAC and robust joint camera/lens optimization
4. Horizon leveling and separate registration of repair images
5. Spherical warp with alpha, centrality, and protection masks
6. Global radiometric compensation
7. Redundancy filtering and central coverage priority
8. GraphCut labels/ownership and conflict mask
9. Validated seam-local, low-frequency radiometry on each source layer
10. Content-adaptive blending
11. Final orientation and JPEG export

Step 9 does not mix RGB values between owners. It estimates a very
low-frequency field from valid, unclipped, low-gradient overlap pixels,
validates it against separate pixels, and applies symmetric correction to the
source layers before compositing.

Step 10 preserves GraphCut detail with a narrow feather and uses wider
low-frequency tone balancing where sources are consistent, while protecting
structure and conflict. The high-conflict branch has a minimum feather
equivalent to a sigma of 12 pixels at a panorama width of 4096 pixels. It
scales with resolution and is activated by existing structure, conflict, seam
consistency, and radiometric-step information. Do not change its expression,
thresholds, radii, weights, or resolution scaling as part of unrelated cleanup.

Spherical RGB projection is validity-normalized: color and validity weight use
the same Lanczos projection kernel, and color is divided only where the weight
is sufficient. After upscaling, every GraphCut ownership mask is always
intersected with the same image's full-resolution `warp.mask`; the existing
fallback fills any newly exposed pixels from another valid image.

When a GraphCut overlap crosses the panorama's periodic 0°/360° boundary, the
relevant areas for the image pair are packed into a compact, contiguous region
of interest, processed by the same GraphCut implementation, and mapped back
periodically. Other overlaps use the original code path.

Projected user exclusions remain separate from the general validity mask. The
final blend falls back to the narrow GraphCut composite in and around the
exclusion so that masked content is not reintroduced. A low-frequency tone
island may still be visible when the fallback image differs in tone from its
surroundings; there is no separate tone correction for this condition.

Feature matching, control points, lens model, geometry, warp, GraphCut,
ownership, mask logic, radiometry, and blend selection are coupled. Do not
assume that a visible seam justifies a general feather-width or ownership
change. Measure the relevant intermediate result first, and keep diagnostics
separate from production code.

## Coding conventions

- The user interface and user-facing errors are currently English-only. Add
  future languages through an Apple String Catalog and the macOS language
  preference; do not add a parallel in-app language switch without an explicit
  product requirement.
- Sidebar header actions must share the same visual trailing inset. In
  particular, the Panorama `Create` button must align with the Images
  `Add` button even though they live in different SwiftUI containers.
- The numbered control in an image row both selects that row and toggles the
  image's stitch inclusion. Clicking elsewhere in the row only selects it.
- Source changes that invalidate a generated panorama continue immediately
  without an extra confirmation dialog, including when retouch output is
  discarded.
- Use domain names that describe permanent behavior; do not label active code
  as a prototype or experiment.
- Comments should explain why non-trivial logic or an invariant exists, not
  recount development history.
- Do not change numerical algorithm parameters during a rename, cleanup, or
  unrelated task.
- The production engine may read only the explicitly selected original images
  and their masks. Never auto-detect other images that happen to be in the same
  directory.
- Do not put file names, test-case identifiers, or local paths into production
  decisions.
- During development, the project format is intentionally never backward
  compatible. Do not add migrations, fallback decoding, or optional legacy
  fields unless the user explicitly reverses this policy. When the format
  changes, update the version, current reader and writer, tests, `README.md`,
  and this file together.
- Update `README.md` and this file when architecture or maintenance rules
  actually change. Do not create historical documents for temporary
  investigations.

## Verification

Choose verification in proportion to the change:

1. Always run `swift build` after code or build-system changes.
2. Run only the affected focused test suites when the task permits tests.
3. Run `./Scripts/build-app.sh` when the application bundle, resources, native
   linking, or build-tree file names change.
4. Do not run the full A–S regression suite by default. When the user wants to
   review it visually, describe the purpose, selected cases, and expected risks
   and wait for explicit scope.
5. Use only original sources in image regressions, and keep old rendered
   results out of automatic source discovery.

After a refactor, review the diff for changed constants, algorithm expressions,
ordering, mask conditions, and cache behavior. A successful compilation is not
proof that visual output is unchanged.

## Git and checkpoints

- Check `git status` before starting work. Preserve unrelated user changes and
  ask for direction if the requested work overlaps them.
- Create a named restore point before risky engine changes when the user asks
  for one. Never move or rewrite a verified tag.
- Commit and push only when explicitly requested. Do not mix experiments,
  diagnostic artifacts, or generated panoramas with production changes.
- `build-app.sh` derives the app version from the local build start time in
  `YY.MM.DD.HH.MM` (year, month, day, hour, minute) format and writes it into
  the built app. There is no version file in the repository.
- `build-distribution.sh` packages the existing built app into a compressed
  DMG with an Applications shortcut and SHA-256 file. Production mode must use
  Developer ID signing, hardened runtime, Apple notarization, and stapling;
  `--local` is explicitly unnotarized and only for local testing.
- When the user says `commit`, treat it as an approved restore point: use the
  version embedded by the latest `build-app.sh` invocation in
  `build/PanoWizard.app`, build and test without rebuilding the app solely for
  the commit, commit, push `main`, create and push the annotated
  `v<appversion>` tag, and verify a clean working tree.
- When restoring, verify the commit or tag, working tree, build, and remote
  according to the user's exact instructions before doing further work.
