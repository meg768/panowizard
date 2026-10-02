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
- Treat source-code simplicity as a product requirement. Challenge attractive
  UX ideas when their benefit would require disproportionate state,
  coordinate conversion, persistence, cancellation, undo, or special-case
  behavior. Explicitly recommend deferring or rejecting such ideas instead of
  silently expanding the architecture.
- Prefer one complete, immediate workflow over drafts, background work queues,
  parallel representations, or live temporary state shared between views.
  Visual polish alone does not justify a new subsystem.
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
- Retouch patches and Little Planet rendering are post-processing steps that
  read the completed panorama. They must never be connected to geometry,
  ownership, seam selection, or blending.
- The completed panorama is stored internally as an alpha-preserving PNG.
  Transparent pixels are missing source coverage; opaque black pixels are
  ordinary image content and must never be treated as missing coverage.
- Global panorama adjustments are a final non-destructive post-processing
  layer after retouch patches. They affect preview and finished exports.
- Global adjustments live in a trailing panel embedded in Preview. They are
  not a separate sidebar destination. The Preview toolbar toggles the panel,
  and that choice is remembered only for the current app session.
- A new AI mask starts with every non-opaque pixel in the captured panorama
  view selected. This alpha-derived mask is an ordinary editable starting mask:
  it can be painted, erased, or cleared, and remains independent of source-image
  masks. The panorama itself remains alpha-preserving, and opaque black is
  always ordinary image content.

## Retouch patches

Retouching uses one deliberately small, high-level model:

- The Retouch view contains a square spherical viewfinder initialized from the
  current Preview viewpoint. The user positions the exact patch area there,
  followed by `Add manual patch`, `Add AI patch`, and a simple list of applied
  patches. Creation order is layer order; the newest patch wins where patches
  overlap. Manual reordering is not part of version 1.
- A patch is a rectilinear view projected onto the panorama at a saved
  orientation and field of view. Nadir, Zenith, and cube-map workflows are not
  separate product concepts.
- The add buttons capture exactly the viewfinder's current square view. Patch
  dialogs receive that fixed flat image and never change panorama orientation.
  Dragging and scrolling inside a dialog pan and zoom only within the captured
  image.
- An AI patch uses an explicit editable mask and a saved prompt, like the
  current AI retouch workflow, but may target any panorama direction. There is
  no separate Mask mode: Option-drag paints, Command-Option-drag erases, and
  `Clear Mask` discards the explicit mask and generated result. Plain drag and
  scroll pan within the fixed image; Command-scroll and pinch zoom.
- A manual patch is a single modal export/edit/import/apply workflow. Its
  original image exists only temporarily while the dialog is open. On Apply,
  save only the imported edited image and the projection metadata needed to
  render it. Do not add a mask, feather control, draft state, persistent
  original, history, resume support, or automatic image analysis. The user is
  responsible for leaving unchanged context around the edited area so the
  imported patch joins cleanly.
- Applied patches may be enabled, disabled, selected to recenter Preview, or
  deleted. To change a patch, delete it and create a new one. Upstream panorama
  invalidation may discard patches consistently with the current
  post-processing model.
- Composite patches before global adjustments so Preview and every finished
  export share the same result.

### Deferred Preview-first patch workflow

The following is a product idea to preserve for later evaluation. It is not
approved for implementation now and must not be inferred as current behavior:

- Preview is the natural place for the user to discover a local defect: “there
  is something wrong here; I want to repair it.” A future explicit Patch mode
  could let the user mark a square area directly in the main Preview.
- Completing the selection would immediately capture that rectilinear view and
  open the appropriate AI or manual patch dialog. Apply would add the finished
  patch to the Retouch list; Cancel would discard the temporary selection and
  add nothing. The project must not acquire draft or incomplete patch records.
- The patch dialog would edit the captured flat image rather than provide a
  second spherical navigator. Retouch would remain the place for managing
  completed patches.
- An AI mask in this workflow would use the same editable alpha-derived
  starting mask as the current Retouch workflow and remain independent of
  source-image exclusion masks.
- Patch capture must use the unadjusted retouch layer because global
  adjustments are applied after retouch. Capturing already adjusted pixels
  would apply those adjustments twice.
- Keep this idea deliberately deferred. Do not add Preview selection tools,
  draft model state, or project-format changes until the user explicitly asks
  to implement it.

## Architecture

- `Sources/PanoWizard/Models/PanoProject.swift` defines project format version
  10. The document reader accepts that version only.
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
- `RetouchPatchService` exports and reprojects a square rectilinear view at a
  saved Preview orientation. Applied patches are cached as one equirectangular
  working image so existing preview and export paths remain unchanged.
- The exported HTML panorama is a standalone viewer with its own conventional
  controls: drag pans, vertical wheel/scroll and trackpad pinch change only the
  field of view, Command-Plus and Command-Minus zoom, Command-0 resets, and the
  arrow keys pan. Its zoom is deliberately centered; do not reuse the native
  editor's Command-held anchor model or let a zoom event alter yaw or pitch.
- Little Planet export always continues the stereographic projection across the
  square output. Its sheet places a square, horizontally wrapping viewport into
  the 2:1 source panorama beside an equally sized rendered Little Planet. An
  unlabeled horizontal resize slider below both previews is constrained to
  10–75%. Horizontal drag or scroll sets rotation around the planet's center;
  the equatorial direction at the source viewport's horizontal center maps to
  12 o'clock, including after recentering. Clicking selects the source
  direction used as the geometric center. The marker is anchored to that
  source direction and wraps with the panorama.
  Centering is a 3D sphere rotation between inverse stereographic projection and
  equirectangular sampling. Pan and resize update the rendered preview only on
  release; a center click renders once immediately. A successful export
  dismisses the sheet, while cancel or failure leaves it open.
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
- Image surfaces share one navigation language: plain drag or scroll pans,
  Command with vertical scroll and pinch zoom at the pointer, and Command-Plus,
  Command-Minus, and Command-0 zoom or reset the active view. Option-drag paints
  the selected mask type and Command-Option-drag erases; plain drag must never
  edit a mask. Panoramas wrap horizontally, while flat images remain bounded.
- In native source-image and spherical panorama surfaces, Command key-down
  captures both the content/world point under the pointer and its viewport
  position. That exact anchor remains until Command key-up; pointer movement
  and scroll or momentum phases must never replace it.
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
