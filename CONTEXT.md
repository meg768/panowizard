# PanoWizard — Current Project Context

Last reviewed: 2026-11-20.

This file contains current decisions, working conventions and unresolved issues.
Earlier investigations, build logs and superseded decisions remain in Git history.
The full pre-condensation version is available at commit `f27e785`.
Write project documentation in English; communicate with Magnus in Swedish.
Follow the current task and applicable AGENTS.md instructions for general rules.
Update existing sections instead of appending a narrative after each work session.
Keep this file around 250 lines; retain evidence and uncertainty for open issues.

Approval requirement (Magnus, 2026-11-19): discuss the solution first. Do not
generate or modify code, including prototypes/diagnostic code, before Magnus
explicitly approves implementation. Questions and feedback are not approval.
This is also saved in the global AGENTS.md instructions.

## Project and architecture

- Repository: https://github.com/meg768/panowizard; normal branch: `main`.
- Local checkout: `/Users/magnus/GitHub/panowizard`.
- Native macOS app: SwiftUI/AppKit, Swift 6, Xcode 26.5, macOS 26.5 minimum.
- Xcode project: `PanoWizard/PanoWizard.xcodeproj`; shared scheme: `PanoWizard`.
- Bundle ID: `se.egelberg.panowizard`; developer team: `52A6FA9VB5`.
- Deliberately Apple Silicon/arm64-only. Do not add Intel/universal support or
  rebuild/replace the pinned OpenCV binaries without an explicit task.
- One in-process C++17/OpenCV engine behind a C bridge; no external stitcher.
- `PanoWizard/Vendor/OpenCV` contains the pinned OpenCV 5 headers and 11 dylibs.
  Xcode embeds/signs the libraries; no system OpenCV installation is required.
- SFTP uses Citadel 0.12.1 and pinned transitive packages in `Package.resolved`.
  Preserve package versions during unrelated builds; licenses are in Resources.
- App Sandbox and Hardened Runtime stay enabled. User-selected read/write,
  app-scoped bookmarks and outgoing network access are required.

Source map:

- `PanoWizard/PanoWizard/Application`: app/document lifecycle and menus.
- `Models`: project format, sources, masks, patches and adjustments.
- `ViewModels/AppModel.swift`: application state and workflows.
- `Services`: import, file access, stitching, retouch, export and publishing.
- `Views`: SwiftUI/AppKit UI and panorama viewers.
- `PanoWizard/OpenCVBridge/PanoramaBridge.cpp`: geometry, radiometry and blending.
- `PanoWizard/PanoWizardTests`: native hosted Swift Testing suites.
- `README.md`: product overview, build commands and repository layout.
- `docs/`: illustrated user help; avoid duplicating its full feature descriptions.

## Build, installation and distribution

Use the native Xcode project and shared scheme. Build products and DerivedData
must be outside iCloud. The old repository `Build` symlink may contain stale
products; it is not the authoritative output location. Standard Xcode product
placement also keeps Swift package resource bundles beside the app.

Established local Release command:

```sh
xcodebuild -project PanoWizard/PanoWizard.xcodeproj \
  -scheme PanoWizard -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /Users/magnus/Library/Developer/Xcode/PanoWizardSFTP build
```

The resulting app is under that DerivedData directory's
`Build/Products/Release/PanoWizard.app`. Do not change package pins just to build.
Use Xcode Organizer for normal Archive, Validate and Upload; there is no custom
bundle/signing/distribution pipeline. Test commands are documented in README.

Magnus's standing installation request:

1. Preserve the previous `/Applications/PanoWizard.app` in a dated location
   outside the repository before replacement. Keep a usable rollback copy.
2. Copy the complete newly successful signed Release bundle to Applications
   using `ditto` or equivalent; do not substitute an older build after failure.
3. Verify installed version/build, equality with the built bundle and
   `codesign --verify --deep --strict /Applications/PanoWizard.app`.
4. Preserve unsaved user documents when closing/restarting the app.

Magnus manually controls `MARKETING_VERSION` before App Store release preparation.
Do not increment it during ordinary local builds or check-ins. The existing
Generate Build Metadata phase produces local timestamp build IDs (`YYYYMMDDHHmm`)
and the About timestamp without editing tracked source files. Minute resolution
means consecutive distribution builds need distinct build minutes.

Last verified local installation (2026-11-20): **1.5 (202611200348)**.
Rollback: `/Users/magnus/Library/Developer/Xcode/PanoWizard-before-overlay-16-20261120-035050.app`
(previous build 202611200331). Quit the app before restoring the complete backup
as `/Applications/PanoWizard.app`; keep the backup itself intact.

Last recorded Apple status, verified 2026-11-16, not a live status check:

- 1.4 was publicly available; submitted build 202611022209.
- 1.5 build 202611161921 was uploaded; review submission was still pending.
- Archive: `~/Library/Developer/Xcode/Archives/2026-11-16/PanoWizard-1.5-20261116-192014.xcarchive`.
- Later local exposure/Little Planet changes are newer than that uploaded build.
- Eleven warnings concern missing matching OpenCV dSYMs. They were also present
  in the validated 1.4/1.5 uploads; do not rebuild OpenCV merely to suppress them.

Known macOS launch issue (reproduced 2026-11-19): CoreServicesUIAgent can reach
256 open FDs while traversing recursive Mountain Duck server /proc paths,
causing POSIX 24 app-launch failures. Restarting that confirmed stuck agent
restored app launch; no product/file-limit/security change was needed.

## Documents, sources and sandbox access

- `.pw` is a project package, UTI `se.egelberg.panowizard.project`.
- Project format remains **10**. Optional fields must preserve reading of older
  format-10 projects. Other format versions are rejected.
- Source-image projects reference external originals. Never silently copy/move
  original photographs into the package or alter them during experiments.
- The package stores masks, the full panorama, ordered retouch patches,
  adjustments and view/export metadata. Preserve these on Save As/reopen.
- File → New from Panorama imports an exact 2:1 equirectangular PNG into the
  package and uses the existing retouch/preview/export pipeline without sources.
- `source-access.json` is optional, project-specific app-scoped bookmark data.
  Restore access before source reads; retain active security scopes as needed.
- Recover inaccessible sources through a native folder Grant Access panel,
  checking all sources and deduplicating folder grants. Cancellation must not
  delete source references. Readable projects need no recovery panel.
- Save relevant grants with the project; do not create a global source registry
  or grant broader access automatically. Save As carries relevant grants.
- Bookmarks depend on local filesystem/app signing identity. Another Mac or
  account may need Grant Access again; do not promise portable access grants.
- Machine-specific grants, API keys and SFTP credentials must not be published
  with regression data. Existing historical tracked examples are not authority
  to add newly generated access grants.
- Each document instance uses isolated temporary files, even when project IDs
  match. Closing/resetting one window must not remove another window's assets.

## Panorama engine and mask semantics

The supported input is one complete overlapping horizontal fisheye ring,
with common image dimensions and shared lens parameters. Separate repair images
fill missing local coverage; they are not additional panorama rows. Do not add
case-specific source discovery or panorama-specific algorithm branches.

Pipeline: oriented TIFFs → optical support → SIFT/rotation RANSAC → shared lens
and camera optimization → horizon leveling → spherical projection → radiometry
→ GraphCut ownership → seam-local tone correction → detail-preserving blending.
Source orientation uses ImageIO followed by the user's quarter turns.

Create Panorama computes native output sampling from source dimensions and the
fitted lens (`outputWidth = 0`). Geometry, radiometry and seams are analyzed at
at most 4096 px wide; native source detail is rendered in bounded blocks.
The stored result is a full-resolution 2:1 PNG with alpha. Preview can use a
smaller display image. Original exports reuse the saved result without stitching.
Transparent pixels mean missing coverage; opaque black is ordinary scene content.
Never claim that stitching synthesizes missing content.

Current source-mask behavior (decision 2026-11-14; checked against code):

- Both ring and repair images use the optically valid source area for matching
  and alignment. User-painted red/green masks apply during rendering.
- Red Exclude forbids those source pixels from compositing. Green Include
  prioritizes source ownership; it does not guarantee ownership or exclude the
  rest of the source. Red wins where red and green overlap.
- Invert swaps marked/unmarked areas of the selected mask only, with Undo.
- Repair images are registered against the fixed ring/lens; they must not alter
  ring geometry. Automatic classification can choose incorrectly (see night A).
- Automatic gained a nadir-to-Repair heuristic on 2026-11-13 (`3d2a33f`);
  no equivalent zenith heuristic exists. Ring classification uses overlap-graph
  connectivity. The 2026-11-14 change moved painted masks out of registration.
- Masks are outside the alignment-cache key. Swift key:
  `unmasked-registration-v1`; C++ cache format: `8`. Do not change cache identities
  during unrelated cleanup. README's older claim that red masks affect geometry
  is superseded by this behavior.

Retouch is downstream of stitching. Newer enabled patches overlay older ones;
editing a patch reconstructs its source from patches below it, never itself.
Global adjustments apply after retouch and are shared by Preview and exports.
Creating a new panorama removes downstream patches only after the existing
confirmation flow. Reimport without new sources must retain existing results.

## Product decisions worth preserving

Navigation uses plain drag to pan/rotate, vertical scroll or pinch to zoom,
and pointer anchoring at gesture start. Horizontal-dominant scrolling is ignored.
Option-drag paints source/AI masks; Command-Option-drag erases. Plain drag must
not paint. Keyboard zoom/reset and existing cancellation/Undo behavior remain.

Little Planet (approved 2026-11-18/19):

- One large preview and one flat, always-visible panel with the exact labels
  **Zoom**, **Rotation**, **Tilt**, **Center**. No disclosure or look presets.
- Zoom spans 0–100%, default 50; zero maps to the positive 0.01 projection bound.
- Tilt changes vertical center: 0° planet, 90° sideways, 180° tunnel.
  Center changes horizontal direction (0–360°); Rotation turns around the center.
- Clicking the full 2:1 thumbnail sets Tilt and Center together. Reset restores
  defaults. Preview refines after slider gestures; export remains full resolution.
- The last successful PNG export stores optional `littlePlanetSettings` in the
  project (Zoom/Rotation/Tilt/Center). Normal Save persists them in `.pw`.
  Cancel, failed export and Reset alone do not overwrite the saved settings.
  No app-wide setting migration into unrelated projects. Old projects use defaults.

AI retouch (2026-11-19): use one editable Instruction field with reset; remove
Replace/Repair preset buttons. The API already takes only image, mask and active
instruction. Retain saved legacy mode/prompt fields for compatibility and restore
the existing patch's active instruction when editing. Default prompts are unchanged.
Signed Release build/install verified; native UI checked on a disposable A copy,
including editing/reset. No live AI generation was needed. Help text is updated.

Overlay (approved 2026-11-19): own row between Retouch and Export. One optional
panorama/overlay.png plus overlayPrompt/overlayEnabled are saved with format 10.
The enabled overlay feeds Preview/exports; PSD includes a separate overlay layer.
Input is the retouched panorama before global adjustments. Base/retouch changes
clear the overlay. Generate uses the existing gpt-image-2 service at the nearest
lower 16-aligned 2:1 dimensions/high; Apply stores the returned bytes unchanged.
Native UI and saved PNG/instruction/on-off state verified with a disposable fixture.
Live AI generation, Apply after a real response, PSD and 360° seam quality remain
unverified. This is not a fix for night A's stitching seams. Tag pre-overlay is
available for rollback. Build log and disposable fixture: work/overlay-20261119/.
Workspace decision (approved/verified 2026-11-20): one full panorama at 2:1, with
a simple toolbar below: Use overlay switch, Edit… and trash. No patch-list
styling, thumbnail or Active/Hidden text: there is only one overlay.
The switch changes the displayed image and Preview/exports.
Delete clears overlay data/temporary image/prompt/enabled flag and marks the
project dirty. With no overlay, show only Create AI overlay….
Native disposable-copy checks: toggle, edit, delete, Save/reopen; saved package
has no overlay.png or overlay metadata, while base PNG remains byte-identical.
Original overlay retained. Signed Release install/signature/equality verified.
Evidence: work/overlay-delete-20261120/.
Simplified toolbar and Create dialog checked natively with/without an overlay;
signed Release install/signature/equality verified. Model/delete behavior is
unchanged. Latest build log: work/overlay-toolbar-20261120/.
Dialog decision (approved 2026-11-20): one exact 2:1 image with mutually exclusive
Before/After segments above; no transition, fixed image position/size. Open on
After when an overlay exists, otherwise Before; disable After without a result
and select it after successful Generate. Instruction has about 6–8 visible lines
plus scrolling. Apply always uses generatedData, independent of comparison.
Compact layout (approved/verified 2026-11-20): content determines dialog height;
remove the expanding preview container and use 8 pt spacing. Preview reserves
editor/footer/status space on shorter screens. Native check: 1360 x 1352 screen
pixels versus 1360 x 1626 previously, with the same 1272 x 636 image and 144 pt
editor. Before/After and footer fit. Signed Release install/signature/equality
verified; Apply's generatedData path is unchanged. No live Generate/Apply used.
Build log: work/overlay-compact-20261120/.
Signed Release install/signature/bundle equality verified. Native Tuscany check:
on/off changes the image in place; Edit opens the retained Before/After dialog.
No new AI request needed. Current build log: work/overlay-single-20261120/.
Earlier build log and preserved instruction draft: work/overlay-comparison-20261120/.
Image-size contract (Magnus, approved 2026-11-20): reduce input only to the
nearest lower dimensions divisible by 16 with exact 2:1 preserved. Height rounds
down to a multiple of 16; width is twice that (multiple of 32). Already aligned
PNGs pass unchanged. Request that same size/high and store response bytes unchanged.
No PW 50 MB cap, fixed output dimensions, output upscaling or fallback.
Surface service errors directly. Reject wrong-size responses without applying
them or replacing an existing overlay. This overrides earlier 2048/3840 limits.
Display decodes native images off the main actor; old overlays stay unchanged.
Actual Vattenskada check: 8462 x 4231 -> 8448 x 4224, original byte-identical;
multipart matches prepared PNG. Aligned input stays unchanged; wrong output rejected.
PSD uses the smaller common dimensions for all layers to support reduced overlays.
Native PSD export checked with 66 x 33 base / 64 x 32 overlay, enabled and hidden:
64 x 32 canvas, two aligned layers, correct visibility flags. Signed Release
install/signature/bundle equality and native project opening verified.
No live API generation; service acceptance of large aligned requests is unverified.
Evidence: work/overlay-16-20261120/; earlier work/overlay-native-20261120/.

Publishing/export:

- Self-contained HTML supports full native results using tiled WebGL textures;
  size and JPEG quality are independent choices. Original size is the default.
- Publish uses one Filename field accepting relative subfolders and adds `.html`
  if omitted. Destination metadata lives in the project, with normal dirty/Save
  behavior; connections and credentials remain local.
- HTML plus its 640 × 360 JPEG thumbnail are mandatory for Publish. Ask once
  about replacing existing HTML; the corresponding JPEG follows that decision.
  Retain hidden staging, recovery and clear partial-failure reporting.
- Public web base URL is optional; do not guess one from an SFTP server path.
- First-use SSH host keys require approval; changed keys stop the connection.
  Local UserDefaults credential storage was explicitly requested; do not copy
  those credentials into project metadata, documentation or Git.
- PSD export is 8-bit sRGB: base panorama plus separate patch layers, disabled
  patches hidden, adjustments reflected in layers and flattened preview.

## Fixtures, help and verification

- `panos/A`: current night case, five Nikon D80/Sigma 8mm NEFs.
- `panos/B`: daylight case, nine Nikon D70 JPEGs with saved masks/assets.
- `panos/C`: locally added Tuscany case, eight Nikon D70 JPEGs, 8472 x 4236
  saved panorama. Native opening verified 2026-11-19 after granting its C folder;
  old bookmarks refer to the original iCloud location. C is not yet committed.
- These differ from bundled `examples/A–H`; the old Desktop A–Z suite is gone.
  Never infer which scene is meant from the letter alone.
- Magnus explicitly approved public GitHub publication of A/B originals,
  project data and image metadata. Keep case folders intact and use copies for
  experiments. Desktop copies do not synchronize with Git automatically.
- `panos/README.md` explains the snapshots; exclude local bookmarks.
  Magnus opted out of separate checksum manifests (2026-11-19).
- A now saves source 5 as Repair Image. Its stored 8484 × 4242 result matches
  the verified repair-role diagnostic byte-for-byte, including the known hard
  sky seam and 40 uncovered pixels. It is a failing regression case, not a fix.
- Help: https://meg768.github.io/panowizard/ (`docs/`, Pages from main).
- `.github/workflows/examples.yml` packages tracked `examples/` on main pushes.
  Help → Download Examples uses the `Examples` release's `examples.zip`.
  Keep editable originals; do not maintain a second committed ZIP/copy.
- No bundled Open Example Panorama; distribute examples through Help download.

Build success and synthetic tests do not establish visual panorama correctness.
Use real images and inspect geometry, seams and color separately. Preserve
originals and distinguish verified results from hypotheses. The project-specific
recorded preference is automated regression runs only on explicit request;
build checks and focused manual verification remain appropriate. Explicit task
verification requirements take precedence. Real-fixture and local-SFTP test
switches are documented in README/TestSupport; they are not default live actions.

Exposure robustness fix (2026-11-17): `exposureGains` retains neutral gains for
channels with fewer accepted pair equations than imageCount−1 unknowns, or when
`cv::solve` returns false. Supported systems retain the existing SVD calculation,
filtering and gain clamp. Geometry/masks were unchanged. Night A completed at
8500 × 4250; B's 8504 × 4252 engine output matched its pre-change reference with
zero changed pixels/max channel difference 0. This verified exposure robustness,
not defect-free geometry. Reproduction harness/rasters: `work/exposure-fix-20261117/`.

## Open issue: night A zenith/roof seams — 2026-11-19

Target: continuous roof and smooth zenith transition without manual masks.
Magnus accepts correcting an Automatic role choice, but Repair Image must also
produce a usable transition. Investigation was deferred; no motor fix is made.

Verified with original oriented rasters, fresh alignment and no painted masks:

- All five Automatic sources are classified as ring images and show a displaced
  roof edge. The same defect exists in the saved 2026-11-17 exposure render;
  no earlier repair of this particular roof seam has been established.
- Omitting source 5, zenith `2007-09-25 22-50-36.nef`, gives a continuous roof at
  8484 × 4242, 89.190163207% coverage (3,890,366 uncovered pixels).
- Keeping source 5 explicitly Repair Image also gives a continuous roof at
  8484 × 4242, 99.999888855% coverage (40 uncovered pixels). Supplemental
  registration accepts 365/623 matches, but a hard tonal sky boundary remains.
- Removing/changing zenith affects both geometry participation and compositing;
  these comparisons alone do not isolate the cause of the original roof step.
- Instrumenting `contentAdaptiveBlend` at 4096 × 2048 shows a smooth transition
  in `centerWeightedComposite`, while the combined detail-preserving result
  retains a hard edge following zenith ownership. The edge is already present
  before the final `structureResult` mix. Bypassing that mix alone is not a fix.

The remaining tonal defect is localized to tone/detail blending. No corrective
algorithm has been implemented/validated; do not describe this as solved or
blame capture parallax without evidence. Retain ring geometry and photographed
edge detail when testing a focused correction. Do not resume unrelated trials.

Local reproduction material (ignored; not installed product changes):

- `work/A-zenith-seam-20261119/`: diagnostic engine copy, stage dumps and logs.
- `work/exposure-fix-20261117/`: oriented A/B rasters and native harness.
- Chat artifacts: `/Users/magnus/Documents/Codex/2026-11-17/fo/outputs/`:
  `panowizard-A-zenith/`, `panowizard-A-repair-seam/`, `panowizard-exposure/`.
  Repair-seam comparison crops use gamma 2 to reveal the dark boundary;
  they are diagnostic views, not candidate fixed renders.
