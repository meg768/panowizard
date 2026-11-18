# PanoWizard Project and Development Context

Last updated: 2026-11-18.

Write all PanoWizard documentation in English, including future entries in this
file. Keep technical identifiers, filenames, and original quotations intact.

## Little Planet controls approved — 2026-11-18

Magnus approved the redesigned dialog and requested commit, Stockholm timestamp
tag and push. Keep all controls visible in one flat panel: Zoom, Rotation,
Tilt and Center. No Creative controls disclosure, separate Planet/Tunnel
presets or Start with a look section. Use the exact short labels Zoom and Center.
Tilt moves the center vertically from ground-centered Planet (0°) through
sideways (90°) to sky-centered Tunnel (180°); Center moves it horizontally
(0–360°). Rotation turns the image around the selected center. At the two
poles, horizontal center changes and rotation can give equivalent effects.

A large preview replaces the former two equal panes. The full 2:1 thumbnail
and both center sliders are synchronized. Reset restores all defaults. During
slider gestures the cancellable preview renders at 320 px, refining to 640 px
on release. Export dimensions are shown separately. The stereographic renderer,
full-resolution export and stitching engine are unchanged. README and Little
Planet help describe the final controls; the old dialog screenshot was removed
from the help page because it shows obsolete controls.

Seven targeted Debug tests passed again before this checkpoint, covering
projection/orientation, full-thumbnail coordinates and reset. Previous native
A checks verified layout, marker/slider synchronization, independent rotation
and reset. No new full-resolution native export was run for the UI redesign.
Signed Release 1.5 (202611182346) is installed; strict deep signature and
installed/build equality were verified. Latest verified rollback copy:
/Users/magnus/Library/Developer/Xcode/PanoWizard-before-zoom-label-20261118-234732.app
(previous build 202611182342). Original projects were preserved.
Build/install logs: work/little-planet-*/. Checkpoint tests:
work/checkin-little-planet-20261118/tests.log. The local H source-access bookmark
remains untracked and unpublished.

## Exposure fallback checkpoint — 2026-11-18

Magnus requested the normal commit, Stockholm timestamp tag and push workflow.
The current bridge source matches the SHA-256 of the source used for the
verified full-resolution A/B renders and installed Release 1.5 (202611172213).
Four targeted regression checks were rebuilt and passed again; git diff --check
and strict deep verification of the installed app passed. The prior native
A completion and byte/pixel-identical B comparison remain applicable.
The checkpoint includes all pending bridge and context changes. The local
examples/H/panorama.pw/source-access.json contains a machine-specific security-
scoped file-access bookmark and is intentionally left untracked and unpublished.
No Little Planet code was changed; the November 18 discussion explained the
existing center selection, rotation and size controls.

## Signed exposure-fix Release installed — 2026-11-17

Built and installed PanoWizard 1.5 (202611172213) in /Applications/PanoWizard.app
using the normal signed arm64 Release scheme and PanoWizardSFTP DerivedData,
with pinned packages and no package updates. The build succeeded with the
existing actor-isolation warnings. Deep strict signature verification passed;
App Sandbox, bookmarks, selected-file read/write and outgoing-network
entitlements were verified. All 69 installed bundle files match the build.
Executable SHA-256: f9b49927ee543198af0d9edbe0c416bcce95265022f94ef712f7053191d63a47.

Previous installed version 1.5 (202611162309) is preserved at:
/Users/magnus/Library/Developer/Xcode/PanoWizard-before-exposure-fix-20261117-221323.app.
Its complete file manifest matched the old installation, and its deep strict
signature was verified before replacement. To roll back, quit PanoWizard,
move the current app out of Applications, then copy this backup there as
PanoWizard.app. Keep the backup itself intact.

A and its five NEFs were copied to
/Users/magnus/Documents/Codex/2026-11-17/fo/outputs/PanoWizard-A-review/.
The installed app opened that copy, received access to its source folder,
and completed Create Panorama successfully. The native Preview is left open
with “Panorama complete · 100% coverage” and five images. The new rendering
is currently in the open document; it was not explicitly saved to the review
package in this turn. Original Desktop/panorama/A remains unchanged (eight
files checked with SHA-256). No app source beyond the prior exposure fix changed.
Installation log, original-app manifest and metadata: work/exposure-install-20261117/.
User-facing rollback instructions: outputs/panowizard-exposure/installation.md
under the current chat directory. No commit, tag, push or App Store upload.

## Exposure fallback verified with current A/B cases — 2026-11-17

The old A–Z suite no longer exists. Current cases are Desktop/panorama/A
(night, five NEFs) and B (daylight, nine JPEGs with saved source masks).
Only exposureGains in PanoramaBridge.cpp changed: retain neutral gains for a
channel with fewer accepted pair equations than imageCount-1 unknowns, or if
cv::solve returns false. Supported systems retain the existing SVD calculation,
sample filtering, reference and gain clamp. Alignment and mask logic are unchanged.

B's reference was rendered with unmodified code before the edit. Native
stitching-engine output after the fix is pixel-identical: 8504 × 4252,
0 changed RGBA pixels out of 36,159,008, maximum channel difference 0.
The PNGs also share SHA-256 2555b731e14848362b40eaecd2fcd2b6743c5f67dc9ef0d4b3f342dbccdc4c55.
B's 96.322457187% coverage and 1,329,763 uncovered pixels are unchanged.
A completes at 8500 × 4250 with 100% coverage and zero uncovered pixels.
Visual review covered an overview, six perspective views and three unscaled
detail crops: no obvious hard color seams or broad blue/magenta cast in those
views; warm/yellow-green lamplight and gradual sky tone variation remain.
A has no successful pre-change reference or calibrated color target.

All runs use app-equivalent oriented rasters, saved source masks and roles,
fresh alignment and outputWidth=0. Saved retouch patches are separate and were
not composited in these engine comparisons. SHA-256 verification confirms all
29 original A/B files are unchanged. Four targeted executable checks passed:
legacy-exact supported solve, sparse blue with correct green/red, no overlap,
and preserved square rank-deficient behavior. Both engines compiled and native
renders completed; git diff --check passed. Installed app unchanged; no commit/push.
Artifacts and report: /Users/magnus/Documents/Codex/2026-11-17/fo/outputs/panowizard-exposure/.
Harnesses, source snapshot, manifests and rasters: work/exposure-fix-20261117/.

## Desktop panorama A exposure failure diagnosed — 2026-11-17

The five enabled Nikon D80/Sigma 8mm NEFs in Desktop/panorama/A reproduce
OpenCV's under-determined solve exception in exposureGains (PanoramaBridge.cpp).
The app-equivalent oriented rasters pass geometry fitting (five ring images,
median residual 0.108 degrees). Blue-channel filtering (15 < both values < 240,
at least 18 valid samples per pair) retains only pairs 1–5 and 2–5, producing
a 2-by-4 system. Rejections are caused by dark values, not saturation.
The solver checks only for nonempty rows and calls cv::solve(DECOMP_SVD),
which rejects this shape. Green/red retain seven/eight equations.
An isolated diagnostic fallback leaving blue gains neutral completes a
1536-by-768 panorama with 100% measured coverage. This demonstrates the
failure path, not a verified production fix or full-resolution quality result.
No app source, installed app, or original project was changed. Diagnostic
sources, rasters and logs: /Users/magnus/Documents/Codex/2026-11-17/fo/work/panorama-A-diagnosis.
A fix should handle insufficient or disconnected per-channel exposure data
with a safe fallback instead of aborting panorama creation.

## Bundled example removed — 2026-11-16

Magnus removed Open Example Panorama and the bundled Lund Cathedral project.
Example projects are distributed through Help > Download Examples. Existing
source copies in Application Support support any previously saved projects.

## PanoWizard 1.5 App Store archive — 2026-11-16

Build 202611161921 was archived from bbe4c92. The signature, sandbox
entitlements, arm64 architecture, and matching app dSYM were verified.
Xcode Organizer completed Validate App with the same eleven OpenCV dSYM
warnings as for 1.4.
Archive: ~/Library/Developer/Xcode/Archives/2026-11-16/PanoWizard-1.5-20261116-192014.xcarchive.
The release notes are in work/appstore-1.5-whats-new.txt.
Magnus requested the upload. Xcode Organizer confirmed that 202611161921
was uploaded to App Store Connect with eleven symbol warnings. App Review
is still pending submission.

Six screenshots captured from PanoWizard 1.5 were uploaded to the English
(U.S.) Mac product page draft. App Store Connect showed seven screenshots,
including the previous one. The source projects were copied for capture.

## PanoWizard 1.4 published in the Mac App Store — 2026-11-16

Magnus shared the green Ready for Distribution status for macOS 1.4. The
public App Store page and Apple's catalog confirmed that 1.4 was available
in Sweden and the United States. The catalog records a release date of
November 15, 2026 at 19:02 Stockholm time. The submitted build was
202611022209, with automatic release enabled.

## Invert a source mask — 2026-11-14

Invert in the mask toolbar swaps the marked and unmarked areas of the
active Exclude or Include mask on the selected photo. It leaves the other
mask intact. Red takes precedence where the masks overlap. One Undo
restores the previous mask. For a repair image, outline the area to keep
with Exclude and click Invert to exclude the rest when blending.
Invert also works on an empty mask, covering the entire photo with the
active mask color. Inverting again clears that mask.

Signed Release 1.5 (202611142138), with support for empty masks, was
installed in Applications. The signature and binary were checked against
the test build. Builds 202611142133 and 202611142022 were saved separately.

## Switching photos after using the lasso — 2026-11-14

The lasso's mouse monitor could intercept sidebar clicks while the tool
was selected. Mouse capture now follows the active gesture and begins inside
the photo's scroll view. Completing or cancelling a selection resets the
selection, pointer state, and cursor.
An unsaved test project confirmed that Return applies the mask, Escape
discards the selection, and users can switch photos immediately afterward.
Signed Release 1.5 (202611142022) was installed in Applications. Build
202611141940 was saved separately. No automated regression tests were run.

## Source masks apply during rendering — 2026-11-14

Ring and repair images use the entire optically valid image area for
matching and alignment. Red and green source masks are read separately
during rendering and are excluded from the alignment cache. Cache format 8
prevents reuse of older alignments based on red masks. Green prioritizes
marked pixels when choosing seams, and red excludes them from blending.
Both types of images follow the same mask rules.
Repair images once again use the shared blending logic from 77e7900.
Geometric classification and separate alignment for repair images remain in
place. The previous state is preserved in 3d2a33f, and PanoWizard 1.5
(202611132137) was saved before the manual test.

Signed Release 1.5 (202611141940) was installed in Applications from
panowizard-render-masks. The build signature and installed binary were
verified. The automated regression and panorama suites were skipped for
the manual test.

## Selected release for repair masks — 2026-11-13

Signed Release 1.5 (202611132137) was built directly from the worktree and
installed in Applications. It includes a strict green repair mask, narrow
inward feathering, full repair weight in coverage gaps, and a validated
fallback factor per channel. The spatial color field and its local validation
remain separate experiments. The signature, build source, and installed binary
were verified.

## Final feathering test in M — 2026-11-13

The installed experimental build 202611132108 was used to compare widths of
8.33, 12.50, and 16.67 source pixels with the masks, alignment, and color field
held constant. The median widths in the 6606 × 3303 panorama were 10.0, 14.1,
and 18.7 pixels. M showed no clear visual improvement. All three runs produced
zero changed pixels outside green and filled valid edge gaps in the synthetic
test. Retain 8.33 source pixels in M and end this tuning. Images and the report
are under repair-spatial/local-validation/feather-test.

## Local luminance and color validation, separate experiment — 2026-11-13

The second experiment evaluates the median and P90 for both absolute luminance
error and the color residual after removing the luminance component from
clipped RGB. Overlapping neighborhoods determine one smooth weight. A final
check measures the interpolated field and attenuates corrections that make
the error worse. Sample selection remained the same.

In M at 6606 × 3303, the median luminance error in the lower left returned
from 3.16 to the baseline of 1.44. The full luminance improvement remained in
the upper left and on sampled surfaces in the upper right. The improvement
along the bottom edge disappeared. The wooden area with 96 rejected samples
retained a median blue deviation of +28.33. Automatic and Repair Image were
byte-identical at both sizes with zero changed pixels outside green. G and D
matched the current engine, and 19 targeted Xcode tests passed. The code and
results remain separate under work/repair-masks/repair-spatial/local-validation
in the main checkout.

Signed Release 1.5 (202611132108) was built from the separate experiment
worktree and installed in Applications at Magnus's request. The signature,
binary, and build number were verified.

## Spatial color field for repair, separate experiment — 2026-11-13

A bounded Gaussian field of reliable residuals in repair-image source
coordinates was tested on top of the current color factors. The field tapers
where samples are sparse, and channels rejected on separate control pixels
retain the existing correction. With M's saved masks, several parts of the
edge became softer. The lower left had a greater luminance error, and the
upper right still had a wooden area without valid measurement samples.
The experiment code is separate under work/repair-masks/repair-spatial in
the main checkout.

Automatic and Repair Image were byte-identical at 1536 × 768 and 6606 × 3303,
with zero changed pixels outside green. G and D were byte-identical to the
current engine at both sizes. Nineteen targeted Xcode tests and a separate
check of the color field fallback passed in the experiment worktree.

In the lower left, the green and blue channels improved individually, but
their previous negative errors had offset the median red error of +12.
Only four of 537 control pixels had a valid red channel. The luminance error
rose from 1.44 to 3.16. In the upper right, all 96 pairs were rejected for a
chroma difference. Red and green met the channel conditions, while the ring's
blue signal was at most 10 in 93 pairs. Red and green had only eight held-out
samples in two cells. The proposed next test is a smooth local limit on
corrections that increase luminance error, evaluated on the combined field
with the same sample selection. The diagnosis and close-ups are in
repair-spatial/lokal-diagnos.

## Validated fallback for repair color — 2026-11-13

When a local factor is rejected, compare the global and neutral factors
per channel on the same control pixels, using the clipping applied by the
final render. Choose the global factor if either the median or P90 improves
without worsening the other. Use the neutral factor when the results are
equivalent or there are fewer than 20 control samples. The conditions for
accepting a local factor remained the same.

With M's saved masks, the red factor dropped from 1.144 to 1.000, and the share
of clipped red values at full repair weight dropped from 92.3% to 25.0%.
Automatic and Repair Image were byte-identical to each other and to the
diagnostic render at 6606 × 3303. Zero pixels changed outside green.
The upper-right tone difference remained. G at 1536 and 5120 and D at 1536
were byte-identical to the previous output. Nineteen targeted Xcode tests
passed. Before-and-after images are under work/repair-masks/repair-fallback
in the main checkout.

Signed Release 1.5 (202611131831) was installed in Applications at Magnus's
request. The signature, binary, and build number were checked against the build.

## Diagnosis of the color transition in M — 2026-11-13

M's last saved state, with green on #5 and #6 and no red, was reproduced
byte-for-byte at 6606 × 3303. The local red factor of 0.953 failed the P90
check and was replaced by a global factor of 1.144. The fallback increased
the error against the ring and clipped red in 92% of pixels with full
repair weight. The neutral red factor performed better on control samples
and reduced the color cast with the same feathering.

The upper-right wooden surface also has a spatial color difference. The
ring already has very little blue there in the dominant raw source. All
96 samples on that surface were rejected for a chroma difference. Zero
pixels changed outside green. The first proposed change is to compare the
global fallback with the neutral factor on existing control samples. The
diagnosis and images are under work/repair-masks/repair-diagnosis in the
main checkout.

## Color matching and feathering for green-masked repair — 2026-11-13

The separate repair previously received only global exposure correction.
Its color is now matched against the finished ring using even, valid
overlap just outside green. The samples use original values before clipping.
Channel adjustments that lack support on held-out control samples follow
the fallback rule above. Feathering stays inside the valid mask and is
measured in source pixels. Where the ring has no coverage, valid repair
pixels get full weight. Paint green with a margin around the object to replace.

M gave identical results for Automatic and Repair Image at 1536 × 768 and
5120 × 2560, with zero changed pixels outside green compared with the ring
alone. The color difference decreased. A reflection on the table is still
visible. A wider green margin in the test covered the remaining tripod at the
former mask edge, with zero changes outside the extended mask. G produced
byte-identical PNG files compared with 77e7900 at both sizes. D's nadir image
was classified as repair and had no gaps. Eighteen targeted Xcode tests
passed. Test images are under work/repair-masks/repair-feather in the main
checkout.

Signed Release 1.5 (202611131802) was installed in Applications at Magnus's
request. The signature, binary, and build number were checked against the build.

## Strict green repair mask — 2026-11-13

Isolated worktree from 77e7900. Red Exclude controls control-point detection
and the final image for both ring and repair images. Automatic uses the masked
control points for classification. Automatic nadir images are identified
before final ring optimization and aligned against the optimized ring. A
green-masked repair is applied last with a hard edge inside the valid green
region, excluding red. Cache format 7 rejects both earlier and experimental
alignment results.

In the M copy, #6 was classified as a repair in Automatic and Repair Image.
An extra red mask reduced the SIFT point count inside the marked area from
1799 to zero, and #6 still aligned. With no red on #6, both image types
produced identical output, with zero changed pixels outside green at
1536 × 768 and 5120 × 2560 compared with the ring alone. G produced
byte-identical PNG files compared with 77e7900 at both sizes. D's automatic
nadir was classified as repair and D rendered without gaps. The cache from
experimental version 6 was rejected. An automated regression test covers
a fully red-masked repair, and eighteen targeted Xcode tests passed.

Signed Release 1.5 (202611131738) was built from the worktree and installed
in Applications at Magnus's request. The strict/deep signature, binary, and
build number were checked against the test build.

## Mask discussion for Panorama M and G — 2026-11-13

Magnus wanted to align handheld image #6 in Panorama M with Image Type set to
Automatic and choose exactly where it could contribute to hide the tripod.
Matching needs overlap outside that selection as well. The red Exclude mask
could remove that overlap. The green Include mask guides Graph Cut seam
selection. In Panorama G it helps select the overlap without the hand while
still allowing the rest of the source image to contribute.

The proposed toolbar used red Exclude to remove marked pixels, orange Prefer
for the existing seam guidance, and green Include (“True Cut”) to restrict the
image's contribution to the marked region after alignment. The restriction
would need to apply to seam selection, blending, and full-resolution rendering.
Backward compatibility for the mask format was unnecessary. The discussion also
considered a per-image checkbox that would reuse the existing mask. The UI and
the rule for competing pixels inside the mask remained open.

Magnus paused the work. On resuming, the proposal was to check in and tag the
baseline before changing code, then run an isolated test on a copy of M with
the existing mask on #6. Check that Automatic aligns #6, the tripod disappears,
and #6 contributes only inside the mask. Use G to verify seam guidance if the
change goes into the product.

A simpler option came up the same day. Match the original pixels within the
lens's valid area and apply the existing red Exclude mask during stitching.
Red outside the desired area might then suffice without adding a mask type.
The TIFF had the mask baked into its alpha channel before OpenCV read it, so a
test would need to read the source image and red mask separately and compare
alignment and final output. Red may also have prevented incorrect matches
in other projects. The code was reviewed, but this option was untested in M.

Magnus compared M after painting the tripod red in the ring images. Without
#6 there was an intentional gap at the tripod, and the hand by the mouse
looked solid. With an unmasked Repair Image there was ghosting around the hand.
Green on a repair image restricted the first seam selection, but fallback
selection and blending could still use pixels outside the mask. Magnus
preferred visible gaps to coverage from outside a strict mask. A check-in was
requested as a checkpoint before any mask experiment. The Xcode suite passed
with local SFTP. Two older retouch tests were updated to use valid PNG files
and wait for the first render.

## HTML controls the overwrite prompt in Publish — 2026-11-13

Publish asks once if the HTML file already exists. If publishing proceeds,
the existing JPEG thumbnail is replaced automatically. Cancel leaves both
files untouched.
SFTPPublisher always receives both HTML and JPEG. The retired thumbnail
setting is no longer handled. All four file combinations were verified
against local SFTP. Signed Release 1.5 (202611130005) is installed in
Applications.

## Single Filename field in Publish — 2026-11-12

Filename accepts a relative path with optional subfolders. When the extension
is omitted, the app adds .html. A blank field uses the project's default name.
Existing publishPath/publishFilename and previously saved local values are
reused. The same normalized destination is used for HTML, JPEG, and the public
link. Signed Release 1.5 (202611122343) is installed. The app was checked for
saved destinations and rejection of other extensions. The targeted tests
passed with optional local SFTP integration skipped.

## GitHub link in Help — 2026-11-12

Help → View on GitHub appears after Download Examples… and opens the project's
GitHub repository in the default browser. The action was verified in the
installed signed Release 1.5 (202611122212).
The Download Examples label omits the ellipsis as of Release 1.5
(202611122216). Help and README use the same label.

## New project from a finished panorama — 2026-11-12

File → New from Panorama… opens an equirectangular PNG with an exact 2:1
aspect ratio in Preview. The PNG data is embedded in the .pw file, and an
optional project field controls the Images section. Retouch, Preview, and
Export use the existing base panorama. Signed Release 1.5 (202611122052)
was installed. Thirty targeted tests passed. The installed app was checked
for the save prompt, a byte-identical PNG in the project bundle, and
reopening after moving the original PNG. A regular source-image project
still showed Images and Create Panorama.
The Panorama section now shows Preview, Retouch, and Export in that order.
The order was verified with an imported project in signed Release 1.5
(202611122107), installed in Applications.

## Create Panorama under Images — 2026-11-12

The sidebar shows Create Panorama as the last row under Images. Panorama
contains Retouch, Preview, and Export. The placement was checked on a copy of
example H in the installed signed Release 1.5 (202611122030).
Magnus chose this version for further work. The checkpoint also includes PSD
export and example H's saved starting view. H's local security bookmark
remains outside Git.

## PSD export with retouch layers — 2026-11-12

Save PSD… exports 8-bit sRGB at the selected size. The base panorama is the
bottom layer, and each projected retouch patch has a separate layer. Disabled
patches are hidden. Adjustments apply to the layers and to the flattened
preview. Signed Release 1.5 (202611122003) was installed and verified.
Twelve targeted tests passed. A PSD exported from a copy of H in the installed
app was verified with an independent reader at 8592 × 4296, with three layers
including one hidden layer.

## App Store status verified — 2026-11-12

App Store Connect still showed Waiting for Review for macOS 1.4. The latest
status change in the history was the November 2 submission at 23:02
Stockholm time. The public Swedish product page for the app's Apple ID
returned 404. The exact date of any earlier public availability was unknown.

## Handheld example H in Help — 2026-11-06

Example H in the repository has ten JPEG sources, two Exclude masks (one on a
disabled source), two Include masks, and two manual patches. The examples
guide shows red and green masks on the same person in different source
images, using illustrations from the saved masks. The masking guide links to H.
The distributed H project uses relative image references. A local security
bookmark was saved outside the tracked examples.

## JPEG sources in the private test project G — 2026-11-06

In the iCloud desktop, the open JPEG project is located under
`Panorama/G/JPEG/panorama.pw`. PanoWizard 1.5 showed Ready with all ten JPEG
sources. The image ID, settings, masks and saved panorama were preserved.
Project format 10 reads masks and saves panorama as internal PNG files. The
private original project and the G in the repository examples are separate.

## Release 1.5 installed — 2026-11-03

On Magnus' instructions, Release 1.5 (202611030044) was built and installed in
/Applications/PanoWizard.app. Strict/deep signature and identical binary +
Info.plist against the build output verified. Normal launch and the About dialog
verify 1.5, Build 2026-11-03 00:44; the app is left open. Existing actor
isolation warnings and AppIntents metadata warnings remain. Previously installed
1.4 preserved in
/Users/magnus/Library/Developer/Xcode/PanoWizard-before-mandatory-thumbnail-7il5dqc4/PanoWizard.app.
App Store archive and shipped 1.4 intact. No commit or push performed.

## Publishing requires HTML and thumbnails — 2026-11-03

PanoWizard 1.5 has no Generate thumbnail option or AppStorage for that. The old
PanoWizard.Publish.generateThumbnail key is removed when the dialog is opened;
previously false is ignored. Render and JPEG upload are always running; success
is set only after both uploads. Existing 640x360/JPEG80-rendering, camera, file
name, overwriting protection, hidden staging and partial error text unchanged.
Export help and privacy policy updated; opt-in live test now publishes an
HTML/JPEG pair instead of a separate HTML-only mode. Verification: five targeted
tests approved (including true WebKit rendering at two FOVs); a local SFTP test
run without fixture servers. Release 1.5 (202611030035) constructed and
strict/deep signature approved. Existing alerts in PanoWizardApp.swift regarding
actor isolation and AppIntents metadata remaining. Manual testing in built-in
Debug app on available project copy with old false: cross box missing, old key
cleared, HTML + JPEG with UTF-8 name published in 2008; remote JPEG verified
640x360. HTML replacement approved and JPEG replacement discontinued: clear
partial result, JPEG SHA256 unchanged. Both temporary server files deleted and
absence verified. The lock is closed. No installation in /Applications, App
Store action, commit or push included; installed app and uploaded archive 1.4
preserved. The helper's changed locally.

## The following development version 1.5 — 2026-11-02

On Magnus' instructions, the MARKETING_VERSION was raised to 1.5 in both Debug
and Release. Construction numbers are generated continuously with existing
timestamps at construction. Projekt/plist and both version settings verified. No
new build, installation or App Store change is included; installed and
downloaded app continues 1.4 (202611022209).

## Automatic publication authorised — 2026-11-02

Magnus instructed you to run automatic publishing. Automatically release this
version selected and saved for 1.4 (202611022209); verified after reloading
(Save disabled, automatic radio selected). Waiting for Review remains. This
replaces the manual publication setting from the submission. The app can now be
published automatically with Apple's approval. No change in build, audit or land
survey. France continued to rest.

## App Store 1.4 submitted for review — 2026-11-02

Magnus gave his final express approval: Submit. App Privacy read: published
policy URL correct, Photos or Videos, Other User Content and User ID declared
for App Functionality and linked to the user; no declarations changed.
Description of the version post, review text, example URL and selected build
reviewed. Manually release this version selected and saved prior to upload to
respect previous instructions not to release the app. This replaces the older
automatic release setting. Update Review followed by Resubmit to App Review
performed. Apple confirms the Waiting for Review for 1.4 (202611022209), which
was sent on 2 November 2026 at 23:02 Europe/Stockholm. Submission ID:
c5c10c97-d367-4412-a117-a6a3e3cc732d. France continued to rest. No rebuild,
code or version change, release or separate message to Apple. Screenshot saved in
the mission map outputs/PanoWizard-1.4-submitted.png.

## App Store 1.4 ready for the next review step — 2026-11-02

Document commits even 4d4b7eb pushed to main; GitHub Pages built and public
privacy/export verified with SFTP information respectively Save.... Right build
1.4 (202611022209) selected and saved to the version mail, which now displays
Prepare for Submission. Magnus explicitly authorised a paused distribution in
France: the withdrawal confirmed and saved, 173 countries or regions remaining; mainland
China continued to withdraw. Apple states that the change in availability may
take 24 hours. Export compliance saved: standard encryption outside the OS, no
distribution in France. Missing Compliance is gone; TestFlight shows Ready to
Submit for
202611022209. No French documentation uploaded, no Info.plist change. Free Apps
              Agreement verified Active. Paid Apps Agreement is also Active but
              has a separate update available; no agreements approved by the
              agent. The App Privacy Statement has not been changed or verified
              here. Archive, source code, and version unchanged; no new builds. No app
              review or release has been performed. Magnus approves final
              shipment separately. This replaces previously pending compliance,
              build coupling and push status.

## Additional control before App Review — 2026-11-02

The Add Build dialog verifies that 1.4 (202611022209) is optional despite
Missing Compliance. Only one unparalleled field change was used to show the
voter; Cancel/omladdning restored the existing 1.3 link and Save is disabled.
French: Available on App Release. Mainland China: only Not Available. Citadel
has AES128CTR with CCryptoBoringSSL; the archive binary contains aes128-ctr and
BoringSSL type names. OS-only encryption exemptions cannot be adopted. Apple's
export compliance table shows the French declaration for non-OS standard
encryption when France is included; no declaration or landing change. Public
privacy/export/examples/support returns 200, example ZIP byte range
206. Privacy still lacks the SFTP extension: local document commits need to be
     pushed before submission. AI code control: OpenAI information before
     explicit AI Retouch/Try Again; no automatic generation from the dialog
     task. App Privacy in Connect is not re-declared or finally verified here.
     Connects' homepage also showed an updated Paid Applications Schedule; any
     impact on the free app has not been established. No rebuild, review or
     release.

## App Store 1.4 uploaded and processed — 2026-11-02

At Magnus' explicit instructions, the document changes in f5df89f were reviewed
and commissioned; the worktree was verified purely prior to upload. The same
validated archives 1.4 (202611022209) were uploaded via Xcode Organizer,
Uploaded 22:25 Europe/Stockholm. No rebuilds, new archives, source code or
version changes. The SHA-256 before and after of the app binary is identical:
a70fbed2ab9d3fc4dccbdadc005227e61ef30c69c77dda8d851d3191f6b2cbf0. Upload
completed with warnings: only the 11 known OpenCV-dSYM warnings. Connect Build
Uploads shows correct version/build and Complete; TestFlight lists 202611022209
under Version 1.4 with Missing Compliance. The Manage form asks what type of
encryption algorithms the app implements; no answers saved. The building is
finished but not clearly confirmed for App Review selection while compliance
remains. Existing 1.3 link left intact; replace with the correct 1.4 link for
inspection. No Submit/Update Review, release, Git push or tagging performed.
Document commits are local; push is needed for published help. Magnus shall
approve any final dispatch separately.

## App Store validation 1.4 approved — 2026-11-02

Magnus himself approved the new developer agreement in Safari. The account page
shows Certificates/Identifiers/Profiles again and the contract warning is gone.
Validate App was run for the same archive 1.4 (202611022209): Organizer shows
Validation succeeded and Validated 22:19 Europe/Stockholm. Eleven known
OpenCV-dSYM warnings remain; the app's own dSYM matches. The certificate defect
did not recur after an agreed agreement; no separate certificate measure or new
credential was created by the agent. This replaces the previous blocking status.
No uploads or app review submissions were made. The document changes are still
local and uncommitted.

## App Store 1.4 ready, validation blocked — 2026-11-02

File of checked app code ea529a69f48a0b5bf55fa68031bcdf3bc1647770:
/Users/magnus/Library/Developer/Xcode/Archives/2026-11-02/PanoWizard-1.4-20261102-2209.xcarchive.
Version 1.4 (202611022209), arm64; archive succeeded. Strict/deep signature,
sandbox/network.client and matching app/dSYM-UUID verified. The archive weapon
installed in Applications; previous app saved in
/Users/magnus/Library/Developer/Xcode/PanoWizard-before-store-archive-20261102-221049.app.
Validate App running in Xcode Organizer: stopped by PLA Update available (the
latest Program License Agreement must be approved by the account holder) and
lacked Mac Installer Distribution certificate with private key for Team
52A6FA9VB5. The file's Apple Development signature is not a finished
distribution signature. No uploads, dispatches, contract acceptance, commit or
push performed. Magnus logged in; the right page was found in Safari. Existing
Rejected Post 1.3 changed to 1.4; description with SFTP/thumbnail and Review
Notes for Guideline 4.0 saved and verified after reloading. Rejected is
inherited status, no new rejection on 1.4. The older build 1.3 (202610242148) is
still connected and must be replaced with the correct 1.4 build after uploading.
Automatically release this version is verified selected and left unchanged. No
What’s New field was shown; version news is available locally. Contact details
and screenshots preserved. docs/privacy.md now describes voluntary SFTP
publishing and local password storage; docs/export.md uses Save... and collects
Publish help. These amendments need to be published before dispatch. SFTP
contains standard encryption via Citadel/SwiftNIO SSH/SwiftCrypto; respond to
Apple's new export compliance questions based on this, without adopting previous
HTTPS-only exemptions. No exemption flag or App Privacy Statement amended.

## Joint check-in — 2026-11-02

Magnus has explicitly authorized commit, time stamp tag and push for both
PanoWizard and Panorama Browser. The PanoWizard checkpoint collects SFTP
Publish, optional companion-JPEG, saved publishing destination and HTML size,
Save... text and closes after the last window. Temporary building logs and
available project copies in /work/ are ignored by Git and kept locally. No App
Store downloads or submissions are included. Verification: 21 targeted
projekt-/SFTP-/WebKit-tester approved; a local SFTP integration test skipped
because the test server is not running. Release 1.4 (202611022151) built,
installed and verified with strict/deep signature and identical binaries. Normal
start and finish with the shutter button verified again. License files retain
the original's whitespace; other staged whitespace control and credentials
pattern control approved. Previous app saved in
/Users/magnus/Library/Developer/Xcode/PanoWizard-before-checkin-20261102-215125.app.

## Closing after the last closed window — 2026-11-02

App Store layoff for 1.3 (Guideline 4.0): window closure allowed the process to
start without reopening. Reproduced locally. The application delegate now
returns true from the applicationShouldTerminateAfterLastWindowClosed. Existing
savings request and Cmd+Q management unchanged; no new menus or window flows.
Installed signed Release 1.4 (202611022135), strict/deep signature and binary to
the build output verified. Manual tests with available projects: normal
shutdown button completes the process; unspared + Cancel maintains the project;
Don't Save completes; Save writes .pw and ends; interrupted Save dialog
maintains the project. Cmd+Q verified unchanged and with unspared + Cancel and
Don't Save. git diff --check approved. Previous app saved in
/Users/magnus/Library/Developer/Xcode/PanoWizard-before-window-closing-20261102-213617.app.
No app store downloads, changes to versions, commits or pushes.

## Save… i Interactive Panorama — 2026-11-02

Only the Save HTML button has been changed to Save in PanoramaExportView.
Publish..., export functions, dialogues and other UI unchanged. Signed Release
1.4 (202611022122) built and installed in /Applications/PanoWizard.app;
strict/deep signature and installed binary to the build result verified.
Installed Export view checked with available project copy: Save... and
Publish... view, Save JPEG.../Save PNG... remaining. No new test for text
modification; build, exact single-string diff and give diff --check approved.
I'm going back up to
/Users/magnus/Library/Developer/Xcode/PanoWizard-before-save-label-20261102-212324.app.
Previous copy changes were preserved. No one commit/push.

## Recurring macOS boot errors and Mountain Duck — 2026-11-02

Both PanoWizard and Messenger were blocked. The CoreServicesUIAgent (PID 9630)
had 256 open FDs, of which 253 were directories; the system's global file limit
was far from reached. proc/task/cwd/root paths In the Mountain Ducks pic-cat
assembly. It indicates recursive crossover of the mounted server /proc as the
triggering cause. The code signatures on both apps were verified. Targeted
SIGKILL by the locked agent restored normal start; both app windows verified.
The new agent only had three open FDs and no directories. No app code, file
limit or security settings changed. Restricting the server installation to a
regular data catalog avoids exposing /proc to the same crossover; the
installation was not changed here.

## Icon startup blocked by macOS file limit — 2026-11-02

Normal appstart reproduced POSIX 24, too many open files, at translocation.
CoreServicesUIAgent (PID 602) had exactly 256 open FDs (253 directories), while
the total file limit of the system was not reached. The signature was valid, and
there was no new app crash. Normal SIGTERM did not help; directed SIGKILL by the
CoreServicesUIAgent itself allowed macOS to restart the process. Then the normal
appstart /Applications/PanoWizard.app opened and its Untitled window was
verified. No product code, file limit or security settings were changed.

## Local release building — 2026-11-02

At Magnus' request, the current worktree was built as signed Release 1.4
(202611020050) and installed in /Applications/PanoWizard.app. Strict/deep-
signature, installed version and build number and binaryhash against the construction
result verified. Previous app saved in
/Users/magnus/Library/Developer/Xcode/PanoWizard-before-build-20261102-005045.app.
No product code was changed and no commit/push was made.

## Interactive Panorama: Original and saved size selection — 2026-11-01

Magnus requested Original as the default for Interactive Panorama Size and that
the selection be saved in the app. The size is now in native
AppStorage/UserDefaults with PanoWizard.HTMLExport.size key, standard Original.
Divided between projects or windows and retained between starts; Save HTML and
Publish use the same choice. JPEG quality, port size and project format
unchanged. Help up to date. Signed Release 1.4 (202611012218) built and
installed in Applications; strict/deep signature, building number and binary hash
verified. Previously on
/Users/magnus/Library/Developer/Xcode/PanoWizard-before-original-html-size-20261101-221923.app.
No new tests for the standard API setting; give diff --check approved. No one
commit/push.

## New local release building — 2026-11-01

Magnus requested the construction of current code. Signed Release 1.4
(202611012204) built and installed in Applications according to saved routine;
strict/deep signature, build number and binary hash verified. Previous app saved
in
/Users/magnus/Library/Developer/Xcode/PanoWizard-before-build-20261101-220706.app.
The app was used during the installation; open projects were left behind and the
new building is used after restarting. No product code changed, no new tests, no
commit/push.

## Publishing path and file name in the project file — 2026-11-01

Magnus requested that Path and Filename be saved in the project itself.
PanoProject now has optional publishPath/publishFilename in project.json.
Existing projects without fields continue to be read as format 10. The dialogue
prioritizes project values; previously locally saved values are copied to the
model when the dialog is opened if the project fields are missing. No new
Path/Filename is written to UserDefaults. Publish is updating the destination
and modifiedAt of the model. Normal Spara/Spara that writes the values in .pw
and the change gives normal unspared status. Close continues to throw
unpublished field changes. Connection and password remains local. 16
projekt-/pakettester passed, including real skrivning/kopiering/ reopening,
older JSON without fields and that credentials are not in the project. Help up
to date. Signed Release 1.4 (202611012203) built and installed;
strict/deep signature, building number and binary hash verified. Previous app
saved in
/Users/magnus/Library/Developer/Xcode/PanoWizard-before-project-publish-destination-20261101-220412.app.
No commit/push.

## See also: — 2026-11-01

Only visible link text in the success message changed to View Panorama. The
actual URL and its native opening in the default web browser are retained;
without a configured base address only Uploaded successfully appears. No other
product changes. Signed Release 1.4 (202611012140) built and installed;
strict/deep signature, building number and binary hash verified. No new tests for
the text change; give diff --check approved. Previous app saved in
/Users/magnus/Library/Developer/Xcode/PanoWizard-before-view-panorama-label-20261101-214046.app.
No one commit/push.

## Public Base URL valfri — 2026-11-01

Magnus only requested that the Public Base URL be optional. Tom or just
whitespace does not provide any URL validation and regular SFTP publication with
the message Uploaded successfully. The specified address is validated and
provides the same clickable link as before. Fields, savings, other UI and SFTP
flow unchanged. Success is stored separately from the selected URL so that even
unlinked uploads are confirmed. Targeted tests for tom/whitespace, specified
URLs, encryption and saved data passed (four run, SFTP integration test
deliberately skipped; transport code unchanged). Help up to date. Signed Release
1.4 (202611012107) built and installed in Applications; strict/deep signature,
building number and binary hash verified. Previous app saved in
/Users/magnus/Library/Developer/Xcode/PanoWizard-before-optional-public-url-20261101-210819.app.
No one commit/push.

## Click on the webpage in the publication confirmation — 2026-11-01

In Magnus' new instruction, there is once again a single saved Public Base URL
field in the connection form. It is validated before publication and
automatically saved with the connection. Older saved configurations without the
field retain their credentials. No reset save connection, copy URL, webpage
dialog or extra button. Existing Successful row shows Uploaded successfully.
followed by a clickable URL; native SwiftUI Text/AttributedString-link opens the
default web browser.

The URL consists of base address + optional path + filename. Each added
component UTF-8/percentkodas separately; the existing encoding in the base
address is retained. HTTP/HTTPS is required; queries, fragments and credentials
in the base URL are rejected. No guesses from SFTP-host/katalog. Rendering
engine, HTML generator and upload code intact. Ten targeted tests via normal
xcodebuild test start approved, including Swedish characters, intermediate,
#/?/%, empty search path, multi-level search path, ending slash, already coded
base address, persistens/migrering, existing HTML export and local SFTP. The
previous LaunchServices error did not occur in this test run. Signed Release 1.4
(202611012057) built and installed in Applications; strict/deep signature,
building number and binary hash verified. This is the maximum amount of time
required to complete the test.
/Users/magnus/Library/Developer/Xcode/PanoWizard-before-publish-url-20261101-205818.app
I'm not going to. The app started normally; test servers shut down. No one
commit/push.

## A single Publish dialogue with an optional survey path — 2026-11-01

Magnus confirmed successful upload to its server and then ordered the
simplification: always visible connection fields, optional path and separate
filename; only Close/Publish. Save Connection, connection interface and entire
Web Link/ Copy URL/Open in Browser removed. Publish validates and saves the
connection automatically; Close does not save field changes. The file name and
path are stored locally per project ID; the existing file name standard is
maintained. Older saved connection with publicBaseURL can be read without losing
credentials; that property is ignored.

Path is a relatively existing Remote Directory. Missing directories are created
in stages, including 2019/Toscana and A/B/C/D; existing directories are reused.
Absolute pathways, . and .., backslash/kontrolltecken are rejected. The
canonical search paths of the server are checked to stop simple thoughts outside
the basic catalog. There's still an existing overwriting issue. HTML generator
and rendering engine are unchanged; help updated.

Nine targeted tests passed with the same built-in test package directly via
XCTest: legacy settings, hostname, search paths, existing HTML export and real
local SFTP with creation and reuse of multi-level catalogs, file name and
received bytes, declined or accepted overwriting, denied catalog rights, file in
catalogue path, simple off-base thinking, wrong passwords and unavailable port.
Test servers down. Normal xcodebuild test start was blocked by LaunchServices'
"Too many open files"; the same error was reproduced with open for BOTH the old
installed app and Debug. No system settings changed and no product code adapted
to this environmental error.

Signed Release 1.4 (202611012026) built and installed in Applications;
strict/deep signature and binaryhash verified. Launched directly through the
app's binary via LaunchServices. Manual control of the Publish dialog itself
remains. Previously on
~/Library/Developer/Xcode/PanoWizard-before-publish-path-20261101-202843.app. No
commit, no push or Apple upload.

## Simplified SFTP configuration — 2026-11-01

Magnus asked for simplification and questioned the Public Base URL. The web
address is now optional under Web Link (Optional); SFTP uploading does not
require it. No web address is guessed from the server's catalog. Without URL,
Uploaded successfully appears without Copy URL/Open in Browser. Existing saved
web addresses are still functioning. Hostname accepts included http/https-adress
and is normalized to hostname at Save Connection and connection. HTML generator
and rendering engine intact. Nine targeted tests pass, including uploading
unpublished URLs to local SFTP servers and normalising hostnames. Help up to
date. Signed Release 1.4 (202611011955) built, installed in Applications and
started according to the build routine; strict/deep signature and binaryhash
verified. Previous app saved in
/Users/magnus/Library/Developer/Xcode/PanoWizard-before-optional-web-link-20261101-195608.app.
Test servers down. No one commit/push.

## SFTP building installed — 2026-11-01

At Magnus' request, the signed Release was built. 1.4 ( 202611011943 ),
installed in /Applications/PanoWizard.app and started according to a conserved
construction pattern. Strict/deep- Signature, installed building number and
binary hash against the build output verified. Previous app saved in
~/Library/Developer/Xcode/PanoWizard-before-SFTP-20261101-194411.app. No new
product changes, tests, commits or pushes in this construction cycle.

## SFTP publishing of interactive panorama — 2026-11-01

Magnus ordered Publish... next to Save HTML...: a locally saved SFTP connection
(host, port, username, password, directory, and public base URL), editable settings, file
name, busy indicator, overwriting query and Copy URL/Open in Browser.
Implemented with exact Citadel 0.12.1 and version-locked transitive Swift
package; licenses included. Using existing FilePanoramaExporter, no other HTML
generator or modification of the rendering engine. Passwords are stored in local
UserDefaults without Keychain as expressly required. The first SSH server key
must be approved and saved; the modified key stops connection.

The old CONFIGURATION_BUILD_DIR overwriting collided verified with the resource
bundles of the Swift package. Removed in favor of Xcode's usual DerivedData;
built outside iCloud. README updated; the old Build link can show older apps.
Signed Release build and strict/deep signature approved in
~/Library/Developer/Xcode/PanoWizardSFTP/Build/Products/Release/PanoWizard.app;
sandbox and network.client verified. No installation or Apple upload. Eight
targeted tests approved: first local configuration, readback and replacement of
saved credentials, URL encryption, existing HTML export and SFTP integration
against local Paramiko servers with ECDSA key (new file, declined or accepted
overwriting, wrong password, unavailable port). Received file content checked.
Temporary scheme change of testers restored; integration test explicitly
requires PANOWIZARD_SFTP_TEST=1 and test servers at localhost:22229;
reproducible fixture is available in PanoWizard/TestSupport/sftp_server.py
(Paramiko for development only). The test server is down. Real web servers,
manual review of the publication dialog and validation of the App Store remain.
Older RSA-only servers provided algorithm negotiation errors; the modern ECDSA
test server functioned without weakening protocol settings. No one commit/push.

## Check-in of recovery context — 2026-11-01

Magnus requested check-in of all pending changes. Only the context of Restore
and Release 1.4 (202610310014) is included; no product code changed. Review, git
diff --check and credential check approved; main/origin/main sank before commit.
No new build or test is required for the documentation. Commit, new Stockholm
time stamp tag and push of main as well as the new tag included.

## Restored building before absolutely green — 2026-10-31

Magnus interrupted the experiment with absolutely green in the final rendering.
Code and test appendix restored to Before-red-light-green-light (de834e7). On
the following instruction, signed Release 1.4 (202610310014) was built; build
and strict/deep signature passed. 0 px extra feather and D-fix left. No
installation, commit or push. Applications continued 202610302154.

## Outside-feather 50 px: verified protection but interrupted attempt — 2026-10-30

Legoland Hell, according to Magnus, is in Desktop/Panorama/F and G. Tested
unilateral linear 50 px-feather in PanoramaBridge.cpp; existing seam and tone decisions
are retained. Include was locked at native projection to a valid corrected
source, without another is called blendCorrection; later valid Include won
overlap. Full resolution with identical raster, masks, and locked registration caches:
F 8402×4201, 4 548 474 green pixels; G 8580×4290, 666 222 green pixels. All
green pixels are exactly equal between new 0/50; outside green new 0 pixel-like
with old 0. The radiometric triangles of the sleep valve and final rendering are
identical F/G/D. D 8410×4205: both ends complete, the D-fix left. But G got a
clear new ghost image outside green on the bag and softer double subject
boundaries: although out-of-the-box blending protects green but still blends
moving subjects outside the mask. The requirement for no new ghost images is not
met. No adaptive method added. 22 existing Swift tests as well as new
independent native controls for 0/50, size, Include isolation and overlap and
Exclude passed; signed Release 1.4 (202610302249) built but NOT installed. A
wasn't tested after the G finding. The entire product test and related
product documentation and test additions restored to HEAD 894b0fa; only this context
remains. App installed continued 202610302154 (0 px). Reusable patch and
before-and-after images are available in the chat
2026-10-30/fo/outputs/outside-feather; test in work/outside-feather. No changes
to the original panorama, none commit/tagg/push. Do not repeat the same solid
feather with unchanged masks in G and expect no ghost images. Magnus
subsequently requested a check-in of the documentation; no product code is
included.

## Check-in with extra feather off — 2026-10-30

Magnus requested check-in of all pending changes: fixed linear feather
implementation with width 0 px and zero handling as well as this context. D's
verified seam fix is unchanged. Currently installed Release is 1.4
(202610302154); build and strict/deep signature approved. Final verification, git
diff --check and credential check approved; main/origin sank before commit.
Previous 32 px rendering and masking controls documented below; no separate
rendering or new test suite for 0 px performed at check-in. Commit, new
Stockholm time stamp tag and push of main and tag included.

## Extra linear feather set to 0 px — 2026-10-30

Magnus requested zero parts and a new build. The width constant is 0.0; a
necessary zero management in analysisFeatherWeight returns ownership × edgeFade
at featherWidth ≤ 0 and avoids division by zero. Other code hashed against the
same implementation as before. Existing ton-/blendkomponenter shall be
maintained; the additional linear transition shall be discontinued. Signed
Release 1.4 (202610302154) installed in Applications and started;
strict/deep signature and binary hash against build outputs approved. 100
px app saved in work/m-fixed-feather/PanoWizard-100px.app. No commit, tag or
push.

## Published 1.3 by Magnus — 2026-10-30

Magnus is now referring to its published App Store version 1.3; the previous
Waiting for Review note is historic. The exact date of publication, Apple
building number and uploaded SHA code are not saved here. The comparison with
later development is based on the Git base 7adbccd (version to 1.3). In
comparison, local 1.4 (202610302114) was run with a fixed 100 px-feather.

## Fast feather down to 100 px — 2026-10-30

Magnus requested 200 to 100 px. Only the width constant changed; all other C++
hashes verified against the same 32 px base as before. Signed Release 1.4
(202610302114) built and installed in Applications; strict/deep signature and
binary hash against the build result verified. The app was shut down normally
before installation and restarted. 200 px version saved in
work/m-fixed-feather/PanoWizard-200px.app. No commit, tag or push.

## Fast feather modified to 200 px for own testing — 2026-10-30

On Magnus' instructions, only 64.0→200.0 in the feather-width constant was
changed. Other C++ verified identical to previous implementation via blob
85112447... after reverse constant change. Signed Release 1.4 (202610302109)
built, installed in Applications and started. Strict/deep signature and installed
binary to the build result verified. 64 px app saved in
work/m-fixed-feather/PanoWizard-64px.app. Magnus is manually testing for a new
Create Panorama. No commit, tag or push; no new rendering tests.

## Fast feather modified to 64 px for own testing — 2026-10-30

On Magnus' instructions, only the constant 32.0→64.0 was changed in the call to
analysisFeatherWeight. All other C++ is byte-identical with the 32 px
implementation (verified by reverse constant change to blob 85112447...). The
D-fix remains. Signed Release 1.4 (202610302103) built and installed in
Applications, strict/deep signature and binaryhash against the build result
verified, app started. 32 px app saved in
work/m-fixed-feather/PanoWizard-32px.app. No new rendering tests; Magnus will
test M/A/D manually after Create Panorama again. No commit, tag or push.

## Exactly 32 px feather reintroduced and installed — 2026-10-30

Magnus requested the same implementation for his own testing, without further
experimentation. Reapplied saved work/m-fixed-feather/experiment.patch; C++ blob
is exactly 851124479560a9dd6201ca83a98a8ba082d80aa9, the same as the experiment.
D's boundary verified unchanged. No new UI or other improvements. Release 1.4
(202610302053) built, strict/deep signature verified, installed in
/Applications/PanoWizard.app and started. Installed binary hash identical to the
build output. The previous D-verified app is backed up in
work/m-fixed-feather/PanoWizard-before-install.app. No new rendering tests;
previous M/D/A- and mask controls are reused. Panorama needs to be recreated to
show the feather. Source code and context unchecked; none commit/tagg/push.

## Revised visual assessment of A's feather test — 2026-10-30

Magnus reviewed showed before-and-after crops and does not assess the difference as
a deterioration for a human. It's ceiling decoration, not text/skylt. The former
visual underrepresentation of A by the assistant was too strict and should not
be treated as a verified practical quality regression. Large maximum pixel
differences alone are no basis for such a conclusion. The measured improvement
of M and the full range of D remain as test results. The production code is
still restored; no new implementation/installation has been executed.

## Although 32-pixel feather for M restored — 2026-10-30

Magnus resumed work for a separate, time-limited feather trial. Tested linear
weight from signed distance to existing ownership, total 32 px (±16) at rendered
size. Existing masks and sound components shall be retained; no smoothness
control, recording, radiometric or sleep reminder. Temporary change:
analysisFeatherWeight and viktackumulering/utstorlek in
analyzePanorama/renderPanorama (+35/−5 rows). M's 314 wood samples improved
median 15→6, p90 27→10/255 at native-rendering 6614 × 3307; polygon edges
visually softer. D's full range at 8410 × 4205. The A-control at 2048 px showed
mjukare/suddigare roof and sign contours (maxdiff 127/255), which was counted as
deterioration and triggered recovery under Magnus's terms. Ownership and
radiometric logs identical to M/D/A. Masking weights exactly 0 for invalid
pixels; magenta sentinels outside the masking gave maxdiff 0 in fixed blend. The
entire production code has been restored by default; the D-fix remains. No app
installation, no commit or push. Substrate and patch in work/m-fixed-feather.
Stop after testing; no further attempts without further instruction.

## M finished for the evening — 2026-10-30

Magnus finished the job. No safe improvement has been identified. Both
experiments below are completely restored; do not repeat them without new
hypotheses and new evidence. Previous proposals on these trials are therefore
overused. Final control: all production codes are identical to those checked
76b747d; D's verified seam fix remains. At the time of completion, only
intentional documentation remained in CONTEXT.md; no construction, commits or
push was carried out at that time. Magnus then requested check-in of the
documentation with new tag and push.

- **Wide blending within Exclude:** mixed seamDetailed/broad with existing
  smoothness and kant-/konfliktskydd. The same 314 wood samples in M: median
  15→14, p90 27→26/255; the scales remained clear. Interrupted due to
  insufficient power. D is pixel-dependent; A maxdiff 1/255 at 2048 px. Excluded
  warpixels made no contribution to the sentinel control. Subject:
  work/m-blend-experiment.
- Locally dimmed radiometry:** 23 temporary rows in applySeamLocalRadiometry,
  field weight headroom/(headroom+the part of the radiometer) before existing
  confidence/korridor. The ceiling ±12/±24 and all safety limits shall be
  maintained. M's median 15→16, p90 27→31/255; 62 newly added measured channel
  values in owned source areas. Disconnected for poor performance and loss of
  information. D's range whole, maxdiff 3/255; A maxdiff 4/255 at 2048 px, no
  apparent deterioration in overview. Subject: work/m-local-damping.

Common: identical images, masks and registration cache; unchanged car title.
None of the experiments were installed. The installed app is still D-verified
1.4 (202610301723), with full resolution rendering.

M pixel-based (6614 × 3307), cache 4eb36269 ... Local residual differences at
the seams of the wood are 35/43 levels in the major RGB channel. Par 3–6 is
rejected due to a measured correction field (2884/265446 = 1,086 % >1 %), not
directly measured 0/255-klippning. However, isolated full correction risks
cutting 163 channel values with information to black in image 6's own areas.
Therefore, simply letting the pair through or raising the safety limits is not
safe. Analysis data: work/m-tonal-analysis and work/m-radiometry-analysis.

## Check-in of D's sewing fix — 2026-10-30

After Magnus verification, all pending changes were requested to check in: the
17 C++ rows of the seamfix and this context. Release 1.4 (202610301723),
strict/deep signature, isolated D regression and short A/Toscana-kontroller
approved as follows. Final verification, git diff --check and targeted control
of credential patterns approved; main and origin/main sank before commit. No
further construction or testing sites were needed. Commit, new tag in Stockholm
time and push of main as well as the new tag are included in the request.

## D Verified by Magnus and Causal Analysis — 2026-10-30

Magnus confirms that installed 1.4 (202610301723) is functioning as before.
Reasonable cause for D: a90d020 simplified to joint selection and removed the
specific candidate limitation for nadir/Repair. The handheld nadir could then
own the nearby racks outside the Include; switching to the displaced image of
the rings gave rise to the offences. The same geometry and masks failed before
the isolated seam fixture and the entire shelf after it, with unchanged blending
code. The full resolution return is maintained. D with hand held nadir and
nearby rack is a concrete regression case for future changes in
seam selection and blending.

## Test construction of the range limitation D — 2026-10-30

At Magnus' request, the signed Release 1.4 (202610301723) was built with the
experimental modification below and installed in /Applications/PanoWizard.app.
Construction, strict/deep code signature and installed binaries against
build outputs approved. The app started. Previous installation copied to
this chat work/d-seam-experiment/PanoWizard-before.app. Original projects
untouched; D needs Create Panorama again to show the change. No one commit/push.

## Experimental area limitation for D — 2026-10-30

Isolated before-and-after test with identical RAW ratings, Include and locked cache
confirmed the range regression in a90d020. At Magnus' request, only the seam
candidate limitation was reintroduced in analyzePanorama: role 2, or role 0 with
at least three horizontal views (< > > 0,65 ) and nadiraxel-Y < − 0,8 , uses
protectedMask before preferCentralCoverage. Two rows keep the rendering rolls
submerged when overlapping images are filtered. A total of 17 new C++ rows;
blending, registration and inclusion semantics unchanged. The change is
experimental.

D reversed 8410 × 4205 with the same indata/cache: reference pixel-dimensional
with saved original, both frames coherent after modification, 100% coverage.
Nadir ownership outside green at 4096 analysis decreases 1405682 → 152 pixels.
Short A and Toscana comparison at 2048 px: unchanged alpha and coverage, altered seam
and tone transitions on the ground, no obvious new geometrical errors in
overview. Only standalone test engines compiled; installed app unchanged. git
diff --check approved. No original projects changed, none commit/push. Subject
to this chat work/d-seam-experiment. Stop after the test, according to Magnus.

## Short regression analysis of Desktop/Panorama/D — 2026-10-30

The line breaches are shown in save result.png (8410 × 4205), not just in
Preview. Five NEFs, green mask in the last picture, no red masks. The project
cachehash verified to fc2af58a...; four horizontal views and the last optical
axis Y −0,999 meet the previous automatic nadir rule. The strongest candidate is
a90d020 (13/10), which removed the nadir/fillOnly restriction to protectedMask at
seam selection and restriction in wide blending. Registration unchanged in the
last two engine changes; cffc2ca changed full resolution rendering and 93bc378
radiometry and blending. No A/B-rendering performed, cause unproven. Next proposed
step: isolated comparison before and after a90d020 with the same geometry and masks,
as well as inspection of vehicle roofing at the racks. No code, mask or project
file changed, nothing build or test bundle. Magnus wants a stop after the report.

## Green mask and Repair Image in M — 2026-10-30

Magnus wants image 6 in Desktop/Panorama/M to only replace the green-painted
area. Savings projects confirm fillOnly in Figure 6 and Green Mask. Current
Include prioritizes the area of seam selection but does not restrict other uses
of the image; Repair Image refers to separate registration without controlling
the ring geometry. No product code or panorama file changed during the review.

Magnus tested red mesh outside the replacement area and showed that image 6 then
hopes over with Insufficient overlap matches. The code review confirms that red
masks are applied before extractFeatures and removes registration documents; the
advice to redmask the rest is therefore insufficient. Proposed direction for
Repair Image with green mask: keep the registration document but limit the image
contribution when combined to green. Not yet implemented or tested.

## Check-in of the blending fix — 2026-10-30

Magnus requested check-in of all pending changes: only the blending fix in
PanoramaBridge.cpp and this context. The sidebar is fully restored to the
previous commit; the button error is unresolved. The latest signed Release
building is 1.4 (202610300018), installed with the original side panel. Bygge,
strict/deep code signature and give diff --check approved. Practical
verification covers Tuscany and example A; the whole A–Z is not the review. No
automated tests conducted. Commit, new Stockholm time stamp tag and push to main
are included in the request. The error rule is also found in the common global
AGENTS.md of iCloud.

## Troubleshooting rule — 2026-10-30

Magnus wants to avoid another round of prolonged, speculative button debugging.
Reproduce the problem and distinguish verified facts from hypotheses before
changing the product. Test one focused hypothesis with a clear expected outcome.
If the attempt does not support the hypothesis, revert it and return to
diagnosis. Avoid a succession of speculative code changes, rebuilds, and
restarts. Extend the task to layout or other behavior only when the evidence
calls for it. If progress stalls, report what is known and what remains unknown.

## Disrupted button search and side panel restored — 2026-10-30

Magnus stated that the problem appears to occur after masking. In an isolated
A-copy, lasso → finished mask → missing side button action could be recreated,
while Panorama → Create started. The generation has been interrupted. The
previous preventive amendment below did not resolve this. Trials with row
identification and separate placement did not provide sufficient verification of
normal muscle clicks. Magnus objected to the extended
the debugging and layout change. Attempts stopped; PanoramaSidebar.swift restored
to full HEAD. No button and layout changes shall be counted as unresolved or
retained. The blending fix in C++ is still there. The unspent mask of the
control copy is discarded; the original design remains intact. Nothing checked
in.

## Intermittent Create-knapp — 2026-10-29

Magnus reported that the Create Panorama of the sidebar sometimes doesn't
respond, while Panorama → Create works. Both use the same canStitch and
stitch(); the side button is in List(selection:). The original intermittent
error could not be recreated in an isolated A-copy. Minimum preventative change
in PanoramaSidebar.swift: selectionDisabled() on the action row and
allowsWindowActivationEvents() for the click that activates an inactive window.
Requirements on bildantal/phase and the menu command are unchanged.

Release build and signature and git diff --check approved, installed version 1.4
(202610292352). Practically verified: empty project does not start Create; the
sidebar opens the retouch confirmation from Preview, Retouch and source image,
including a coordinate click on the left side of the button. All confirmations
have been cancelled; no new generation or modification of original projects.
Check copy closed without saving; the app is on Untitled. No automated tests
performed and no commit/tagg/push. Continued use needs to confirm that the
intermittent behaviour has disappeared. The question of normal or toned buttons
was asked asynchronously; no response came before this note.

## Softer colour transition in exclusion masks — 2026-10-29

Magnus approved the proposal from the Tuscan investigation. Only
PanoramaBridge.cpp has been modified: the mesh protector uses existing
seamDetailed (small source detail plus low frequency, consistency-limited color
correction) instead of just narrow. No wide image detail or minimum feathers are
reproduced in the protected area; the calculation continues to use only valid
source pixels. Local radiometry allows p90 residues above 12 only if the
original p90 error is at least halved. Other media, medium, substrate and
cutting requirements are unchanged; no subject-specific code.

Practical rendering with the same Toscana geometry and seams yields 8486 × 4243,
the same coverage and all eight source masks byte-for-byte and pixel-for-pixel equal in
analysis. The local colour jump of the mask canton decreased 22→4/255 with the
same 53 edge samples. The vertical color seam remains partially.
Before-and-after renders of example A at 4096 px was examined manually: the
photographer continued masked, no visible return, identical alpha and coverage. No
automatic regression tests performed.

Signed Release build succeeded, installed as 1.4 (202610292319), strict/deep
code signature and git diff --check approved. The app opened an isolated Toscana
copy with the new full-size result to Preview/Ready, all eight source images and
existing red mask. The verification copy is open in this chat
work/toscana-blend/verification/Toscana; all 12 files of the source folder are
hash-verified unchanged. The original project needs Create Panorama again to get
the new blend. No upgrades, commits, tags, pushes, archives or Apple uploads.

## Investigation of blending in Toscana/På utflykt — 2026-10-29

Eight JPEG sources and panorama.pw in iCloud/Mina filer/Panorama/2006/Toscana/På utflykt were reviewed unchanged. The saved panorama 8486 × 4243 was
pixel-drivenly recreated with the current engine, the same ImageIO masked TIFF
and existing alignment cache 09aede8d.... The rounded edge of the blue-green
stain follows the red mask on the nadir image 13.24.55; a replacement stone
laying comes from 13.24.27. Two interactive rules were verified:
contentAdaptiveBlend restores narrow near userExclusions and closes tonal
equalization; local radiometry for image pairs 2–7 is rejected despite median
9→3,787 and p90→13,567 because the absolute p90-limit is 12. Exposure also
varies between sources (f/7,1–13 at 1/250s). Separate diagnostics using the same
geometry and seams show that permissible correction plus equalization reduces
the local color jump along the mask edge from 22 to 4,5/255 (median largest RGB
channel, 53 edge samples). Loose seams remain partially; this is not a finished
or generally verified fix. Recommended direction: keep away the masked content
but allow safe low-frequency colour matching and assess improvement of
radiometrics locally. No app code, installation or project file modified; no
regression tests performed. Diagnosis and comparison can be found in this chat
work/toscana-blend and outputs/.

## Check of documentation after check-in — 2026-10-29

Check-in cffc2ca and tag 2026-10-29-21-32 are pushed. The GitHub workflow for
the example package and Pages were both successfully completed. The main changes
in aid followed this commit. Following Magnus's question, Getting Started (seven
examples and HTML-storlek/kvalitet), README's quality selection as well as G's
current standard prompt and F's comparison with the JPEG examples were
supplemented. New screenshots from the installed app show the export's separate
HTML quality and G's JPEG sources. The images were scanned visually; local
documentation links and image references and git diff --check approved. A/G-projekten
was opened without saving; no changes to examples/. No app code modified or new
build needed. All 129 local links and image references are controlled. Magnus then
requested check-in of the additions with commit, new timestamp tag and push to
main.

## Approved sample size and check-in — 2026-10-29

Magnus agreed to use the 12288 × 6144 variant that saved panorama image in
example G and complete check-in. result.png is now 97191998 byte (92,7 MiB),
below GitHub's file limit. Source-JPEG retains 4000 × 6000; image references,
retouches and adjustments are retained. Help and example readME indicates the
saved sample size. The full-size original is backed up locally outside the
repository. This does not change the Create and project format of the app.

Check-in includes all pending changes, including high resolution Create,
Preview/retusch/export, HTML size and JPEG Quality, help as well as G's JPEG
sources, new patches and deleted HTML exports. No Git LFS is introduced. The
most recent signed Release is 1.4 (202610291952), previously practically
verified. Commit, new Stockholm time stamp tag and push to main are all part of
Magnus' approval. Final control: G opens to Ready with all six JPEG sources and
retouch. All pending files are under 100 MiB; 69 documentation links, patch and
source references, installed code signature and git diff --check are accepted.
No automatic regression tests were performed at this check-in.

## Measure PNG options for G — 2026-10-29

To investigate the GitHub barrier, separate candidates were created without
altering G's original. Loss-free OpenCV PNG compression level 9 with adaptive
filters yielded 165546270 byte (157,9 MiB) at 16914 × 8457; identical decoded
pixels were verified. That's not enough for the GitHub file limit. A scaled
candidate 12288 × 6144 with the same PNG encoding became 97191998 byte (92,7
MiB). Reduced scaling reduces the resolution; JPEG sources retain 4000 × 6000.
Suggestion: use the 12288 variant only as a saved sample image in G and keep the
full-size original locally. The proposal was subsequently approved and applied
in accordance with the section above. Original exchange identity and local
backup verified; nothing checked in.

## JPEG source images in example G — 2026-10-29

On Magnus' instructions, G's six NEF sources were replaced by
DSC_0442.JPG–DSC_0447.JPG. JPEG quality of 98%, unchanged oriented measurement
4000 × 6000; ImageIO uses the same oriented decoding as the source image reading
of the app. The camera, lens and photography time were verified after coding.
The total size of the sources decreased from 194,8 MB to 43,9 MB (77,5 %). The
NEF originals were backed up locally outside the repository before being removed
from G.

Only image URLs and modifiedAt were changed in G's project metadata; image ID,
rotations, measurements, retouches and adjustments are retained. The existing
folder bookmark also covers the JPEG files. Save panorama, patch images, patch
masks and HTML are unchanged byte for byte. Help and example readME now
describes JPEG in G; F retains NEF. The app opened G with all six JPEG sources,
source image view and Preview/retusch to Ready. No new generation or app code
changes were made.

The source change does not resolve the check-in barrier: G's panorama/result.png
is still the 180988415 change (172,6 MiB). No commits, tags or pushes were made.

## Check-in and large file in G — 2026-10-29

Magnus confirmed satisfaction with full-size HTML at approximately 43 MB versus
240 MB and requested check-in of all changes. Kod/dokumentation reviewed; the
latest Release build and signature, 24 local documentation links, the project's new
G-patch references and git diff --check approved. No finds on targeted control
of credential patterns. main and origin/main are sinked before commit.

G's new panorama/result.png is the 180988415 byte (172,6 MiB), over GitHub's 100
MiB limit for regular Git files. No LFS tracking is configured in the repot;
current example workflow uses git archive. A choice between Git LFS with custom
sample packaging and the submission of all G project changes locally has been
requested. No commits, tags or pushes made before that election.

## JPEG Quality for HTML — 2026-10-29

At Magnus' request, JPEG Quality was added under Interactive Panorama, with
Normal (82%, Standard), High (92%) and Maximum (98%), the same levels as image
export. HTML has a separate quality selection that is sent via AppModel to the
JPEG encoding. This replaces the fixed HTML quality below 80%. The help is up to
date. Practical Small exports of the same G-image gave 5,55/ 6,75/7,23 MB;
different JPEG quantization was verified for the three levels. Installed UI
displays all options and default Normal; previously open G projects were
reopened on Export with HTML size Original as before the update.

Release-build succeeded and was installed as **1.4 (202610291952)** in
/Applications/PanoWizard.app. Installed signature and give diff--check approved.
No automated regression tests created or run. Nothing checked in.

## JPEG and size selection for HTML — 2026-10-29

Magnus approved JPEG-only for the interactive HTML export and selection
Small/Medium/Large/Original. Implemented with maximum width 4096/8192/12288/
saved original width, although JPEG quality is 80% and Medium as standard. The
smaller source panorama is not enlarged. The selection of HTML does not affect
the project's saved originals or the separate image port selections. Help and
README updated.

Practical exports of adjusted G: Small 5,4 MB, Medium 17,1 MB, Large 31,8 MB,
Original 52,3 MB; embedded JPEG and respective image size verified. Minor A kept
4096 × 2048 even with Medium. Medium was reviewed in Safari; Small was also
exported through the app from G with saved patchar/justeringar (4,6 MB and 4096
× 2048). They vary in size with motifs and adjustments. No automated regression
tests run; existing HTML test was given a valid image file because export now
decodes the image.

Release-build was successfully installed in /Applications/PanoWizard.app: **1.4
(202610291940)**. Installed signature and give diff--check approved. The changes
remain unchecked. Already modified original files in examples/G were left
untouched during this work; practical app control was carried out in isolated
copy.

## Size of the HTML file — 2026-10-29

Magnus estimates about 240 MB per HTML panorama as too large. The HTML export
needs to be able to reduce the file size without lowering the saved project
originals. Sample compression of coloured G with ImageIO/JPEG quality 0,80
yielded calculated independent HTML: 4096 px approximately 5,4 MB, 8192 px 17,1
MB, 12288 px 31,8 MB and the original 16914 px 52,3 MB. These are JPEG
measurements with a calculated base64 overhead; sizes vary with the subject.
Proposal: own selection of HTML width and JPEG quality, standard 8192 px/80 %.
The proposal was subsequently approved and implemented in accordance with the
section above.

## Full panorama generation — 2026-10-29

Create now calculates the panoramic width from the original measurement and
calibrated lens (angular resolution at the optical axis, with aspect
correction). Geometry and seams, color, and blending are analysed with a maximum width
of 4096 px; the final image details are projected directly from the original in
smaller blocks. Full 2:1 PNG is stored in the project. Preview loads up to 4096
px with explicit RGBA texture; exports use the saved result without new
stitching. Project format and MARKETING_VERSION are unchanged; older projects
retain their savings.

Retouch composites and car exports are now running in the background.
Invalidation of the panorama does not leave the retouch's busy status. HTML uses
WebGL 2 with texture parts to display images wider than the individual texture
of the GPU. PNG data is embedded into small separate data elements and read as
Blob; a single about 230 MB long script token provided unreasonable reading time
in Safari. HTML is still independent and loss-free, but it can be very large.

Verification completed after the previous chat interruption: isolated G-copy has
16914 × 8457 px in saved projects as well as Original JPEG and Original PNG.
Both existing patch images and masks were retained for replacement after
saving and reopening. Preview, retouch, tweaks and HTML export from the installed
app were visually checked; Safari showed full resolution with panorering/zoom as
well as retouch and tweaks. The change in the source image during the
retrospective calculation restored the working mode; the control change was
discarded. The original copies are unchanged. The assistant describes the new
flow.

Signed Release build was successfully installed in /Applications/PanoWizard.app:
**1.4 (202610291911)**, deep/strict-signatur and git diff --check approved. No
automatic regression tests performed; existing test calls and expectations are
adapted to async retouch and automatic size. No extensive review of all examples
or other web browsers performed. The changes are unchecked; no commit, tag,
push, archiving or Apple uploads have been made.

## Requirements for generation, preview and export — 2026-10-29

Magnus specified the flow: Create Panorama will generate and save panorama in
maximum resolution based on the source images. Exports shall use the already
high-resolution result; no new panorama generation at export. A smaller viewing
copy of Preview is accepted if it simplifies implementation. This replaces the
proposal to render high resolution only on export. Implemented and verified in
accordance with the section above.

## For the purposes of this Regulation, the following definitions shall apply: — 2026-10-29

Examining detail loss in example G: OpenCVPanoramaEngine.outputWidth is
hardcoded to 4096 for all generations. Saved panorama/result.png in G is 4096 ×
2048 (8,4 MP over the entire sphere). The NEF sources are 24 MP; the same
ImageIO reading that the app uses was verified to 4000 × 6000 after orientation.
The original of the export shall retain the existing size of the panorama.
Higher detail resolution requires a new generation with greater exhaustion. No
functional change or new panorama was made during the investigation. Magnus then
decided to discuss the solution further before implementation; later clarified
requirements are listed above. Check-in included the investigation and the
independent HTML export examples/G/panorama.html (4096 × 2048).

## Checkpoint — 2026-10-28 21:01 Europe/Stockholm

Magnus requested check-in of all pending changes: isolated temporary work files,
retained retouch at reimport without new images, lasso in the image margins and
documented arbets-/versionsrutiner. Source code and context checked; the latest
release build was successful, installed signature and git diff --check approved.
No further code changes or version enhancements were made at check-in. Commit,
new timestamp tag and push are included in the request.

## Lasso at the edges of the picture — 2026-10-28

On Magnus' instructions, the lattice clicking and hovering surface was extended
to the entire view area of the image, including the margins. The outline and
marker are drawn there; existing rasterization cuts the mask at the edge of the
image without limiting the angles of the polygon. The pencil hovers and gestures
are still in the picture. The change is only in PanoramaPreview.swift; the
project format remains unchanged.

Signed Release building succeeded. The app installed is 1.4 (202610282048),
controlled by codesign --verify --deep --strict. In the isolated G-copy,
Exclude/Include was verified on all four edges and correct cutting; also
cornering, magnification lasso and panelling were checked during the work. Brush
pulling with modifier key remains to be tested manually. The control copy was
shut down without saving. No automatic regression tests, commits, tags or pushes
performed.

## Two fixes after code review — 2026-10-28

On the instructions of Magnus, only AppModel.swift was changed: each model
instance receives its own workbook under macOS
temp/PanoWizard/projektUUID/tempUUID for restored panorama, patch images,
retouch composites and patch dialog files. Imports without newly added image
URLs update the overlapped file counter but retain panorama, retouch,
adjustments and selected working mode. The template, project format and version
number are unchanged.

Signed Release building was successful, copied to /Applications/PanoWizard.app
and checked with code design --verify --deep --strict. The installed version is
1.4 (202610282006). Manual control in two isolated G-copies with the same
project ID: reimporting existing image kept everything; after Save, panorama,
patch images, patch masks and retouch metadata were identical to the original. A
new image provided a continuous intended zero setting in one copy, while the AI
patch of another copy could be opened without error and saved with all image
data intact. The controls were closed. No new AI calls or automatic regression
tests were run. No commit, tag or push was performed for these changes.

## Targeted code review — 2026-10-28

Project and retouch workflows examined without code changes or automatic regression
tests. Two errors were manually verified in isolated copies of G with a new
project ID: (1) re-importing an existing image to zeroes panorama, patches and
adjustments despite unchanged image selection; (2) simultaneously opening copies
with the same project ID parts restored temporary panorama-/patchfiler in
AppModel.init. Zeroing in one window deleted patch files that the other window
needed; Edit showed "The patch image could not be read". The errors were
uncorrected during the review; they were later corrected according to the
section above. The review copies were closed without saving. Separately, Magnus
has chosen to maintain today's zero position when removing source image.

## Model-based workflow — 2026-10-28

Magnus uses a template `panorama.pw` that is copied to each new panorama. The
copies retain the model's project ID. The collision between temporary work files
above is therefore relevant in normal work when several such projects are opened
simultaneously, even if they contain different panorama. Magnus subsequently
approved a unique worksheet per open document, without modifying
mall/projektformat; the solution is implemented and verified in accordance with
the section above.

## Versioning workflow — 2026-10-28

Magnus manually changes the app's version number (`MARKETING_VERSION`) before
archiving and uploading a release to App Store Connect. The agent must not
change the version number on its own during local builds, check-ins, or
release preparation. Check in the version bump with the code sent to Apple.
Use these version boundaries in Git to draft release notes. A separate
changelog is unnecessary. Build numbers remain separate and are generated
automatically by the existing build step.

## Example G and assistance — 2026-10-28

Magnus added `examples/G`: six Nikon D7200 NEF images, no source masks and two
active AI patches in Replace mode. There is no separate nadir or zenit image; AI
reconstructes grass and leaves downward and branches and leaves upwards. The help example
overview, AI guide, homepage and opening instructions as well as both README
files now describe A–G. Five help images were taken in the app from a temporary
project copy: overview and before and after for nadir and zenit. Patch order and
comparison flow were verified manually. Supporting images reviewed; 128 local
links and image references and `git diff --check` approved. The original project and
the source images are unchanged (verified against worktree). Magnus then
requested check-in with commit, time stamp tag and push. The automatic release
description of the sample package was also updated to A–G. GitHub Pages builds
from main/docs and example workflow packs examples/ automatically at push. No
app code was changed or a new app builder needed.

## Local construction — 2026-10-28

Magnus showed after the first build that 1.3 was already waiting for App Review.
Before the second computer's check-in, the local project file and origin/main
were on 1.2; thus the uploaded version had not been saved there. The first local
build 1.3 (202610280135) was therefore replaced with the following version:
MARKETING_VERSION is now **1.4** in Debug and Release. Usually signed Release
building was successful and copied to `/Applications/PanoWizard.app` according
to the project installation routine. Installed version **1.4 (202610280137)**;
version metadata and `codesign --verify --deep --strict` verified for built and
installed app. Project file plist check and `git diff --check` approved. After
check-in on other Maces, `7adbccd` was retrieved with version basis 1.3. The
committee changes only version numbers and context; local 1.4 is retained. No
regression tests performed according to the project test preference. No restart
of the app, archiving, uploading, App Review modification, commit or push
performed.

## Current state of publication — 2026-10-28

Magnus screenshot confirms **macOS 1.3 — Waiting for Review** in the App Store
Connect. This replaces the publication status 1.2 below. Construction number and
date of dispatch for 1.3 has not been verified. The version upgrade is now
available in Git after other Macs check-in; the construction site has not been
verified. Check both Git status and the last verified version submitted before
your next update.

## Shaded version basis — 2026-10-28

Other Mac's check-in `7adbccd` saves version **1.3** in Git. Locally the next
build is **1.4** as per the section above; App Review status 1.3 has now been
confirmed with Magnus screenshot. Previous data on 1.2 are historical.

## Historical state of publication — 2026-10-24

PanoWizard **1.2 (202610240249)** is submitted to App Review and the status
**Waiting for Review** is verified in App Store Connect. Submission ID:
`17a31abe-65ac-4c62-b0b4-da16b4eec9c9`, dispatched 2026-10-24 at 03:00 Swedish
time. Magnus explicitly chose to replace the approved but unpublished 1.1
release; it was discontinued before the version mail was changed to 1.2. The new
building has been selected and Review Notes updated for load-bearing and example
A–D. Export compliance is responsible for the new construction. Manual
publication after approval remains. No new contract was accepted by the
assistant; the submission was successful despite a general notice of agreement
having been previously shown.

Active repository on Mac mini is now `/Users/magnus/GitHub/panowizard`, outside
of Dokument/iCloud. Signed archive:
`~/Library/Developer/Xcode/Archives/2026-10-24/PanoWizard-1.2.xcarchive`. File
signature and upload verified; only 11 known OpenCV-dSYM warnings. After a
separate failed GUI build, four ARCHS_STANDARD overrides were changed to arm64
because the accompanying OpenCV libraries only support arm64. The generated
archive product links that blocked the Release build folder were moved to
`~/Library/Developer/Xcode/BuildLinkBackups/20261024`; no target files were
deleted. Signed normal release building succeeded afterwards. These local
project settings and this context are not yet committed or pushed.

This status replaces the older publication status below. Wait for Apple's
message. Don't send in a new build or change the shipment without Magnus'
instructions.

## Current publishing status — read first (2026-10-16)

PanoWizard **1.1**, build **202610162112**, is inserted into App Review**. The
user's screenshot from the App Store Connect confirms **Items Submitted (1)**,
**MacOS App 1.1**, **1.1 (202610162112)** and **Waiting for Review** on 16
October. This is sent, not approved or published. The next step is to wait for
Apple's message. Do not re-submit or change build without the user's
instructions.

Version 1.0 (202610080027) was rejected on 15 October: Kina/OpenAI and lacked
sample files. Mainland China has been demarcated. Review Notes has been updated
for Help → Download Examples..., which downloads the automatically generated
package from GitHub. The source files under examples/ are still editable. The
user has verified both the new AI patch in A via download and the corrected 360
zoom locally.

Source code check point before documentation of dispatch: `22debb5`. The tag
`apple-submitted-1.1-202610162112` marks this documented dispatch checkpoint;
the exact binary identity between archive and commit has not been verified by
reproducible build comparison.

PanoWizard is the project Magnus wants to publish. **LAN Scanner and Broker
Explorer are only used privat/lokalt by Magnus.** They shall not be prepared for
App Store, GitHub Releases, DMG or other public distribution without new
explicit instructions. Previous proposals for the distribution of these two
tools were rejected by the user.

The active repository is /Users/magnus/Documents/GitHub/panowizard, origin
https://github.com/meg768/panowizard.git. Older next-gen names and formulations
about old ../panowizard below are history, not current search instructions.

Read this file before work resumes. update it when the structure, behaviour,
verification, distribution basis or key decisions of the project change;

## App and document icons — local change 2026-10-08

On Magnus' instructions, the approved full-square prototype is used as a new
appicon. All 10 AppIcon PNG sizes are opaque without an embedded frame or corner
mask. The separate PanoWizardProject.icns resource and the CFBundleTypeIconFile
have been removed. The document type UTTypeIcons specifies UTTypeIconText=PW and
allows macOS to use the app icon as the default badge on the system document
form. Debug and clean Release build succeeded; plist and icons
storlekar/opacitet verified. The Finder view has not yet been visually verified
and may be affected by icon cache or other installed app versions. The format of
the project remains unchanged. The release building is located in
/Users/magnus/Library/Developer/Xcode/PanoWizardBuilds/Release/PanoWizard.app.
Magnus starts again and continues in a new conversation. Next step: open this
build and check the app icon as well as existing and new .pw documents in
Finder. No new upload, submission or modification of the submitted build has
been made. The icon changes and this context are saved with commit and push at
Magnus' request.

## Target, outline and current instruction

`panowizard-next-gen` is the next generation of PanoWizard, built as a regular
native macOS app in Xcode for future Mac App Store distribution.

`../panowizard` is the existing finished app and is the reference implementation. It can't be changed.
The problem that migration solves is the project, build, and distribution setup, not
application code, algorithms, workflows or design. Do not perform feature
development, UI redesign, general refactoring or simplification that removes
functional parts.

Step 1 created a standard SwiftUI/Swift-app with Hello World, followed by the
Photography category and the accurately preserved old app icon. The user
subsequently confirmed that this baseline builds, archives and has passed App
Store Connect Validation.

Step 2 is now implemented locally: the entire application code, C++ engine,
necessary resources, original OpenCV library, tests and user guide have been
migrated. No known application features have been deliberately omitted. The user
has confirmed the successful App Store Connect validation of the migrated app.
Only the 11 precompiled OpenCV library symbol warnings remain.

Current instruction (2026-10-06): complete the Tutorial migration to
self-sufficient /docs with local images. Previous prohibitions against touching
Tutorial/ are replaced by this new instruction. No app code is changed. The user
has subsequently requested commit+push to origin/main. File access shall be
project-specific: restore optional metadata within `.pw`, check all originals
and directly request native Grant Access directory access per inaccessible
location if permission is missing, without a preliminary app alert. Save
bookmarks in the project for restart. Legacy projects with no metadata should be
able to be authorised and then upgraded through regular Save. Original images
shall always be external; never copy or move them to `.pw`.

## Repository and checkpoint

- Remote: `https://github.com/meg768/panowizard-next-gen.git`.
- Branch: `main`.
- Last committed basis: `c3526fb820096b8eaaf46a7f68001e908fbd4798`.
- The tag `pre-migration` points to this commit and is at origin.
- The migration and subsequent verified corrections are included in the
  checkpoint requested by the user to commit and push 2026-10-06.
- The old project was clean at the start. The contents of all its regular files
  (including Vendor and existing build files, excluding Git-internals) were
  compared to SHA-256 before and after and remained unchanged.

## Native Xcode base

- Projekt: `PanoWizard/PanoWizard.xcodeproj`.
- Shared scheme: `PanoWizard`, in `xcshareddata/xcschemes/PanoWizard.xcscheme`.
- App target and product: `PanoWizard`, `PanoWizard.app`.
- Native macOS, SwiftUI, Swift 6 language mode, Xcode 26.5.
- Deployment target remaining on macOS 26.5, from the new verified basis.
- Organization identifier: `se.egelberg`.
- Bundle identifier: **`se.egelberg.panowizard`**, Debug and Release.
- Automatic Xcode-managed signing, team Magnus Egelberg, ID `52A6FA9VB5`.
- Sandbox and Hardened Runtime apps are still activated.
- Photography-kategori: `public.app-category.photography`.
- The Xcode generated Info.plist is supplemented by `PanoWizard/Info.plist`,
  which only contains the original document type and exported UTI declarations.
- Project package: `.pw`, UTI `se.egelberg.panowizard.project`, Editor/Owner,
  the original `PanoWizardProject.icns` as document icon.
- App Store-version/build are still Xcode settings: 1.0 / 1. The time-based
  version number of the old script has not been reintroduced.
- No storage frameworks or Swift package dependencies.
- No `Package.swift` or own bundle, signature or distribution script.
- `.gitignore` excludes user-specific Xcode-state, `.DS_Store` and DerivedData.

The original Swift package used the standard Swift 6 competition without the
Xcode model's MainActor insulation as standard. Therefore, that setting was
removed from the app targets; the existing explicit actor entries of the source
code are retained. Algorithms, parameters, mesh conditions, cache identities and
image processing arrangements were not changed.

## Structure and dependencies

- `PanoWizard/PanoWizard/Application` — app-/dokumentlivscykel and menus.
- `PanoWizard/PanoWizard/Models` — Project format, original images, masks,
  patches, adjustments and document packages.
- `PanoWizard/PanoWizard/Services` — imports, metadata, stitching, retouch,
  image processing, Little Planet, exports and file access to the sandbox.
- `PanoWizard/PanoWizard/ViewModels` — AppModel and workflows.
- `PanoWizard/PanoWizard/Views` — whole existing the SwiftUI/AppKit interface.
- `PanoWizard/PanoWizard/Assets.xcassets` — the original unaltered app icon.
- `PanoWizard/OpenCVBridge` — of the original `PanoramaBridge.cpp` and C-header.
- `PanoWizard/Resources` — Backgrounds, documentation and third party licenses.
- `PanoWizard/Vendor/OpenCV` — the original OpenCV 5-headers and dylibs.
- `PanoWizard/PanoWizardTests` — all 13 original Swift Testing files.
- `docs` — Self-supporting GitHub Pages help, illustrated guides and images.
- `README.md` — existing function description with new Xcode building
  instructions.

`OpenCVBridge` is a native Xcode static library target with C++17. A small
`module.modulemap` makes the original's C-API available as `import
OpenCVBridge`. Header and C++ implementation are byte-identical to facit. Xcode
links libc++ and OpenCV and uses a regular Copy Files phase to Frameworks with
CodeSignOnCopy. No external stitching tools or auxiliary processes are used.

The original 11 distributed OpenCV 5 libraries are available with: calib, core,
features, flann, geometry, imgcodecs, imgproc, objdetect, photo, stereo and
stitching (`libopencv_*.500.dylib`). The copied Vendor binaries are
byte-identical to the original. Xcode will sign the embedded copies normally.
All transitive `@rpath` references verified are in the app's Frameworks; other
references go to Apple's system library. No local Vendor search routes are
needed at runtime.

**Final architecture decision (2026-10-05): PanoWizard is intentionally Apple
Silicon/arm64-only.** The original verified OpenCV 5.0 binaries are only arm64.
Do not add Intel/x86_64 support, do not rebuild OpenCV and do not create universal
binaries. Do not accept Xcode's proposals for standard architectures. `ARCHS =
arm64` is therefore used for app, bridge and testing. Intel support hasn't been
created; even the old script only built arm64. Do not change the OpenCV version
or algorithms to solve this without an explicit new task.

Backgrounds A.jpg, B.jpg and C.png are copied as a regular Backgrounds resource
map. The only resource change of the welcome wine is `Bundle.module` →
`Bundle.main`. The original OpenCV-/tredjepartslicenser shall be accompanied by
the appraisals.

## The name of the species

The existing appliance was imported in step 1 from
`../panowizard/Resources/Icons/PanoWizardApp.icns` with Apple's `iconutil`. All
ten PNG representations in the AppIcon.appicon are byte-identical to the
original representations extracted. No redesign, colour change or other
alterations were made.

All Mac slots are available: 16, 32, 128, 256 and 512pt, each in 1x/2x. 512pt
@2x is 1024×1024 and verified in the compiled Assets.car. Large representations
are found in Assets.car; extraction of only the built AppIcon.icns therefore
does not show the entire icon set.

## Sandbox and necessary kidney adjustments

Signed app entities have been verified to contain:

- `com.apple.security.app-sandbox = true`.
- `com.apple.security.files.user-selected.read-write = true` — project,
  JPEG/PNG/HTML/Little Planet/manual patch export and file management.
- `com.apple.security.files.bookmarks.app-scope = true` — access to external
  original images after the panel is closed and restarted.
- `com.apple.security.network.client = true` — existing OpenAI AI retouch.

No full disk access, sandbox exception, disabled library validation or other
broad security vulnerability has been introduced.

The original's project saves references to external originals, not embedded
copies of them. Project format **10 is unchanged**. The original file access
behavior was not enough for a sandboxed app after rebooting.

`SourceFileAccess.swift` keeps security-scoped access active while driving. It
no longer uses UserDefaults for source grants. Individual grants from
ImageImportService are stored in memory until Save enters optional project
metadata. Both the first image selection and Add must create a real bookmark
before the image is accepted. Native folder recovery keeps the selected
directory active in the same way.

The project may include **`source-access.json`** as an optional package member:

```json
{
  "version": 1,
  "bookmarks": {
    "/absolute/path/to/source-folder-or-file": "BASE64_OPAQUE_APP_SCOPED_BOOKMARK_DATA"
  }
}
```

Swift Codable Data is Base64 in JSON. The keys are standardized absolute POSIX
search paths. Only grants already awarded covering the project's source URLs are
saved. An allocated directory is deduplicated and replaces redundant individual
file bookmarks in the same directory. No broader directory access is
automatically created. Old packages without the file will receive empty bookmark
metadata and read as before. `project.json` and its formatVersion **10** is
unchanged.

Bookmarks are **app-scoped but stored project specifically in `.pw`**, not in
app settings. Apple document-scoped bookmarks require both file anchors and file
targets; they do not support the catalog target. App-scoped bookmarks support
the requested native catalog authorisation and only require existing app-scope
entitlements. Apple DTS source:
https://developer.apple.com/forums/thread/798402?answerId=855880022 No document
scope entitlement or temporary sandbox suspension has been introduced.

In document reading, only the open project bookmarks** with
`.withSecurityScope`, `.withoutUI` and startAccessingSecurityScopedResource are
restored before source images or metadata are used by previews. Resolved
bookmark data is recovered in memory and can be saved at the next Save,
including stale refresh. Of course, a process can still be accessed from
projects that have already been opened; macOS sandboxgrant is process-wide. It's
not a persistent global source registry.

All project sources are checked with real FileHandle-open/read. Permission
errors are collected for the entire project before NSOpenPanel appears directly
with the expected parent catalog. Grant Access of the panel is user
confirmation. After each grant, the remaining sources are checked; the next
necessary directory is displayed immediately without any additional Grant Access
alerts. A directory covering several originals or subcategories eliminates their
additional picker needs. Cancellation is off. Other I/O-fel have common error
handling. Refused access shall not delete references.

Grants become optional metadata in the document's working state and make the
document unsecured until Save. Save enters metadata together with unchanged
other project permissions. Save As includes the same relevant app-scoped grants
and does not require document anchor rebound. Project window
sourceReloadRevision starts with existing previews after successful resolution.
Revert follows the same read and recovery path.

An app-scoped bookmark is linked to the app's signature identity and local file
system. No guarantee of access after migration to another computer, user, or other
signature identity, or external files moves/stale-situationer that have not been
tested. Unused grants can be recovered through the same recovery. Project
metadata does not contain source image bytes and duplicerar/flyttar never
original.

Comparison to facit: **36 old Swift files migrated**, of which 32 are
byte-identical. The four necessary adjustments are:

1. PanoramaWelcomeView.swift — Bundle.main for resources
2. ImageImportService.swift — maintain the security-scoped original image
   resolution.
3. PanoProjectDocument.swift — Restore saved access before missing-file logic.
4. PanoWizardApp.swift — Resolution in the document window lifecycle and clearly
   error.

** Intentional differences from the old app:** legacy projects without
previously saved access grants may require user choice Grant Access for external
originals. No folder dialog is automatically displayed for readable projects.
The sandbox and lowercase bundle ID provide separate app references; old API
keys and UI preferences are not automatically imported. The API key is specified
in the same existing dialog. No key-locking solution or automatic copying of
sensitive settings has been introduced.

## Application behavior and baseline invariants

Preserve the existing implementation of:

- One complete overlapping horizontal fisheye ring covering 360° × 180°,
  with no multi-row stitching.
- Shared camera and lens parameters, separate repair images, and optimized
  geometry.
- Original orientation through ImageIO followed by the user's quarter turns.
- Red alpha-based exclusion masks and green seam-priority masks.
- SIFT, rotation RANSAC, robust camera and lens optimization, horizon
  leveling, spherical warping, radiometry, GraphCut ownership, seam
  correction, and blending.
- Internal 2:1 PNG with alpha preserved. Transparent pixels mean missing
  coverage. Opaque black is ordinary image content.
- Panorama preview, identical drag, scroll, and Command-zoom navigation,
  and masking tools.
- Manual and AI retouch patches with the existing creation and editing
  lifecycle. Patches do not affect stitching geometry. Newer patches are
  placed above older ones.
- The existing editable, alpha-derived AI mask, prompt, and saved results.
- Global non-destructive adjustments after retouch, shared by preview and
  export.
- Little Planet stereographic projection with the existing center, rotation,
  and resizing.
- JPEG and PNG output and self-contained HTML export with the existing
  implementation.
- Document, Save, Save As, Revert, and close behavior, menus, shortcuts,
  and file handling.
- The English interface and existing design, without introducing a language
  switcher or redesigning the UI.
- The production engine reads only explicitly selected originals and masks.
  It does not automatically look for images or use case-specific code.
- Cache format keys and associated mathematical parameters may not change
  during unrelated migration, renaming, or cleanup.

The old `best-ever` tag is the reference for visually verified panoramas A–S.
A successful build or synthetic test does not establish identical visual
results for these real panoramas. A–S were not run during the migration.

## Local Build map

The standard `CONFIGURATION_BUILD_DIR` of Xcodes is set at project level to
`$(HOME)/Library/Developer/Xcode/PanoWizardBuilds/$(CONFIGURATION)`. The
Git-ignored `Build` of the repository is a local symlink to
`~/Library/Developer/Xcode/PanoWizardBuilds`. The applications are therefore
accessed as `Build/Debug/PanoWizard.app` and `Build/Release/PanoWizard.app`.
That's the latest successful build per configuration. No own copying, bundling
or signing mechanism is used; Xcode builds and signs normally.

The reason for the external storage is that the repository is in iCloud
Documents. A direct app build under repository's Build got
FinderInfo/fileprovider-metadata from iCloud and Xcodes code design rejected it.
Therefore, the building products must be kept outside iCloud. The release
building and `codesign --verify --deep --strict` succeeded after this change. On
a new checkout, the Build link can be recreated to the above local folder; the
machine-specific link version is not managed.

## Construction, testing and archiving

Always use the usual Xcode project and shared PanoWizard schema.

```sh
xcodebuild -project PanoWizard/PanoWizard.xcodeproj \
  -scheme PanoWizard -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/panowizard-migration clean build

xcodebuild -project PanoWizard/PanoWizard.xcodeproj \
  -scheme PanoWizard -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/panowizard-migration-release clean build

xcodebuild -project PanoWizard/PanoWizard.xcodeproj \
  -scheme PanoWizard -destination 'platform=macOS,arch=arm64' test

xcodebuild -project PanoWizard/PanoWizard.xcodeproj \
  -scheme PanoWizard -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath /tmp/panowizard-migration.xcarchive archive
```

PanoWizardTests is a native hosted test target with the original `@testable
import`. OpenCVBridge normally builds as a target dependent. The test target and
bridge shall use SKIP_INSTALL and shall not appear as separate products in the
distribution archive.

## Verified in migration

- The pure Debug and Release build was successful.
- The Native Release filing was successful.
- All 54 existing test cases in 13 suites reported approved. They include
  project documents, metadata/orientering, grouping, native bridge validation,
  synthetic 2:1 panorama and cache reuse, mask dispatch, retouch, patch editing,
  adjustments, Little Planet, spherical math, UI interaction math and OpenAI
  request/response-hantering.
- The test `panoramaFixture` returns without work if
  `PANOWIZARD_PANORAMA_PROJECT` is missing. It wasn't configured here; the 54
  tests reported, therefore, don't mean that a real photographic project was
  tested.
- Tests were done after the final kidney transplants.
- The C++-motor/header of the original is byte-identical. The test files were
  originally identical; ImageMetadataReaderTests has subsequently been given
  actual file creation in import fixture and check for bookmark errors according
  to the latest file access task.
- Resources, licenses and Vendor libraries of the original have been compared;
  all transitive libraries are available in the built-in app without external
  Vendor runtime requirements.
- `codesign --verify --deep --strict` approved the app; signed sandbox entries
  and Info.plist/UTI/kategori checked.
- The apicon has the required compiled 1024×1024 representation.
- The signed sandboxed Release app was launched and tested via macOS-UI. Welcome
  view, thumbnail of the original image and spherical preview were shown.
- A single synthetic format-10 project was opened with the new folder dialog.
  Save As saved `.pw`, relative source image search path and panorama changed
  unchanged.
- The app avslutades/startades about and the saved project was opened without a
  new folder authorization; original image and preview remained.
- JPEG and PNG were exported in 1024×512; HTML contained its embedded image.
  Little Planet dialogue and PNG export worked (512×512 for test panorama).
- Move Source File to Trash succeeded for its own synthetic test image. No old
  project images were used for this destructive test measure.
- The file content of the old repository is unchanged according to
  before-and-after manifest.
- The only warning in final appbyggen/arkivering is that Xcode's metadata
  extraction was skipped for missing AppIntents.framework, which was also
  included in the basic project.

Initially, C++ linking problems (library search path and libc++) arose that were
solved with regular build settings. One test had surviving Xcode test frame
signature files from a discontinued build; a clean test build solved it. No
signature scripts or exceptions were introduced for this purpose.

Local verification logs are found in `/tmp/panowizard-migration-debug.log`,
`/tmp/panowizard-migration-release.log`,
`/tmp/panowizard-migration-final-tests.log` and
`/tmp/panowizard-migration-archive.log`. Test results are provided in
`/tmp/panowizard-migration-final-tests.xcresult`. These are temporary and not
included in the repositories. The synthetic files of the UI test were below
`/tmp/panowizard-migration-fixture` and are not product resources.

## History: first runtime regression and previous legacy workaround

This section describes an earlier implementation/verifiering. The map dialogue
was later removed as set out in the section on new project bookmarks below.

After the migration, the user reported that an existing `.pw` project is opened
with the correct bildnamn/dimensioner but shows ”The Image Could Not Be Read”.
The error was reproduced in the commonly signed Release app with
`/Users/magnus/Desktop/Panorama/E/panowizard.pw`, format 10 and eight external
PNG files.

The project package stores metadata and source image URLs in `project.json`. The
original isn't embedded. The old printer makes the URLs relative to the folder
containing the `.pw` package (although `..` may exist); the old reader also
supports absolute file URLs and fallbacks to the same filename next to the
package. For example, the e-project refers to `2009-06-25%2014-53-14.png` next
to the package, with URL decoding for the file name in the middle. Embedded
panorama/masker are separate resources in the package. The metadata of the image
list does not show that external image exchanges are readable. SourceImageRaster
is unchanged and uses ImageIO directly on the source image URL.

Rotor reason in the migration access code: SourceFileAccess could return without
a real access grant after `isReadableFile`, including only control of parent
folders. Filmetadata/permission bits and access to `.pw` do not give sandbox
rights to open the external originals. This meant that the necessary folder
dialogue was missing. In addition, the source code `.task(id: image)` could have
already saved a failed reading before access was granted; the same image value
did not start with that reading.

The narrow correction changes two production files:

- `Services/SourceFileAccess.swift`: check the actual file opening and read a
  change with FileHandle instead of metadata-based `isReadableFile`. For denied
  access, the same native NSOpenPanel is used for the source folder, the same
  app-scoped bookmark storage and the same active security-scoped access. After
  the elections, an actual opening of sources is verified. A file is considered
  missing only when the parent can actually be listed and the file name is
  missing, so denied access does not remove source image references. No
  automatic import of other images from the folder is entered.
- `Application/PanoWizardApp.swift`: resolution is terminated only after access
  and model are complete (`defer`), and ContentView gets a new identity when the
  resolution is terminated. It restarts from the existing
  source and thumbnail reads after access without changing image loads or UI
  design.

This is not the case with `.pw` format, URL format, metadata, savers, ImageIO
loaders, algorithms, entitlements or App Sandbox. Old format-10 projects do not
need to be rewritten; access grants are stored in the app's own preferences.
Other older project formats are still subject to the existing version policy of
Facet.

Verification after correction:

- The real E-project was opened in the regular Release app: a folder
  authorization, followed by visible thumbnails and readable original images,
  all eight selected through UI without image reading error. The actual
  pixels/mask of the first image was displayed visually.
- After closing without savings and full restart, the same project was opened
  without a new folder issue; the original image reading worked again.
- SHA-256 before and after confirmed unchanged project.json and all eight external PNG
  files.
- Release build and normal Debug build succeeded. App Sandbox and app-scoped
  bookmarks are still active; regular app builders have no full file system
  exception.
- 56 tests in 14 suites were passed, including the old 54 and two new focused
  tests for actual file opening respectively a catalogue that is not source
  image content.
- Important test limit: Xcode automatically adds a test-only read-only exception
  to `/` in the hosted test app. Hosted tests therefore do not prove denied file
  access to the sandbox. A temporary test of such denied access showed this and
  was removed. The above runtime verification was performed in the normal
  Release app with its regular, controlled entitlements, without this exception.

Logs: `/tmp/panowizard-source-access-release.log`,
`/tmp/panowizard-source-access-debug.log`,
`/tmp/panowizard-access-final-tests.log`. Result bundle:
`/tmp/panowizard-access-final-tests.xcresult`. Nothing committed, tagged or
pushed.

## History: new project file bookmarks — verification 2026-10-05

This verification applies to the first version without recovery. The latter,
explicitly user-selected Grant Access recovery is described below.

The user does not accept additional folder selection and has expressly waived
legacy file access requirements. The previous legacy map workaround has been
removed. App-scoped bookmarks from explicit image selection are sufficient for
requested flow without format change. No source images are copied, duplicated or
moved to the project package.

Modified production files in this task:

- SourceFileAccess: remove NSOpenPanel/AppKit/mappgrant; let the bookmark
  creator throw out errors instead of silently ignoring it; balance access if
  storage fails. Restore uses savings grants with no UI.
- ImageImportService: accept only images whose bookmarks have been successfully
  saved.
- PanoProjectDocument: manage throws from the existing retain of the document
  URL.
- PanoWizardApp: restore grants before the initial source previews start.

Runtime was verified in the normal signed Release app without broad file access
from the test host. Three new synthetic 640×320 PNG images were located outside
the sandbox container in
`/Users/magnus/PanoWizardBookmarkVerification-20261005`: two in `Sources`, one
in `Added`. Projects were created using normal Choose Source Images, the third
image was added via Add from the second directory, and Save saved
`Projects/BookmarkWorkflow.pw` to a separate directory. No senior portfolio
grant was selected. UserDefaults contained three individual file bookmarks
(852–856 bytes). The package contained only project.json and mask catalogues, no
original images.

The release process was completed with Quit and verified to be gone before
restart. After the relaunch only `.pw` was opened via Open Panorama. All three
thumbnails and individually selected images were uploaded without any new
access and folder dialog or image errors. The image pixel was verified visually. The
original remains in its original location.

Debug and Release build worked. App Sandbox and app-scope bookmarks are enabled
in the signed regular Release app; no file system exceptions were introduced.
Logs: `/tmp/panowizard-bookmarks-debug.log` the following points are added:
`/tmp/panowizard-bookmarks-release.log` the following points are added:
`/tmp/panowizard-bookmarks-tests.log` I'm not going to. Final test log:
`/tmp/panowizard-bookmarks-final-tests.log`. Test results:
`/tmp/panowizard-bookmarks-final-tests.xcresult`. All 56 tests in 14 suites
passed. The first run detected an old import fixture with only invented URLs and
stubborn metadata; scoped bookmarks require actual files. The test now creates
files for the column and also verifies that non-existent files with bookmark
errors are not imported. The optional panoramaFixture had no
PANOWIZARD_PANORAMA_PROJECT and therefore did not run a real stitchfixture. The
usual Debug app was built cleanly after the test run so the temporary file
system exception of the test host is not left in the latest Debug product.
Nothing committed, tagged or pushated. The old repository hasn't changed.

## Recoverable Grant Access through app references — verification 2026-10-05

This version was replaced by project metadata and a single alert stream as shown
below.

Current permission recovery replaces the previous limit of return:

- Titel: **Could Not Read Source Images**.
- Text: **PanoWizard needs permission to access the source images for this project.**
- Button: Cancel and Grant Access.
- Grant Access opens NSOpenPanel as a sheet with only catalog selection,
  initially `sourceURL.deletingLastPathComponent()`. The panel shall be
  displayed only after the alert has been closed, and only at the user's express
  choice.
- The selected directory is kept security-scoped and saved as an app-scoped
  bookmark via existing SourceFileAccess. All project references are read
  directly.
- If the next permission error is a different directory, the same recovery will
  appear for that directory. No individual file authorisation is required.
- Successful resolution restores the document model and changes ContentView's
  reloadrevision so previously unsuccessful thumbnails/previews recharges.
- Cancel in alert or panel interrupts recovery without changing
  original/projekt.
- Revert is using the same permission recovery. Other fil-/sparfel still have
  normal error handling and OK button.

Modified production files: SourceFileAccess.swift and PanoWizardApp.swift.
SourceFileAccess returns a type of PermissionRequired with URL to the rejected
source image. A real FileHandle read separates permission errors from the rest
of I/O-fel; Cocoa read/write-no-permission and POSIX EACCES/EPERM are supported.
Runtime showed that macOS reported the denied reading with Cocoa
write-no-permission and a misleading "permission to save" text; this is also
handled by the new recover. Confirmed missing files still follow the existing
missing file policy.

Verified in the commonly signed sandboxed Release app:

1. New synthetic format-10 fix, `PanoWizardRecoveryVerification-20261005`, with
   three external PNG images: two in Sources, one in Added; `.pw` in separate
   Projects. The catalogues had not been selected or bookmarked before.
2. Opening `Projects/Recovery.pw` gave exact text and Cancel/Grant Access
   buttons.
3. Grant Access opened the native panel directly in Sources, with image files
   disabled. A catalog box covered both of its pictures. Retry found the next
   denied catalog.
4. The next Grant Access opened right in Added. After its catalog selection, the
   error disappeared and all three thumbnails and source image spreads were
   uploaded.
5. The app was completely shut down with Quit; the Release process was checked
   to be gone. After the relaunch, the same `.pw` was opened without a new
   permission list or folder panel. All three sources could be selected without
   image error; image pixels were verified visually.
6. UserDefaults contains directory bookmarks for Sources and Added (740 bytes
   each), not individual recovery file grants. SHA-256 before and after confirmed
   unchanged project.json and all three external originals. The package still
   contains only project.json; no photocopies or format changes were made.

Release and the usual Debug build worked. Code design and ordinary
sandbox/bookmark-entitlements were verified; no file system exceptions were
introduced. 58 tests in 14 suites passed, including two new focused tests: real
permission-denial identifies sourceURL and confirmed missing file does not
provide a permission-recovery. The broad test-only file access of the hosted
test app does not prove sandbox grants; therefore, the entire recovery was
tested in a regular Release app. Optional real panoramaFixture is still
unconfigured. Cancel and incorrectly selected foldergrant has not been manually
tested in this runtime verification.

Logs: `/tmp/panowizard-recovery-release.log` the following points are added:
`/tmp/panowizard-recovery-debug.log` the following points are added:
`/tmp/panowizard-recovery-final-tests.log` I'm not going to. The result:
`/tmp/panowizard-recovery-final-tests.xcresult`. The old repository hasn't
changed. Nothing committed, tagged or pushated.

## Project-specific bookmarks and legacy upgrades — verification 2026-10-05

Production changes restricted to SourceFileAccess, PanoProjectDocument and
ProjectDocumentView in PanoWizardApp. Optional metadata as shown in the table
above is the only format extension. The old app ignores unknown package members,
but its usual Save would not preserve bookmark metadata; a new app is needed for
sandbox persistence. Original algorithms, image loaders, resources and UI are
unchanged beyond the requested recovery flow.

**Really legacy project U:** `/Users/magnus/Desktop/Panorama/U/panowizard.pw`.
Contains nine external 2000×3008 PNG originals, two exclusion masks, three
protection masks, panorama/result and two active manual retouch patches. Backup
of only the existing project package is available in
`/tmp/panowizard-legacy-U-before-project`; no external originals were copied.
SHA-256 manifest for existing projekt-/bildfiler:
`/tmp/panowizard-legacy-U-before.json`.

Commonly signed sandboxed Release app verified via native UI:

1. Full process restart before test. The first Open of U without bookmark
   metadata gave an exact Could Not Read Source Images / Grant Access alert.
2. Grant Access opened directly in U. A native catalog selection gave access to
   all nine originals. Projects were opened without further questions.
3. Source pixels, existing green protection mask and later red exclusion mask
   were verified visually; the retouchlist showed both active manual patches.
4. The usual Save added a source-access.json with a U-catalog bookmark. **All
   existing files, including project.json, were byte-identical to before and after.**
   This verifies the preserved settings, IDs, dates, and metadata, mask and
   patchbytes, panorama, protected masks, as well as all external originals.
5. Quit and check that the Release process really disappeared; relaunch and Open
   of the same U gave neither alerts nor folder picks. All nine sources were
   selected individually without image error; thumbnails/pixels/masker was
   charged.
6. The grant for the U-catalogue is not in the old UserDefaults bookmark
   register. Code no longer reads the register: persistence comes from project
   metadata.

**Multiple directories:**
`PanoWizardRecoveryVerification-20261005/Projects/Recovery.pw`, three synthetic
external PNG originals (two Sources, one Added) with no metadata. Again, an
initial alert; Grant Access started Added-picker and then directly
Sources-picker, without a second alert. Sources was chosen once for two files.
Save stored exactly two catalog bookmarks; all existing fixtures were unchanged.
After full Quit/relaunch/Open all three were loaded without alert/picker. The
package contains only project.json + source-access.json, no original images.

Debug and Release build succeeded; normal Debug app was built after the tests.
Codesign and signed ordinaries sandbox/bookmark-entitlements were verified. 62
tests in 14 suites passed. Four additional tests cover optional metadata with
complete projekt-/mask-/panorama-/retouch-roundtrip, legacy without metadata,
collection of all denied sources, and only relevant deduplicated grants. Hosted
test-only file system exception cannot prove sandbox runtime, which was
therefore tested in regular Release. Optional real panoramaFixture is still
unconfigured.

Logs: `/tmp/panowizard-project-bookmarks-release.log` the following points are
added: `/tmp/panowizard-project-bookmarks-debug.log` the following points are
added: `/tmp/panowizard-project-bookmarks-tests.log` I'm not going to. Test
results: `/tmp/panowizard-project-bookmarks-tests.xcresult`. The old repository
is unchanged. Only the explicitly tested Desktop/U-projektet has been upgraded
with optional metadata; other existing content was kept accurate. Nothing
committed, tagged or pushated.

## Standing verification limits

- No new App Store Connect validation or distribution has been made since the
  migration.
- No full visual panorama regression to the old appen/A–S. External source image
  reading in the actual E-project was later verified as set out in the section
  above.
- No sharp AI image call with API key; network.client and existing
  request/response-tester are verified, not end-to-end service response.
- The entire manual export/extern editing and import workflow was not tested
  through the UI; its implementation follows and retouch-/patchredigeringstester
  passes.
- All possible file moves, volumes, permissions changes and stale-bookmark
  situations are not manually tested. Unavailable grants are reported as
  incorrect; the user can choose Grant Access to recover missing grants.
  Bookmarks are stored in the project and linked to appidentitet/lokalt file
  systems. Transfer to another dator/konto is not verified. App preferences are
  not necessary.
- No Intel support; the original binary dependencies are arm64.
- No known deliberately removed functions. These verification limits must not be
  hidden or "disallowed" by removing or simplifying application functions.

## Direct native permission picker — verification 2026-10-05

The preliminary Could Not Read Source Images / Grant Access alert has been
removed. PermissionRequired starts the existing folder recovery on the next
main-loop port. Bookmark management, project metadata, retry and sequential
folder grants are unchanged. Other reading errors still show common error
alerts.

Debug and Release built with BUILD SUCCEEDED; logs:
`/tmp/panowizard-direct-authorization-debug.log` and
`/tmp/panowizard-direct-authorization-release.log`. Normal sandboxed Release app
was verified with a new test fix:
`/Users/magnus/PanoWizardDirectAuthorizationVerification-20261005/Projects/Direct.pw`.
Three external PNGs in two directories: opening went directly to the native
picker of the Added catalogue, then the Sources catalogue picker, with no app
alert between steps. All the pictures were uploaded. Save saved two folder
bookmarks in the existing source-access.json version 1. SHA256 for all four
previous files (three originals and project.json) was unchanged. After full
quit, relaunch and reopen, all three images were uploaded without alert or
folder picks. No change in format, no change in sandbox/capabilities. Existing
tests were not repeated for this UI change; the previous run had 62 approved
tests. There's nothing commit/tag/push.

## Automatic timestamp-based build identity — 2026-10-05

Semantic version remains manually controlled via MARKETING_VERSION = 1.0 in
Debug and Release. No automatic semantic increment and no persistent counter.
The native app target has an always running Run Script-phase Generate Build
Metadata, which uses a single local date call and writes two preprocessor macros
in $(DERIVED_FILE_DIR) /PanoWizardBuildMetadata.h. CFBundleVersion becomes
YYYMMDDHHmm and optional PanoWizardBuildTimestamp becomes YYYY-MM-DD HH:mm from
the same time. No source/project/plist-filer changes during construction.

The app Info.plist uses the usual plist preprocessing of Xcode with this
generated prefix header. Generate_INFOPLIST_FILE is NO for the app target (test
target unchanged), as otherwise the generated plist will replace CFBundleVersion
with CURRENT_PROJECT_VERSION. Standard bundle keys are therefore explicitly
included in the input panel with regular Xcode variable expansions. Photographs,
document types, icons and bundle identifiers are preserved. Xcode continues to
run plist processing, asset catalog, app bundling, signing and Archive; no
custom bundling/signing. CURRENT_PROJECT_VERSION = 1 is deleted for not entering
a competing build value.

The About command opens the default native macOS About panel with two rows:
Version 1.0 (202610052215) / Build 2026-10-05 22:15 (verified example). Debug
and Release built, and their bundle of metadata and About panels were verified.
The archive to /tmp/PanoWizardTimestamp.xcarchive was successful and contained
CFBundleShortVersionString 1.0, CFBundleVersion 202610052216 and local Build
2026-10-05 22:16. Native code design --verify --deep --strictly approved for
Debug and the archive. Construction logs /tmp/panowizard-timestamp-{debug
,release,archive}.log.

CFBundleVersion follows the current Apple documentation format (one to three
numeric integers separated by a dot; here an integer). App Store Connect
validation/upload was not run in this step. The minute resolution means that two
builds within the same minute get the same number; a new distribution build
needs another minute. Local time also means that changing systemklocka/tidszon
or returning to winter time can give previous value: no global monotonicity
guarantee without counter, according to simplified requirements. Nothing at all
commit/tag/push.

## Xcode Analyze and regression tests — 2026-10-05

The architectural decision above is final for now: arm64-only, no
Intel/universal- changes or OpenCV reconstructions. Analyze was run with shared
PanoWizard-scheme, Debug, platform=macOS,arch=arm64; app and native OpenCVBridge
included. First Analyze was blocked by RetouchPatch.id: UUIDx in
Models/PanoProject.swift. Unknown type resulted in error for Codable/Equatable.
Restored only UUID, which exactly matches the initialiser and the original
model. No change in format, retouch-/maskstate or behavior.

The next run hit an old PanoWizardTests.xctest in shared Debug output at code
design. Xcode's normal clean solved static output without source changes. Final
clean analyze was successful: zero diagnostics in Clangs PanoramaBridge.plist.
Swift compilers reported no code warnings. The only remaining warning was
AppIntents metadata extraction skipped / No AppIntents.framework dependency
found; benign because the app does not use App Intents. No dependency was added
to silence it. Build the metadata-phase always-run notice is intentional. Clang
static analyzer analyzes C++; Swift is controlled by the compiler, and
precompiled OpenCV-dylibs are not analyzed as source.

Debug and Release built approved. Test results: 62 passed in 14 suites, 0
failed, 0 skipped, /tmp/panowizard-analyze-tests.xcresult. Hosted tests do not
prove sandboxpermission runtime; no new UI recovery tests were needed for UUID
type. Normal Debug app was built cleanly after hosted tests to leave normal
sandbox/signing without test-only exceptions. Logs:
/tmp/panowizard-analyze-before.log (initial compilation error),
/tmp/panowizard-analyze-after.log (steel test bundle signing error),
/tmp/panowizard-analyze-final.log (Analyze approved),
/tmp/panowizard-analyze-{debug-build,release build,tests}.log. No changes to the
original project, OpenCV, algorithms, UI, external source images, Grant
Access/bookmarks, .pw format, capabilities or architectures. There's nothing
commit/tag/push.

## The dSYM of the app in normal Archive — 2026-10-05

The only buildsetting change: the Release configuration of the project now has
DWARF_DSYM_FOLDER_PATH = "$(BUILD_DIR) / $(CONFIGURATION)
$(EFFECTIVE_PLATFORM_NAME)". DEBUG_INFORMATION_FORMAT = dwarf-with-dysm was
already correct and is unchanged. Configuration_BUILD_DIR and the user's
Build/Debug and Build and Release shortcuts are preserved. Xcode may generate the
app's dSYM in its normal BUILD_DIR; for Archive this is
ArchiveIntermediates/PanoWizard/BuildProductsPath, which native Archive collects
automatically. BUILT_PRODUCTS_DIR was not sufficient as it also inherits the
fixed CONFIGURATION_BUILD_DIR search path. No copy/signing-scripts.

Normal Release Archive /tmp/PanoWizardDSYMFinal.xcarchive was successful. Its
dSYMs/PanoWizard.app.dSYM/Contents/Resources/DWARF/PanoWizard and archived app
executable have both UUID 63859E98-443B-319C-B2CB-AFB3EEE7F791 (arm64). The code
design of the archive -- verify --deep --strictly approved. The 11 precompiled
OpenCV libraries are unchanged; no dSYMs were manufactured and their symbol
warnings are intentionally left behind. The App Store Connect validation/upload
was not re-launched.

Debug/Release was built and the existing 62 tests in 14 suites passed. The
result /tmp/panowizard-dsym-tests.xcresult. Normal Debug was built purely after
hosted tests. The file left, as before, a dangling native Xcode-symlink in the
fixed Release output folder; only the dangling link was removed before the final
normal Release build. No change in app code, architecture, sandbox, OpenCV or
image processing. Logs /tmp/panowizard-dsym-debug.log the following points are
added: /tmp/panowizard-dsym-release-final.log the following points are added:
/tmp/panowizard-dsym-tests.log and /tmp/panowizard-dsym-archive-final.log I'm
not going to. There's nothing commit/tag/push.

## Single model design at project opening — 2026-10-05

Only the ProjectDocumentView lifecycle was changed. model is optional State and
init stores dokument/bookmarks but does not create AppModel. ContentView is only
displayed when the source resolution is successful. Existing .task
reads, restores, and authorizes sources and creates the final full model once.
New unspent projects create their model once in the same task. No initial full
model, double retouch rebuild or initial thumbnail pass that is then discarded.
Normal opening does not increase sourceReloadRevision; force-recovery maintains
the existing journey. Pending grants are based on savedDocument when the model
is still missing; Save/bookmarks retains the same format/semantik. The Native
Grant Access dialog and folder sequence are unchanged.

The same Release app, U/panowizard.pw and sample 15 seconds with 1 ms interval:
before /tmp/panowizard-new-open.sample retouch rebuild had 608 + 591 = 1199
samples under two model construction paths (view init and deferred resolution).
After /tmp/panowizard-opening-after.sample only resolveSources-path and 646
retouch rebuild samples; view init had 1 sample and no model/rebuild. 46 percent
less sampled retouch work, about 0.55 s of the previous estimate eliminated.
Sampling is estimation, not exact end-to-end latency or an exact runtime
invocation counter. The code has a single protected design at normal opening and
the profile confirms a single design path. No one
rendering, OpenCV, cache, image algorithm, or sandbox change. The U was opened without
Save.

Recovery was also verified with
/Users/magnus/PanoWizardOpeningRecovery-20261005/ Projects/Opening.pw: three
external test images in Added and Sources, direct native picks for each
catalogue, then uploading all three. Save saved two folder bookmarks in
source-access.json. SHA256 on the three originals and project.json unchanged.
Full quit, relaunch and reopen required no alerts or picks. Debug/Release BUILD
SUCCEED; 62 tests in 14 suites passed. /tmp/panowizard-opening-tests.xcresult;
/tmp/panowizard-opening-{debug,release,tests}.log. Debug was built purely after
hosted tests for normal sandbox/signing. Nothing at commit/tag/push.

## Recent distribution status and OpenCV symbol investigation — saved 2026-10-06

The user has confirmed that the PanoWizard.app-dSYM warning is resolved and the
App Store validation is successful. The current Upload Symbols Failed warnings
apply only to the 11 precompiled OpenCV 5.0 dylibs. The native dSYM output
fixture of the file is described above.

The latest task was to read-only investigate whether OpenCV symbols can be
obtained without changing verified behaviour. No libraries were rebuilt or
replaced. There is NO authorisation to implement an OpenCV rebuild; the next
decision remains with the user. The recommendation is to leave the symbol
warnings until improved crash-symbolization justifies a separately verified
dependency rebuild. The Arm64-only decision remains final for now. Nothing
commit/tag/push is allowed.

### Locally recovered origin and construction configuration

The .vendor cache of the original contains opencv-5.0.0.tar.gz, opencv-5.0.0/
and opencv-build/ with CMakeCache.txt, build.ninja, compiler metadata and object
files. Source archive SHA256:
b0528f5a1d379d59d4701cb28c36e22214cc51cf64594e5b56f2d3e6c0233095 All 6905
compared extracted source files were identical to the archive. Embedded Version
control is unknown; exact upstream Git-commit/download-URL was not determined.
The local exact source archive and building configuration are available.

The 11 dylibs in the original .vendor-cache/opencv-build/lib have the same UUIDs
and identical __text machine code sections as the current Vendor/OpenCV/lib. The
SHA256 of all files is different, so don't say full byte identity between
build-output and Vendor; the UUID + __text comparison shows the same
linkage origin and machine code.

Configuration: Release, shared dylibs, arm64, C++17, -O3 -DNDEBUG, deployment
macOS 26.0; AppleClang 21.0.0.21000101, CMake 4.4.0 and Ninja. BUILD_LIST =
core,imgproc,imgcodecs,features,flann,calib,photo,stitching; its dependencies
result in exactly calib/core/features/flann/geometry/imgcodecs/
imgproc/objdetect/photo/stereo/stitching. No additional contributions. Accurate
algorithm hint, NEON/FP16/DOTPROD baseline and NEON_BF16 dispatch; GCD,
Accelerate/LAPACK, Eigen 5.0.1, Carotene and KleidiCV 26.03. I'm not going to be
able to do this. The following code is used for embedded codec support: zlib
1.3.2, libjpeg-turbo 3.1.2-70, PNG 1.6.57 (NEON, EXIF/XMP/ICC/cICP), TIFF 4.7.1,
JPEG2000/OpenJPEG 2.5.3 and GIF/HDR/SUNRASTER/ PXM/PFM. AVIF is missing despite
requested WITH_AVIF: separate the desired CMake options from actual
detected/built support. For accurate reproduction, external headers
SDK/toolchain and CPU/dependency-autodetection must also be pinned, not just
BUILD_LIST.

### Why current dylibs can't get real matching dSYMs

I'm not going to be able to do this. All 871 remaining Mach-O .o files were
checked: 0 had __DWARF. Dylibs also lacks DWARF; the dsymutil --dump-debug
folder on core was empty at object/debug-info-poster. No existing OpenCV-dSYM
was found in the original, new repot or previously investigated local
build/archive-mappar. The database was never created, it's not just lost in the
packaging. Genuine matching dSYMs cannot therefore be recovered from these
artefacts. Do not manufacture tomma/falska symbol files or copy UUID to other
dSYMs.

### Minimum possible future action — Recommendation only, not implemented

An isolated rebuild of exactly the same source/config/dependency/toolchain, with
Release optimization remaining and only debug-info enabled, is plausibly drop-in
compatible but not yet verified. OpenCV 5.0's local
cmake/OpenCVCompilerOptions.cmake supports BUILD_WITH_DEBUG_INFO=ON and adds in
this toolchain to -g1 in Release without removing -O3. Generate dSYMs from new
binaries/object files before stripping; they must match new dylib-UUIDs. Compare
export-symboler/ABI/install names/transitiva deps, headers, CPU/backend-
configuration, codec support and machine code; verify PanoWizard image results
and regression tests before any replacement. It would require replacement
dilibs, not just an archive setting fix. The fact that debug-info normally does
not change behavior is no guarantee of byte-identical code or identical behavior
at new build. Do not touch the now-verified native stack without further
explicit instructions.

Sources: https://llvm.org/docs/CommandGuide/dsymutil.html and
https://docs.opencv.org/4.12.0/db/d05/tutorial_config_reference.html; exact
OpenCV 5.0 option behavior was also verified directly in the local CMake source
file.

The most recent code change is still a simple AppModel construction at opening,
with verified Debug/Release, 62 tests and preserved Grant Access persistence as
described in the section above. Only CONTEXT.md was updated at this context
saving.

## Commit/push-checkpoint — 2026-10-06

The user requested commit+push of current work to origin/main. The checkpoint
includes the entire native Xcode migration, arm64 OpenCV binaries and resources,
sandbox/bookmark-recovery with optional project metadata, timestamp identity,
native archive-dSYM setting, UUID typefix, simple AppModel construction at
opening, tests, user guide and context. Previous verifications are described
above; no new code changes or OpenCV rebuilds are made as part of the
checkpoint. There's no tagging.

## Minimum GitHub Pages help for review — 2026-10-06

/docs/index.md created from scratch with short user assistance in English:
purpose, create/open/save, external source images and Grant Access, Add,
Create-analysis/ stitching, navigation/adjustments, masks, manual/AI patches,
Little Planet and JPEG/PNG/HTML-export. Facts Tutorial/, README and current UI
labels. Analyze is not a separate user operation; help explains that Create does
analysis and stitching. No assets duplicated: the initial version is text only.
No framework, theme, JS, custom design/config or navigation system. Tutorial/
and app code unchanged. The user then requested commit+push to origin/main. No
GitHub Pages configuration or deployment was performed.

## Tutorial migration to self-sustaining docs — 2026-10-06

The user stopped the first move, requested analysis and authorised after
completion. Tutorial/README.md is now docs/getting-started.md. Images/ and
HowTo/ moved to docs/; respectively, the guides README.md are now called
index.md. Existing docs/index.md is maintained with a panoramic illustration and
links to five picture guides. All 17 images are byte-identical with committed
Tutorial material; no duplicates or image dependencies outside of the docs. All
internal page and image links verified are within docs and point to existing content.
Public page links use .html; each detail guide links back to the homepage. No
framework, theme, JS or configuration changes. Tutorial/ contains only locally
ignored .DS_Store; its tracked material has been moved. The app code is
unchanged. Readme's structural data is updated. No commit/push or deployment.

The user requested commit+push of the docs migration 2026-10-06. No tagging or
separate deployment requested.

## Native Help menu — 2026-10-06

PanoWizard Help reads the PanoWizardHelpURL from the app's Info.plist and opens
https://meg768.github.io/panowizard-next-gen/ via NSWorkspace.shared.open in the
default web browser. The double slash of the URLs are XML entities in the source
folder because existing Xcode-plist preprocessing otherwise interprets them as a
comment; built-in Debug/Release-plists contains the exact normal URL. SwiftUI
replaces the .help command group. AppKit helpMenu points to a retained off-menu
NSMenu, which according to the native API suppresses the automatic Spotlight
Search box. No WebView or custom help window. Docs and other app functions
unchanged. Debug and Release build succeeded. Release ran: Help contains only
PanoWizard Help, without Search; click Opened correctly published help page in
Safari. No commit, tag or push as directed by the user.

The user then authorized commit+push of the Help menu change to origin/main. No
tagging requested.

## Joint project window frames without subsequent zoom — 2026-10-06

The user selected app level storlek/position for all project windows. The old
WindowStateRestorer with two async steps and explicit zoom ((default true)
replaced by NSView.viewDidMoveToWindow which synchronously restores the common
frame PanoWizard.ProjectWindow via setFrameUsingName(force: true), and registers
native setFrameAutosaveName. Previously saved frames are reused. Separate
isZoomed flag is no longer used; defaultSize 1240x780 applies without a saved
frame. No changes to the project data, load or separate zoom of the welcome
window. Debug/Release build succeeded. Release verification: opened Opening.pw,
resized with native Window → Move & Resize → Left (901x923 points), completely
quashed and reopened the same project; saved less frame returned. Closed and
opened H/panowizard.pw; the same common frame used, images and preview loaded.
No subsequent programmatic project zoom remains. UI snapshots verify the final
size; no box-by-box measurement of opening frames is performed. No one
commit/tag/push.

## The text of the om-window version — 2026-10-06

At the user's request, the Om window now only displays Version 1.0 and Build
with local datum/tid; numerically CFBundleVersion in parentheses removed from
UI. CFBundleVersion is still automatically generated and included unchanged in
the bundle metadata. Manual semantic version is controlled by the app target's
Version / MARKETING_VERSION (Debug and Release), currently 1.0. No one
commit/push.

The user confirmed that the project window restoration is working and requested
a commit+push of current work. Xcode has also normalized project.pbxprojects,
added INFOPLIST_KEY_CFBundleDisplayName=PanoWizard in Debug/Release and removed
PanoWizard.entitlements from synchronized-group membershipExceptions.
Marketing_version is continued 1.0 I'm not going to. Release-build of the
om-text succeeded.

## Topic-oriented GitHub Pages Help — 2026-10-06

The user requested simpler visual homepage and separate topics; structure was
suggested prior to implementation.docs/index.md has title, existing 1800x900
(2:1) panorama, short intro, and 11 topic links grouped Start / Create and
inspect / Correct / Export. Six new Markdown pages are moving instructions from
the homepage: projects.md, source-images.md, creating-panorama.md, preview.md,
export.md, file-access.md. Existing getting-started.md and four HowTo guides
kept on the same URLs. The Masks Guide supplemented with an existing warning of
recreate/retouch; the AI Guide with existing API key requirements. All 17 images
are switched identical; new pages refer to existing images without copies. 58
internal links checked against existing files within the docs. Ordinary
Markdown, no JS, CSS/theme/framework/generator or change of app. Published
rendering not verified (nothing push/deployment). No commit/push as directed.

The user then requested commit+push of the subject-oriented help page to
origin/main. No tagging or separate deployment requested.

## Hide the automatic repo heading in Help — 2026-10-06

The user asked to remove the blue panowizard-next-gen heading at the top of each
page. Verified published HTML and default theme Primer: the repo headline is
rendered only if site.title is truthy and differs from page.title.
docs/_config.yml sets title: false to shut down this headline globally without
CSS, own layout, JS or modification of the pages' Markdown headlines. Published
rendering cannot be verified before push/deployment. No commit/push performed.

The user then requested a commit+push of the setting that hides the repo heading
to origin/main. No tagging requested.

## Correction of repo items — 2026-10-06

After push, it was verified that Pages deploy by 5f957c5 was successful and
published HTML still contains the repo headline; title:false wasn't enough
(metadata refills title). Replaced with site title PanoWizard Help and minimal
docs/_includes/head-custom.html CSS: .markdown-body > h1:first-child:not([id]) {
display: none; }. Primaries include head-custom in head. The selector hits only
automatic h1 without id, not Markdown headings with id. No own layout or
JavaScript. Locally verified against published HTML; published effect requires
new commit/push. No commit/push yet.

The user authorised commit+push of the correction (c+p) to origin/main.

## Assistance review against current implementation — 2026-10-06

All 12 Markdown help pages read and compared with current SwiftUI viewlabels,
AppModel, dokument/bookmark/import-kod, OpenCVBridge and
export/retouch-services. Corrected startup flow: Create Your Panorama directly
selects source images, Add applies to more images in open projects (also
verified in running UI and picks off). Source Images clarifies right-click or Image
type and equal pixel size after rotation. Previous categorical claims that
multi-row is unsupported are removed: ring model exists, but no explicit
multi-row rejection or verification of such datasets; the recommendation for an
overlapping ring is maintained without promising multi-row support. Little
Planet has Option drag to center, drag/horizontal scroll to rotation; existing
shape-screenshot shows earlier click-text/sliderlayout and is marked clearly as
older. Mask/Create-varning Corrected: masking changes invalidate panorama
directly, clear patches and neutralize adjustments; successful stitch makes the
same trip. API-key entry button clarified from current AI sheet. Other topics
retained. 58 local links verified, all 17 images unchanged. No full new
stitching/ AI-anrop/export benchmark or reproduction of the scene results of the
illustrations; estimates 'few minutes'/'most sequences' are not supported by the
code and have not been retested. No one app code, structure, or design change. No one
commit/push.

The user then authorised commit+push (c+p) of the corrections to origin/main
from the Help review. No tagging requested.

## .pw document icon identical to the app icon — 2026-10-06

The user requested the exact appikon artwork for .pw without paper treatment.
PanoWizard/Resources/PanoWizardProject.icns Replaced with the existing native
actool-generated AppIcon.icns from the built app. The AppIcon asset is
unchanged. Existing CFBundleTypeIconFile=PanoWizardProject.icns and native
resource-copy retained. Debug/Release build succeeded; in both built bundles
verified that referenced document icons are byte-identical with their
AppIcon.icns and source resource. No script or build pipeline change, no redesign.
The Finder icon cache for already registered documents was not verified; the
cache may display old icons until macOS updates pre-registration. No one
commit/push.

## No window tabs and simplified View menu — 2026-10-06

The user requested no tabs and only Zoom In / Zoom Out / Reset View in View.
NSWindow.allowsAutomaticWindowTabbing=false is set before launch; the app window
gets tabbingMode=.disallowed when updated. The view menu is identified via the
Zoom In- title (SwiftUI uses internal menuAction, not image responder selector)
and filtered to the three commands, even at native menu-update/open/tracking to
avoid AppKit injection by fullscreen/tab-items. The native fullscreen button is
not changed. Debug/Release build succeeded. After the full reboot of Release,
native View menus verified exactly three records, no tab/fullscreen-menyposter.
Previous local document changes have continued. No one commit/push.

## Return to standard for View menu and tabs — 2026-10-06

The user declined the special code to limit View and close tabs and priorities
SwiftUI/macOS-standard. The entire newly added ViewMenuDelegateProxy, menu
tracking observer and tabing overrides removed; app file restored to committed
mode. The existing Zoom In/Out/Reset commands and the system standard
poster/flikar are maintained. The previous paragraph View/tab-implementation is
therefore replaced. The change in the document remains. No one commit/push.

## Verification of native project tables — 2026-10-06

The user authorised the verification of tabs and existing Close/Save/quit, with
adjustments remaining if no concrete errors are found. Test copies Tab-A.pw and
Tab-B.pw were created in /tmp/PanoWizardTabVerification from Opening.pw;
relative source-paths rebased to existing external test images (only copies
modified). Native Merge All Windows worked, tabbar/new-tab/systemkommandon
available. A roterades/sparades with Cmd-S; the image size of B remains
unchanged. B was rotated and Cmd-W gave Save/Don't Save/Cancel; Cancel kept the
tab, Save saved B and closed only B. On-disk JSON verified separately rotation=1
for A/B. A was changed again, another tab was activated and Cmd-Q warned of
unsparing A. Cancel stopped quit; Don't Save finished the test run and disk-A
kept previously saved rotation=1. Original Opening.pw SHA256 unchanged. The
existing W-Project was not amended. No specific tab error detected; no app code
changed. Not a complete verification of all menyalternativ/Save As or many
concurrent dirty tabs. Previous icon change remains; no commit/push.

The user then authorised commit+push (c+p) of the document change and updated
context, including beslut/verifiering to follow native tabs. No tab code remains
in the amendments; no tagging requested.

## Empty projects with the same working surface — 2026-10-06

The user authorised the first amendment: empty documents should look like
ordinary projects without images. ContentView now always uses
NavigationSplitView and DetailWorkspace; the previously large
PanoramaWelcomeView in blank documents is removed. The sidebar always displays
Images/Add and Panorama/Create/Retouch/Preview/ Export; Create and
navigationrows are disabled when the database is missing. Sidebar-No Images
overlay removed to avoid obscuring the posts. Preview has simple No Source
Images text with Add/drop-instruktion. No model, stitching, or sandbox change
Debug/Release build succeeded. Release-UI verified via File New and native
flickr +: both display the same sidebar/arbetsyta without image background. Add
opens native image imports, interrupted after check. Separate appstart's
welcome- scene/maximering left in this first step; only empty project documents
changed. No one commit/push.

## A simple shutdown of automatic tabing — 2026-10-06

At the user's explicit request, only `NSWindow.allowsAutomaticWindowTabbing =
false` is entered in the existing app delegate `applicationWillFinishLaunching`.
No menu filtering, proprietary window management or other tab adjustment has
been added. Debug and Release builds without error (logs
/tmp/panowizard-simple-tabbing-debug.log and release.log). Runtime verification
is not yet complete: the running app closure shows unreserved changes. The
termination was discontinued to preserve them; the user has been asked whether
to save save and close or allow termination without saving. A full restart is
required before the new launch setting can be verified with two documents. No
one commit/push.

## Commit, push, and timestamp tags — 2026-10-06

The user decided that future `c+p` or `commit+push` requests for this project
should also create and push an annotated tag on the final commit. Use
`YYYY-MM-DD-hh-mm` in Europe/Stockholm local time on a 24-hour clock. This is a
workflow for explicitly requested commits and pushes. Do not automate it
through a build hook or commit or push against the user's instructions.
Commit ce238af, which added an empty project workspace and a simple tab
setting, was pushed. Runtime verification of the tab setting after restart
was still pending.

## Recorded context — 2026-10-07

The user wants every explicitly requested check-in (c+p) to produce a
recognizable version on GitHub that is easy to return to. The commit is the
version, and the push publishes the commit and tag to origin. Keep the simple
YYYY-MM-DD-hh-mm format. The user wants neither extra time precision nor
special handling for more than one commit within a minute. Do not move a
published tag if its name conflicts.
The latest pushed code change was ce238af. The following commits 3975097 and
e91ddea changed only the context and tagging procedure. Existing tags:
pre-migration, 2026-10-06_23-15-44, and 2026-10-06-23-18. There were no other
app code changes. Debug and Release builds passed for the tab setting.
Runtime verification after restart with two documents was still pending.
Unsaved changes had to be preserved.

## Buffered UI changes implemented — 2026-10-07

The user approved seven points with "Drive": the Images menu always has Add...
(disabled without active project model), separator and picture list when images
are available. Focused scene action uses existing image importers. The sidebar
Create button's trailing padding corrected from 20 to 14 after visual check
against Add. The Panorama menu is now called Create, the same as
action/kortkommando. The welcome image remains; WelcomeWindowZoomer removed,
existing WindowStateRestores reused with a separate app-level frameName
PanoWizard.WelcomeWindow. Normal default 1080x680, project frame unchanged. No
change to startup and reopening workflow otherwise. The source image's mask toolbar shows
Clear mask and Rotate with ikon/text; Remove and Invert buttons removed,
Cmd+Z/underliggande mask functions unchanged. The preview mode has the same
Create button as Retouch/Export (disabled according to canStitch). All six
ContentUnavailableView uses new common OpticalEmptyStateLayout, intrinsic
message group centered at height/3 and cluttered for small areas;
texter/typografi/interna distance unchanged. Debug/Release builds without error.
Release UI controlled: Add... with empty project, import of existing docs JPG in
an unseparated test document, the machine buttons, image menu, Create in
Preview/Retouch/Export, visual height of the blank. Right padding final adjusted
from screenshot; final adjustment not verified in restarted UI yet. The welcome
window resize/quit/relaunch-persistens is not manually verified this time. The
old Tab-A fixture now lacks its external PNGs and gave existing read errors; not
modified or saved. The user's separately running installed app intact. No
commit, tag or push.

## Other buffered UI list — 2026-10-07

Approved with "Run": the machine button is now called Clear (same ikon/action),
JPEG export starts with existing Maximum value 0.98 instead of High 0.92, and No
Source Images empty mode has Add-button. Add uses the exact same import
presentation as sidopanel/Images-meny, with no new file management. I'm going to
add text. Changes to the first UI list not yet committed are retained. No one
commit/tagg/push. Debug and Release BUILD SUCCEED after this list, diff --check
without error. The code link to existing imports and Maximum tag 0.98 verified;
the three changes have not been manually tested in the restarted app this time.

## Third buffered UI list — 2026-10-07

Approved with "Run": No Source Images actions contain an explicitly centred
VStack with Add and help text in their own row (ContentUnavailableView actions
otherwise placed them horizontally). The description for Preview without images
is now "To preview, first add source images and create a panorama". Retouch and
Export use the corresponding approved text and Add when images.isEmpty. With
images but without panorama, the existing Create/text/canStitch is maintained.
All Add-buttons use existing model.isImporterPresented; no new
sandbox, import, and stitching workflows. Previously uncommitted UI changes retained. No
one commit/tagg/push. Debug and Release BUILD SUCCEED. diff --check without
error. Branches and Add-action checked in the code; final visual control in
restarted app remains.

## Backgrounds and collected check-in — 2026-10-07

User replaced or extended welcome pictures: Backgrounds now include A.jpg–G.jpg,
C.png replaced with C.jpg. The entire folder reference is normally copied by
Xcode. Debug and Release built without error; exactly the same seven image names
and byte-identical images verified in both app packages. No image
transformations performed by Codex. The user authorised commit+push of compiled
UI lists and new backgrounds, with date tags according to established routine.
The above manual verification limitations remain; they have not been replaced by
claims of new runtime tests.


## Repository name and help URL — 2026-10-08

Active repository is now /Users/magnus/Documents/GitHub/panowizard, origin
https://github.com/meg768/panowizard.git. Previous next-gen names in history
refer to this migrated Xcode project. PanoWizardHelpURL in Info.plist updated to
https://meg768.github.io/panowizard/ after renaming. Native Help-action still
reads this key and opens the default web browser.

## Support and privacy policy — 2026-10-08

In front of the App Store, we added docs/support.md and docs/privacy.md as well
as links from the help's homepage. The user explicitly chose GitHub Issues as
the support channel (activated in meg768/panowizard). No invented e-mail
address. Policy based on current code: local image processing, external source
images, projektmetadata/masks/panorama/patches and security bookmarks, voluntary
OpenAI image-edit request directly via HTTPS with its own API key. The key is
currently in UserDefaults, not Keychain and not the project. No claims about
OpenAI retention or training; links to the provider's data policy. Support warns
that GitHub Issues is public and that .pw may contain images and paths. Local
Markdown and HTML links verified. No app code changed. Published after the next
Pages deployment: /panowizard/support.html and /panowizard/privacy.html. The
pages are not yet pushade/publicerade. The App Store Connect Privacy form and
the app's AI consent stream remain separate; the user previously postponed the
AI review. No commit/tagg/push this time.

## App Store Connect and TestFlight — 2026-10-08

support and policy changes above is then commuted and pushed into e569164, with
annotated tag 2026-10-08-00-24. The previous UI-/bakgrundscommit is 5bcd215, tag
2026-10-07-23-36. The "not pushed" of the older pieces is their timing.

- App Store Connect Apple ID: 6819353008; bundle se.egelberg.panowizard.
- Archive/upload succeeded for 1.0 (202610080027). The building was also
  selected for the distribution version. The app icon appears correctly in
  Connect.
- Internal TestFlight group "My Testing": a tester and a build. Magnus installed
  via TestFlight and confirmed the basic flow: create projects, add images,
  create panorama, export, save and reopen. This is user verification, not new
  automated tests. The AI live call hasn't been verified.
- Free: Current Price screenshot shows 0,00 kr in Sweden and zero prices in
  other visible markets. Availability 175 countries or regions.
- Manual release was recommended and the user proceeded as instructed;
  ultimately saved selections have not been verified in screenshots. Please
  check this before any future publication of automatisk/manuell.
- Primary language English (U.S.); category Photo & Video, no secondary
  category. The age form gave 4+ (regional exceptions are shown), Not Applicable
  as the override. Content Rights saved as no third-party content, provided that
  the welcome pictures are Magnus' own. Apple's Standard License Agreement
  remains.
- App Privacy was published through the user's step-by-step work. Declared
  types: Photos or Videos, Other User Content, User ID; App Functionality,
  linked to identity, no tracking. API keys such as User ID and the link to
  identity are our assessment, not an explicit Apple classification of API keys.
  Background: voluntary OpenAI image-edit with own key and provider's default
  retention; local image processing is not data collection per se.
- Privacy Policy URL: https://meg768.github.io/panowizard/privacy.html Support
  URL: https://meg768.github.io/panowizard/support.html Marketing URL:
  https://meg768.github.io/panowizard/ Copyright: 2026 by Magnus Egelberg.
  GitHub Issues is the chosen support channel.
- Description and keywords filled in, promotional text and subtitle left blank.
- Sign-in required delimited; Apple contact details completed by the user. **The
  API key is specified in the AI retouching interface itself, not in Settings.**
  The user's correction is the controller for future
  dokumentation/granskningsnoter.

Review notes saved by the user:

PanoWizard creates panoramas from overlapping source images. To test the main
workflow, add overlapping photos, click Create, and export the result. Image
stitching, masks, manual retouching, and previews run locally without signing in.

Optional AI retouching requires an OpenAI API key entered in the AI retouch
interface. It sends the selected panorama view and editing instructions directly
to OpenAI.

### Shop screen

A screenshot is uploaded and saved, with Lund's Cathedral in Preview and the
app's sidebar. The project was already open from
/Users/magnus/Desktop/Panorama/U/panowizard.pw in /Applications/PanoWizard.app.
Native app screenshots were taken via CUA; no code or project changes were made.
After explicit approval, it was scaled in proportion to ImageMagick and narrow
dark side margins to exactly 2880 × 1800, without cropping or distortion.
Originally: /Users/magnus/Desktop/PanoWizard-AppStore/01-preview.png Uploaded:
/Users/magnus/Desktop/PanoWizard-AppStore/01-preview-2880x1800.png

### Known remaining questions

AI-disclosure/uttryckligt consent in the app was previously opened and has not
been reviewed or amended during this session. How Apple will test optional AI
retouch without its own API key was discussed but not resolved before the user's
input. The shipment is confirmed; this does not mean that these questions are
verified or that Apple has approved the app. Handles concrete feedback when it
comes.

Context saved locally upon explicit request; no new commit/tagg/push requested.

## Local build and installation workflow — 2026-10-08

The user explicitly requested that successful builds be copied to
Applications. Copy the complete PanoWizard.app bundle to
/Applications/PanoWizard.app so that the latest build is always there.
Use the build that just succeeded. The Release build at the time was at
/Users/magnus/Library/Developer/Xcode/PanoWizardBuilds/Release/PanoWizard.app.
Use a tool such as ditto and verify the installed version, build number,
and code signature. If the current build fails, do not copy an older build.
This workflow is a standing request and does not require confirmation for
each build.
Latest Release copied at the time: version 1.1, build 202610081849.

## .pw document icon and icon cache — 2026-10-08

An explicit document icon with weight corners, app tag and PW text has been
added as PanoWizard/PanoWizard/Resources/PWDocument.icns. Info.plist indicates
CFBundleTypeIconFile and UTTypeIconFile to PWDocument.icns and
LSTypeIsPackage=true. Release built, copied to /Applications/PanoWizard.app
(version 1.1, build 202610081849); codesign --verify --deep --strict succeeded.
The active Launch Services registration pointed right, but NSWorkspace still
gave the old app icon. Restarting Finder/ikonagent was not enough. Following the
user's follow-up, the user's two cache apps com.apple.iconservicesagent and
com.apple.iconservices were moved from DARWIN_USER_CACHE_DIR to
/tmp/pw-icon-cache-backup-20261008185507 and Finder was restarted.
NSWorkspace.icon(forFile:) then returned the new document icon for
/tmp/pw-icon-check.pw, visually verified. The user's real Finder view has not
been checked. No project documents were amended. No one commit/push.

## macOS generated .pw icon verified — 2026-10-08

Replace the conclusion and implementation of the previous icon notation. At the
user's request, UTTypeIcon was restored with UTTypeIconText=PW.
CFBundleTypeIconFile and UTTypeIconFile were removed; LSTypeIsPackage=true was
retained. After releasing build, copying to Applications, registering and
restoring the user's icon cache, NSWorkspace.icon(forFile:) now returns macOS'
own system-generated document icons with weight corners, app tag and PW text.
The result is visually verified on the test package /tmp/pw-icon-check.pw. The
previous own PWDocument.icns was therefore not necessary and has been removed
from the source tree. Cachebackup for this test:
/tmp/pw-system-icon-cache-backup-20261008190119. No one commit/push. The user's
actual project files have not changed.

## Standard text in the macOS generated document icon — 2026-10-08

UTTypeIconText=PW was removed at the user's request. UTTypeIcons is now an empty
dictionary; the file ending is still pw. The release build was successful and
copied to /Applications/PanoWizard.app: version 1.1, build 202610081904. The
code signature was verified. After registration and cache reset,
NSWorkspace.icon(forFile:) for /tmp/pw-icon-check.pw still displays PW in
versales, now as macOS default text without explicit text setting. Visualally
verified. Cachebackup: /tmp/pw-default-label-cache-backup-20261008190459. This
default setting has been maintained. No one commit/push.

## Checkpoint for documentation and construction routine — 2026-10-08

The user requested to save context + c+p. The checkpoints include CONTEXT.md and
Info.plist: macOS-generated document icons with default text and packet markup,
as well as the existing routine of copying successful builds to Applications.
The most recent installed and signature verified Release is 1.1 (202610081904).
Separate local changes to the MARKETING_VERSION, Xcode schematic formatting and
docs-copy/ are not included in this commit. Date tags are created according to
the saved c+p routine. Previous 'no commit/push' notes describe the situation of
each test.

## Updating and publishing of documentation — 2026-10-08

The user consented to the update of existing documentation without modifying the
app code. Getting Started follows Import → Create → Preview → Export. Existing
page structure retained; guides have current controls, technical requirements
separated from photo advice, current GUI images and real examples from N, U, V,
S and Z. The existing photographic image of the machine before-and-after examples is
kept and scanned without an old GUI. The AI example uses an already saved
repair; no new API calls were made. Retouch displays the base panorama, while
Preview displays active patches; the AI comparison is therefore captured in
Preview with identical direction and zoom. All 14 pages were rendered locally,
22 referenced images verified, internal links and git diff --check approved. App
files, original projects and docs-copy/ were verified unchanged against startup
checks. Existing local Xcode version or scheme changes is not included in the
documentation committee. The user then requested c+p and GitHub publication.
Pages are configured for main:/docs and published automatically after push. The
date tag is created according to the existing c+p routine.

## Global directions for HTML export — 2026-10-08

Two switches above Save HTML: Invert drag direction and Invert scroll zoom. Both
by default. @AppStorage/UserDefaults saves globally, not in projects. The HTML
export reads the selections and inserts fixed direction factors. Drag is
reversed on both shoulders, normal scrollzoom is reversed separately; the keypad
and keyboard retain their behavior. No settings panel in the exported display.
All four combinations were controlled via exported JavaScript and simulated
pan, scroll, and pinch events. Five existing PanoramaAdjustmentProcessorTests were
passed. GUI and global storage verified after restarting and switching G → N.
Release built and copied to /Applications/PanoWizard.app, build 202610082159;
code signature approved. Export guide and export picture updated locally. Before
restarting, the user's open G had unspent changes. They were preserved through
Save As to /Users/magnus/Desktop/Panorama/G/panowizard-before-html-settings.pw;
the original was not rewritten. The app now shows N's Export with both switches
off. No commit/push requested. Formerly Xcode version or scheme changes retained.

## This is the total amount of data that can be collected. — 2026-10-08

The user chose Drag to turn the camera and Scroll up to zoom in as text. The
drag-switch connection is unchanged. The display of the scroll switch is the
negation of invertScrollZoom, so on really means up = zoom in. Save the choices.
Standard with no saved options: pull, scroll on. It's the most unchanged.
Release build 202610082218 was successful, copied to Applications and the code
signature verified. Both texts and existing choices verified in the GUI. Export
guide and screenshot updated locally. No commit/push requested.

## Scroll down to zoom in — 2026-10-08

At the user's request, Scroll up to zoom in was replaced by Scroll down to zoom
in. Switch is now directly linked to invertScrollZoom again: off = existing
direction, on = down zooms in. Both switches are off by default. Global storage
is maintained. Release 202610082227 built, copied to Applications and signed.
GUI verified in O: both switches off and the new text appears. No commit/push.


## Modal start dialogue — 2026-10-08

At the request of the user, the welcome window was replaced by a fixed,
centralised start dialog. Create Your Panorama and Open Panorama... have the
same white button style. Quit is a regular SwiftUI button down there. No window
buttons or resize. AppKit runModal blocks menu commands until the user selects a
project or Quit. The interrupted file selection remains in the dialogue. After
the file selection has been approved, the mode is released before the
asynchronous import or opening; in case of error, the dialogue is resumed. The
size and restoration of the project window remain unchanged. Release
202610082315 built, copied to /Applications/PanoWizard.app and signed. GUI test:
open existing N, import a real N image to Untitled, disable file selection,
block Cmd-N, unreadable test image with error message and return to modal
dialog, and Quit. The temporary project was closed without saving; the original
projects were not rewritten. The start image and the name of the documentation
have been updated. No commit/push requested for the amendment.


## Three identical start buttons and a complete background — 2026-10-08

Quit now has the same white capsule, size and texture as create or open, with power
symbol. The background is located separately behind the fixed content surface
and also fills the safe-area of the dialogue; the empty ribbon at the bottom is
gone. Release built, copied to Applications and signed. Current GUI visually
checked and documentation starting image updated.


## Larger start dialog with transparent buttons — 2026-10-08

Open Existing Panorama replaces the previous text of the start button. All white
button backgrounds are 82% opaque. The content size of the dialog is calculated
from the visible surface of the current screen: 62% width and 68% height,
normally at least 800×560 and maximum 1100×740 points; smaller screens limit the
size so that it can be spaced. Release built, copied to Applications and signed.
GUI visually verified: greater dialogue, readable text and comprehensive
background. Start image and the start button of the project guide updated. No
commit/push requested.


## Vertical balance of the start dialog — 2026-10-08

Button backgrounds now have 74% opacity (26%) The free vertical space is divided
by a Spacer above the contents and two below, for 1/3–2/3-balans. Release built,
copied to Applications and signed. Visually checked and the documentation
starting image updated.


## Project windows are managed by SwiftUI/macOS — 2026-10-08

At the user's request, WindowStateRestores was removed entirely. ProjectWindow
no longer reads PanoWizard.ProjectWindow and does not use setFrameUsingName or
setFrameAutosaveName. SwiftUI/macOS performs recovery. Declaration defaultSize
and minimum working surface are maintained; the previously agreed layout of the
start dialog is unchanged. Release built and copied to Applications, code
signature and give diff --check approved. GUI verified by opening N: normal
project window, Ready 5 images. No commit/push requested.


## SwiftUI selects the starting size of project — 2026-10-08

At the user's request, DocumentGroup.defaultSize(1240×780) was also removed. No
own recovery or specified default size for project windows remains. The existing
minimum number of employees 900×600 shall be maintained. The design of the start
dialogue continues separately. Release built, copied to Applications, signed and
GUI-controlled by opening N (Ready 5 images).


## Start dialog closes after project selection — 2026-10-08

The user discovered that the welcome window was still behind the project.
Previous GUI checks verified project opening but missed the background window.
After successful opening and import the referenced NSWindow is now closed directly
with close() instead of dismissWindow, as the closable style of the dialog is
removed. The interrupted filval/fel maintains the dialogue as before. Release
built, installed in Applications and signature verified. GUI test with N: open
project and new app reading selects the project window, no remaining start
dialog.


## Checkpoint: Start dialog and window management of the system — 2026-10-09

The user agreed that SwiftUI/macOS will manage the size and position of the
project window; no window coordinates shall be stored in .pw at Save. The
request tag+c+p includes the latest design of the start dialog, corrected
closure after project selection, removed own window restoration and defaultSize
and corresponding documentation and context. The release build and GUI tests are
described above. Separate existing Xcode version or scheme changes and docs-copy/
are left outside this commit. Date marked according to Europe/Stockholm.


## Seven combined GUI changes — 2026-10-09

The user authorised a joint implementation according to the common list:
1. Zoom In/Out/Reset reaches the current visible ImageNavigationResponder also
   from the sidebar, with regular responder chain first and window image view as
   a fallback.
2. The locked side panel show/hide-knapp removed also in the sidebar column.
3. Normal project window size is stored globally in UserDefaults after manual
   resizing (didEndLiveResize). Only width and height, no position, no .pw content and
   no save requirements. No frame-autosave keys. Zoom and full screen remains the
   responsibility of macOS. This replaces yesterday's decision on a completely
   native size.
4. Images → Remove All... after Add... with Cancel/Remove All confirmation.
   Clears sources, masks, panorama and patches from the project, retains
   original files. I'm inactive without pictures.
5. The images menu shows only the file name, retains
   selection and Option-number shortcuts.
6. Preview-tommy: the eye symbol and No Panorama to Preview.
7. All three of the empty Create's use the board symbol and existing pill style.

Release built and copied to Applications, signature verified. 12
PanoProjectTests passes, including a new remove-all test that verifies that the
original file is preserved. Start mode hopes to overtake the XCTest host so
tests can start. GUI: zoom through the side-focus menu, remove toggle, clean
file name, Remove All Cancel, confirmation, or disabled state afterwards,
Preview/Retouch/Export-tomvyer. Manual resize gave 2222×1542 screen pixels and
the next new project exactly the same size. Project N's GUI removal was not
saved; N was reopened unchanged. Temporary Untitled projects were shut down
without savings. N is open. The source images guide describes Remove All. No
commit/push requested. Previous Xcode version or scheme changes and docs-copy/
have not been modified by this work.


## Simple project start-up and cleaner side panel — 2026-10-09

New list approved for simple overall implementation:
1. The separate welcome scene and modal AppKit loop removed entirely.
   DocumentGroup has defaultLaunchBehavior(.suppressed) to avoid automatic file
   selectors; appdelegate creates a normally empty document after startup if no
   documents are available. Starting XCTest will skip this.
2. The toggle of the sidebar is restored; NavigationSplitView gets a true State
   binding for columnVisibility instead of constant(.all). GUI verified the hide
   and show.
3. project.images.isEmpty is a common welcome permission in ContentView before
   the branches of the workvisions, both at start and Remove All, regardless of
   the chosen workvisions. Create a Panorama / Add overlapping photos, then
   create your panorama. The Add Images and Open Existing Panorama buttons...
   use existing style and importing or opening; no special mode or window.
4. Images/Panorama-indata/resultatgrupper retained. Bred Add Images... directly
   under the image heading. Create removed from the Panorama heading; menu and
   empty panorama views Create retained. No extra seat-holding.

Release built, installed in Applications and signature verified. 12
PanoProjectTests pass. GUI: empty project start without file picker or dialog,
toggle both directions, welcome view from Retouch, import of N image, Remove All
returns to welcome view, Open Existing Panorama opens N with five images. The
test project is temporary and shall not be saved; the original has not been
amended. The start guide texter/bilder and the relevant guides updated to the
new layout. No commit/push requested. Previous amendments to the seven-point
list were retained.


## Standing engineering principle: KISS — 2026-10-09

Magnus prefers the simplest solution and the simplest code that correctly
meets the requirements. Favor established platform patterns and default
behavior. Reuse existing solutions and avoid unnecessary special cases or
abstractions. Explain the cost of large changes and propose a simpler option
when one exists. If a request conflicts with an applicable standard or
regulation, say so and explain what is affected. This applies to future work.

## Standing test preference — 2026-10-09

Create or run automated regression tests only when Magnus explicitly asks.
Build checks and practical manual verification of requested changes remain
appropriate.

## Bred Create Panorama and photographic welcome view — 2026-10-09

Two approved listing points implemented under KISS. Create Panorama is widely
under Panorama, with the panel symbol, existing WorkspaceToolbarPillStyle and
model.stitch/canStitch; the same width as Add Images. Welcome view is reusing
existing Backgrounds/*.jpg. A static random NSImage is retained during the
session; no new storage, carousel, animation or dialogue. The background only
fills the empty project view and is 58% black, with white text and existing
button styles. No automated regression tests created or run. Release built,
copied to Applications and signed. GUI: background and readability, button width and
inactive button in empty project, opening of N and active button to start stitch
progression (hereafter discontinued). Start image and Create instructions
updated. No commit/push requested.


## Activation of menus and start documentation — 2026-10-09

The latest three-point list carried out according to KISS without automatic
regression tests. ImagesCommandActions canNavigateImage based on current image
view; Zoom In/Out/ Reset View is disabled without image, even in Export and
empty panorama views. Sidebar.onDeleteCommand gets nil when no source image is
selected, so AppKit grays Delete. No replacement of the default Edit menu or
text field response chain. Manually verified GUI: empty project has inactive
Zoom/Delete/Remove All and Panorama Create/Retouch/Preview/Export; Add works. J
opened and selected source image provides active Delete as well as active zoom
commands. The original design was not altered. Other
mask/skapande/exportkontroller retain existing terms of content. Documentation
examined: no remaining references to modal start dialogue. Getting Started and
Projects clarify normal project start-up with available menus; current
photographic start-up image updated. Release built, copied to Applications,
signature verified and diff-check approved. No one commit/push.


## Total checkpoint — 2026-10-09

The user requested t+p+c, interpreted as commit, annotated date tag and push to
origin/main. The checkpoints include current approved change lists, current
normal projektstart/fotografisk welcome view, sidebar and content-dependent
commands, global regular window size, Remove All and updated docs. KISS and no
automatic regression tests on its own initiative are permanent preferences;
previously added pre-test-preference remove-all tests are included in the
checkpoints. Last modification constructed and manually verified as above.
Existing separate Xcode version or scheme changes and docs-copy/ are omitted.


## In the case of a shortcut tcp — 2026-10-09

In the future, Magnus will use tcp for tag + commit + push. Practical order:
commit currently approved arbete/kontext, create annotated local date tag on the
new commit and push commit and tag. This checkpoint preserves the name; no new
changes since d615674. Separate Xcode changes and docs-copy/ are left out.


## Documentary images and commit/push — 2026-10-09

At the request, the unprinted backup docs-copy/ was deleted. The latest GUI
captured from the Applications app for Welcome View, Source Images, Preview,
Retouch, Export and Adjustments; docs/Images updated with six real screenshots.
The opening steps of the Little Planet guide reuse the current Export image. The
masking guide button name and navigation/starttext clarified. No app code
modified and no automatic regression tests run. Commit/push also includes the
previous local Xcode changes (version 1.1 and Xcode schedule formatting), upon
request to commit remaining work.


## Extra empty projects at file start — 2026-10-09

The startup documents.isEmpty could be checked while a .pw file was still open.
Minimum fix: applicationDidFinishLaunching now requires macOS
NSApplication.launchIsDefaultUserInfoKey == true before an empty project is
created. Existing suppressed strategy and deferred creation are maintained;
SwiftUI owns the file opening. Native untitled delegate attempts did not yield
any projects or file selectors and are not included in the final amendment.
Release built, installed in Applications and signature verified. Manual control:
normal appstart shows Untitled and the welcome view; after closing, N/panowizard.pw is
opened directly from Finder, and the Window menu lists only panowizard.pw, no
extra Untitled. The original design was not altered. No automated regression
tests, no commit/push requested.


## Randomness of each new project — 2026-10-09

EmptyProjectWelcomeView.backgroundImage changed from static let to local @State.
Each new welcome view chooses from existing jpg backgrounds, and SwiftUI keeps
the selection at reschedule. No global session cache or new storage. Release
built, installed and signature verified; manually verified that normal start
showed city image and File > New (Command-N) showed another square image in
Untitled 2. The slum allows the same image again. No automatic regression tests
and no commit/push requested.


## Unchanged new project not changed — 2026-10-09

isDirty now only compares workingDocument != savedDocument. The previous saveURL
== nil also made an entirely intact new project dirty. The change is a line.
Release built, installed and signed. Manual control: File > New followed by
Close closes without saving; import of a source image continues saving.
Temporary import projects closed without saving, the original was not amended.
You've got a clean welcome sign. No automated regression tests, no commit/push
requested.

## Open Example — 2026-10-09

File > Open Example uses SwiftUI NewDocumentAction for an unpublished example
copy of Panorama U. The user agreed that the last U was saved before restarting;
the original was saved via the app before copying resources. Packed material:
nine original images, red and green masks, panorama and two manual patches
(nadir and flagpole), approximately 95 MB. No local bookmarks or .DS_Store
included. Source images are copied once to the Application Support of the app so
your own saved projects do not depend on the bundle of the app. A new project
ID, title Example and Save suggests Example as the file name. docs/projects.md
documents the function. Manual verification found that the relative source
search paths via the /tmp symlink were wrong; calculation and reading now use
resolutionSymlinksInPath for bas/ursprung. Release built, installed and signed.
Manually verified example opening, nine source images and mask indicators, both active
patches, own file name in Save and successful reopening of separately saved
copy. There are no automatic regression tests. The amendments have not yet been
committed.


## Open Example after Open — 2026-10-09

Open Example is first in CommandGroup (replacing: .saveItem), before Close.
Native Open... is keeping the openDocument: Previous NSMenu moves gave the right
visual order but wrong SwiftUI action; it's been removed. Release built,
installed and signed. Verified menu order and that Open opens the file selector.

## UX with JPEG source images — 2026-10-09

The nine PNG source images in /Users/magnus/Desktop/Panorama/UX were converted
with sips to JPEG quality 95, unchanged resolution 2000 × 3008. project.json
updated to relative .jpg URLs; image ID and metadata remain. Internal
PNG-masker/panorama/patchar maintained according to the user's choice. Full
backup: /Users/magnus/Desktop/Panorama/UX-backup-before-jpeg. Source images are
75,5 MB → 18,2 MB. UX opened in installed PanoWizard, the UX folder authorized
in file selector. Verified nine JPEG source images, five mask markers and two
active manual patches. The original U is intact.


## UX as a built-in example and menu without separator — 2026-10-09

Bundled Example replaced by UX: nine JPEG source images plus existing panorama,
masks and two patches. Relative search paths, no bookmarks or .DS_Store.
Installed JPEG files hashed against UX; sample resources approximately 42 MB. An
existing menu delegate hides the separator immediately before Open Example
without moving menu items or changing actions. Release built, installed and
signed. Manually opened Example: nine .jpg, five mask markers, two active
patches. Command-O verified with regular file selectors. No commit/push.


## Restored patch management — 2026-10-09

At the request of the user, the last amendment and its regression test were
restored. Create Panorama cleans the patches again after successful stitching.
The UX model and the menu placement are retained.


## Warning before Create Panorama with retouch — 2026-10-09

All UI paths use AppModel.stitch, which now asks for confirmation of retouch
patches (also disabled). ContentView displays Create Panorama? with Cancel and
the destructive Create Panorama button; warns that patches are removed and
cannot be regretted. Only confirmation calls for stitch discarding retouch.
Without patches, the stitching starts right away. The regression test verifies
that the request does not start stitching or modify panorama/patchdata and that
even disabled patches provide a warning. Both retusts approved, release built
and signature verified. Installed without closing the user's open
project or save prompt.


## Checkpoint 2026-10-10-00-00

The user requested t+p+c: current UX example with nine JPEG images, Open Example
directly under Open without separator, and confirmation before Create Panorama
if retouch patches are available. The latest release build and both retusts
approved. Commit and annotate date to origin/main.


## Open Example removed — 2026-10-10

At the user's request, removed: menu point, separator management, newDocument
environment, example loader, Xcode resource references, all linked
exempelbilder/projekt and supporting documentation. The retrospective test now
uses synthetic data without sample dependency. Generic relative route management
is maintained. Historical context notes are preserved. Both retouching tests
approved; pure release build, installed and signature verified. Manually
verified the File menu without Open Example. The user's U/UX and already copied
source images in Application Support are retained so that saved projects can
continue to be opened. No one commit/push.


## Panorama selection of the siding panel disabled — 2026-10-10

Retouch/Preview/Export now uses the same terms as the menu: stitchedResultURL !=
nil. NavigationRow has disabled, selectionDisabled and reduced opacity for text
and icons when panorama is missing. Release built, installed and signed.
Manually verified that clicking all three in empty projects doesn't change the
view. No more tests. No commit/push.


## Checkpoint 2026-10-10-17-35

The user requested t+c+p. Removal of Open Example and its resources, independent
retrospective warning test and inactive sidebar selection before panorama is
available. Release built and installed, retusts approved and the sidebar's click
behavior manually verified. Committed with an annotated date tag to origin/main.


## Preview fills the workspace — 2026-10-10

PanoramaPreview uses SphericalPanoramaView without workspace padding and with
angular radius 0. Retuschvyn maintains its previous default values. Release
built, installed and signed. Manually verified with G/panowizard.pw that the
image reaches left or right and the edge under Adjustments and above the status
row, without rounded corners. The project didn't save. No new tests; no
commit/push.


## Checkpoint 2026-10-10-17-59

The user requested tcp for Preview without margins, rounded corners and shadows.
Release built and visually verified. Commit and annotate date to origin/main.


## Male mode: zoom anchor at sequence start — 2026-10-10

NativeImagePanMonitor now locks the mouse anchor at the first CMD zoom motion in
a scroll sequence, not at the CMD key press. Existing ImageSurfaceScrollGesture
maintains the anchor through direct gesture phases and momentum. New sequences
take on new anchors even with CMD. The zero-delta end phases update the sequence
status. The non-phase wheels use 0,25's inactivity for new sequences, so not
every wheel event changes anchors. Preview unchanged. Release built, installed
and signed; five existing ImageSurfaceInteractionTests approved. Physical CMD
scroll with the mouse moved between sequences not manually verified by the UI
tool. No commit/push.


## Maskzoom: explicit scrolling position after layout — 2026-10-10

The user is still experiencing an unclear zoom point. Zoom-onChange used
ScrollViewReader.scrollTo for a movable 1-pixel marker immediately after the
zoom was changed. Replace the zoom positioning with
scrollPosition.scrollTo(x:y:) calculated from locked image point and viewport
anchor. Waiting for new contentSize before positioning; handling centered image
and scroll boundaries explicitly. The anchor shall continue to lock at the start
of the sequence. Release built, installed and signed. Physical mouse behavior
remains to be verified. Open project or save prompt left. No commit/push.


## Additional movement space restored — 2026-10-10

The user requested to skip the last change. Additional viewport padding and
related contentSize change removed. Previous zoom anchors at sequence start and
explicit scroll position after layout remaining.


## Maskzoom with AppKit anchor and location — 2026-10-10

The user approved a new test following the analysis: also powerful zoom drives.
CMD scroll now reads image point through
AttachmentView.convert(event.locationInWindow) and viewport point through
NSClipView at sequence start. No SwiftUI ScrollGeometry is used for CMD anchors.
After updated image size, clip.bounds are corrected via the actual image point
position minus locked viewport point. NSView.layout and setFrameSize as well as
updateNSView schedule corrections by layout. The image tank is maintained
through the sequence in both zoom-in and zoom-out; normal scroll boundaries
remain, no extra canvas margins. Preview unchanged. The SwiftUI positioning
remains for tangentbordszoom/pinch/reset. Release built, installed and signed;
five existing interaction tests approved. Physical CMD scroll not yet manually
verified. No commit/push.


## Maskzoom: synchronous correction of the layout — 2026-10-10

The user confirmed the correct anchor principle but shaky zoom and asked for a
little trial, back at great complexity. The Async correction is removed.
AttachmentView.layout corrects immediately after super.layout; setFrameSize
marks needsLayout instead of correcting in advance. CMD scroll also marks
needsLayout; no correction in updateNSView. The experiment reduces the amount of
code. Release built, installed and signed. Project G left open, restart
required. Softness at physical CMD scroll remains to be verified. No
commit/push.


## CMD scroll is used correctly — 2026-10-10

The user confirmed good zoom, but reported pan at maxzoom.
NativeImagePanMonitor.install used self?.handle(event) ?? event, which restored
the event even when handle returned nil to use it. Changed to guard let self
else return event; return self.handle(event). CMD scrolling thus does not reach
the normal scroll view at zoom limits. Even their own pan events are consumed as
intended. Release built, installed and signed. The app hasn't restarted. Manual
control of maxzoom remains. No commit/push.


## Checkpoint 2026-10-10-20-28

The user requested tcp after verifying soft and correct mesh zoom in both
directions, stable image point and that maxzoom does not transition to pan.
Common image and scroll boundaries accepted. Release built and signed; five existing
interaction tests approved earlier in the work. Committed and annotated date to
origin/main.

## Open Recent with unique menu names — 2026-10-10

File → Open Recent added under Open. Use the existing history of NSD
DocumentController and the usual document opening. Just shows .pw projects,
removes double URLs and builds the shortest unique suffix of the search path for
each option. Full search path as a tooltip; Clear Menu clears the history. Tom
List has disabled No Recent Documents and Clear Menu. Implemented in
PanoWizardApp.swift with native submenu delegate. Name count verified for empty
lists, repeated parent scenes and rooted files. Release built, installed and
signed. Manually opened G from history and U via Open; the menu then shows
U/panowizard.pw and G/panowizard.pw. Projects not altered or saved.
docs/projects.md updated. No commit/push requested yet.

The user then set a maximum of 10 projects. The menu is limited after filtering
and deduplication, before calculating unique names.

## Preview navigation without unsupported status — 2026-10-10

At the user's request, ProjectDocumentScene.isDirty only ignores
project.previewViewpoint when compared to savedDocument. Full workingDocument is
still used at Save, even when iDirty is false. AppModel.setPanoramaViewpoint
does not change modifiedAt, so no other fields need to be excluded. Masks,
retouches and adjustments still affect unsupported status and closure warning.
docs/projects.md updated. Release built, installed and signature verified; give
diff --check approved. The app is not restarted; physical preview scroll remains
for the user to try. No commit/push requested.

## Panorama C regression and isolated AI retouch transfer — 2026-10-14

User tested fresh projects with all eight original C images. Confirmed good:
`c857861`, `b5c4a6e`, `b53b18e`, and `0600cf0`. Confirmed bad: `d2dd3e8`.
`0600cf0` and `d2dd3e8` are adjacent commits, locating the first observed
regression at `d2dd3e8`; no stitching repair is authorized in this task.

The former HEAD `a90d020` is preserved on
`codex/safety-before-restore-20261014-004036`. Its six uncommitted AI retouch
changes are preserved in stash `b1e3603eaab5498fcc380da6bec66029d379da2e`
and `/Users/magnus/Library/Developer/PanoWizardCheckpoints/restore-2026-10-12-02-24-20261014-004036`.

User authorized transferring only those six saved AI retouch changes onto
`0600cf0`. Active branch: `codex/ai-retouch-on-0600cf0`. Applied the exact diff
from `a90d020` to the saved stash, without later committed changes. The API now
receives the original unmasked patch image and a separate PNG mask, with painted
pixels transparent in the API mask. The default instruction explains that
original pixels are available as reference. OpenCV bridge and stitching services
are unchanged relative to `0600cf0`. User's panorama projects and originals must
remain untouched; user performs the real panorama C and live AI retouch checks.

Validation: 12 tests in OpenAIAIRetouchServiceTests and RetouchPatchServiceTests passed. Clean Release build succeeded; installed identical verified bundle in /Applications/PanoWizard.app and launched it. Real panorama C and live AI retouch remain user verification. No commit or push performed.

## Pan/zoom and mask gestures — 2026-10-15

User approved a simpler, consistent navigation model inspired by Google Maps:
drag to pan (drag rotates the spherical preview); scroll in any dominant axis
zooms without a modifier; trackpad pinch zooms. `Option`-drag paints masks and
`Command-Option`-drag erases; plain drag never changes a mask. Little Planet
now uses drag to rotate and click to set its center; its special Option-drag
and horizontal-scroll pan were removed. Exported HTML wheel zoom now also
uses the dominant scroll axis.

Implementation is currently uncommitted on local `main` (which was synced with
`origin/main` before this work). Changed navigation/gesture code in
ImageSurfaceInteraction.swift, PanoramaPreview.swift, PanoramaRetouchView.swift,
SphericalPanoramaView.swift, LittlePlanetExportSheet.swift, and
PanoramaExporter.swift; updated targeted tests, README, and help pages. Tests
and Debug build passed; built app copied to `/Applications/PanoWizard.app`
(bundle version `202610151915`). `git diff --check` passed. No commit or push.
Next conversation should continue from these uncommitted GUI/navigation changes;
the stitching engine was not modified.

## Publishing archive prepared — 2026-10-16

On Magnus’s request, created a Release archive of current clean commit `968bc96433826435f1fbc73ed495313fceebca77` for upload preparation. Version **1.1**, build **202610161843**, arm64. Archive: `/Users/magnus/Library/Developer/Xcode/Archives/2026-10-16/PanoWizard-1.1.xcarchive`. Archive succeeded; deep strict signature verification passed for app and embedded OpenCV libraries; sandbox entitlements verified. Archive has Apple Development signing; distribution signing/validation remains part of Xcode Organizer distribution. Existing actor-isolation warnings in PanoWizardApp.swift remain. No functional tests performed in this turn. No upload, App Review message, or resubmission performed. Build log: `/tmp/panowizard-1.1-archive.log`.

## App Store Connect follow-up — 2026-10-16

Apple rejected version 1.0 (202610080027) on October 15 under Guidelines 5 (China mainland/OpenAI references) and 2.1(a) (sample files needed). China mainland was deselected and saved; availability changed from 175 to 174 countries/regions. Public examples and instructions are at https://meg768.github.io/panowizard/examples.html and https://github.com/meg768/panowizard/tree/main/examples. User screenshots confirm a separate archive **1.1 (202610161844)** passed validation and was uploaded to Apple, then selected on the version page; export compliance warning was cleared. This is the uploaded build, distinct from the assistant-created 202610161843 archive above. Review Notes and revised store description were drafted in chat; saving all metadata and final version field were not independently verified. User chose to keep one store screenshot for 1.1. No new review submission or approval has been confirmed. Opening downloaded examples on another Mac remains unverified.

## Minimal navigation polish — 2026-10-16

On user request, replaced open/closed hand navigation cursors with default arrow in source-mask, spherical preview, and retouch surfaces; removed only the associated cursor push/pop state. Existing mask hide/unhide, transparent cursor, brush indicators, and modifier behavior retained. Shared scroll intent now ignores horizontal-dominant gestures (including pure horizontal); vertical zoom and inversion unchanged. Updated existing scroll regression test; all five ImageSurfaceInteractionTests passed. Release archive succeeded: version 1.1, build 202610161939, `/Users/magnus/Library/Developer/Xcode/Archives/2026-10-16/PanoWizard-1.1-polish.xcarchive`. No upload, submission, commit, or push performed for these changes. Manual visual verification remains outstanding.

## Local 360 zoom anchor lifecycle — 2026-10-16

On user request, changed only SphericalPanoramaView.swift for zoom lifecycle: pan/reset/keyboard zoom invalidate old anchors; phase-less wheel direction changes recapture the cursor point, retaining the 0.25-second pause threshold; pinch captures one fixed world direction and screen anchor per gesture instead of recapturing every event. Scroll momentum retains its original anchor. Projection math, source-image zoom and mask behavior unchanged. Release build succeeded in `/Users/magnus/Library/Developer/Xcode/PanoWizardLocalZoom`; installed `/Applications/PanoWizard.app` version 1.1 (202610161955) and strict deep signature verification passed. Original configured Release output failed directory creation; explicit local build output used instead. No new archive/upload/commit/push; user visual verification pending.

## Download Examples menu — 2026-10-16

User accepted trying Help → Download Examples… via default browser. Added one button beside PanoWizard Help opening https://github.com/meg768/panowizard/releases/download/examples-v1/PanoWizard-Examples.zip with NSWorkspace. Created public examples-v1 release targeting existing commit 8dd3078 (not marked latest) with only tracked examples A/B/C plus README in PanoWizard-Examples/; 51 files, 107033864 bytes. Local ZIP integrity passed, SHA-256 matches GitHub asset digest, public download URL returns HTTP 200. Release build 1.1 (202610162009) succeeded, installed at /Applications/PanoWizard.app, strict deep signing verified; Help menu item visually confirmed through accessibility. Actual browser download via menu remains for user testing; destination follows default browser preferences. No app archive/upload, commit, or push performed. GitHub release and asset have been published.

## Single examples.zip packaging — 2026-10-16

User explicitly requested removing the extra release copy, replacing examples/ with repository-root examples.zip, removing the Download section from the packaged README and reviewing README accuracy. Commit ef3a8da contains packaging, root README fixes, help download-link update and app menu URL update; previous navigation/zoom code remains uncommitted. ZIP has 51 entries under examples/, all three complete projects and JPEGs; 103253397 bytes (under GitHub 100 MiB file limit). Three saved panorama PNGs were losslessly recompressed to meet the limit; canonical decoded pixel hashes matched originals for A/B/C, JPEGs and all other project members unchanged. ZIP integrity, all entries and relative source references verified. Packaged README now covers opening, Grant Access, API requirements and safe experimentation without a Download section. Root README corrected external source references, project bookmarks, navigation and test-suite wording; docs/examples.md points directly to root ZIP. Unpacked local source folder preserved outside repository at /Users/magnus/Library/Developer/Xcode/PanoWizardExamples-source-backup-20261016. Release build 1.1 (202610162028) succeeded, signature verified, installed and started locally. Download URL: https://github.com/meg768/panowizard/raw/refs/heads/main/examples.zip.

Packaging publication verified: main at ef3a8daa6ab9c5becf988b81d2a329acdccc1c2e, root ZIP public URL HTTP 200. Deleted obsolete examples-v1 release and its tag/asset after replacement was live. GitHub accepted the 98.47 MiB archive with its standard >50 MiB advisory. Earlier App Review draft links to tree/main/examples must be replaced with the direct ZIP or examples help-page URL before submission.

## Restore editable examples folder — 2026-10-16

User rejected ZIP-only storage because A/B/C should remain easy to edit. Restored examples/ from preserved originals; verified every original project/image file byte-for-byte against 8dd3078 (README intentionally retains review fixes and no Download section). Removed root examples.zip; updated docs to repository ZIP download instructions and root README layout. Removed dead direct-download app URL: Help now shows Example Projects… opening the examples guide. Commit c0780c9 contains only restoration/docs/menu; earlier navigation/zoom changes remain uncommitted. Release build 1.1 (202610162035) succeeded, strict deep signature verification passed, installed locally. No archive or Apple upload. Earlier ZIP-only packaging entries are superseded.

## Automatic example ZIP publication — 2026-10-16

User accepted keeping editable examples/ while generating a download ZIP automatically, like rendered help. Added .github/workflows/examples.yml triggered by main pushes touching examples/** or workflow, plus manual dispatch. Ubuntu 24.04, pinned actions/checkout v6 commit, job-only contents:write, serialized publication. git archive packages only tracked examples/ files; unzip integrity check precedes upload. Creates/updates Examples release (tag examples), asset examples.zip, not marked latest. README explains maintenance; examples README retains no Download section. App Help → Download Examples… and help examples page use stable URL https://github.com/meg768/panowizard/releases/download/examples/examples.zip. Commits c1f528f and bbdaabf pushed to main; prior navigation/zoom edits still uncommitted. First publication and replacement run both succeeded (Actions runs 38949803446 and 38949928545); release notes identify current source commit bbdaabf13288120a70aa5fe0035c1659fa3eebf0. Local tracked-file ZIP integrity/set check passed (51 files). Release build 1.1 (202610162045) succeeded, installed and started; strict deep signature verification passed and menu confirmed. No Apple upload or archive.

Final published ZIP downloaded and verified: GitHub SHA-256 digest, ZIP integrity, entry set and byte-for-byte contents of all 51 tracked original files match.

Added per-click UUID query to app download URL (commit cb59d3e, pushed) because a replaced asset can leave stale signed redirects in caches. Canonical release path stays fixed; cache-busted download returned HTTP 200 and fully verified ZIP. Final local Release build 1.1 (202610162048) succeeded and was installed/signature verified.

## End-to-end example A update verified — 2026-10-16

User edited examples/A locally to add AI patch D30DEBAC-089E-48CF-BBED-72012EF4AA7B. Committed/pushed only examples/A in 39cc4cf. Automatic workflow run 38951529053 succeeded and replaced stable examples.zip asset. Downloaded final asset (113848090 bytes; SHA256 1ad6803cf69dcf4298e471e46c2ddb318e25bb165cbf73396612a13a8b45f5b4); digest, ZIP integrity and updated A project/new patch/new mask byte-for-byte contents verified. Existing downloaded copies are not auto-updated; user should Download Examples again and open the newly extracted A project. No app rebuild needed for changed examples.

## Help synchronized with example A AI patch — 2026-10-16

User confirmed automatic download contains A update and requested help review/corrections. Updated docs/examples.md counts and explanation (manual pole repair plus AI cobblestone ground repair), Getting Started, Masking rebuild warning for both patches, Manual Patch guide, AI Patch guide, and examples/README table. Refreshed a-retouch.jpg to show both patches and added a-ai-after.jpg from current app screenshots. Screenshots taken using disposable copied project, preserving tracked examples. All local Markdown links/images resolve; images visually inspected. Commit 6d49c78 pushed; example packaging workflow 38952186995 succeeded; Pages run 38952185983 publishing. No app code/build changes in this request.

Published help verified over HTTPS: examples, getting-started, Masking and AI Patch pages contain updated A descriptions and new image reference. Pages deploy job succeeded.

## Checkpoint — 2026-10-16 21:07 Europe/Stockholm

User requested commit/tag/push after confirming the updated A download and help changes. Checkpoint includes all pending navigation polish and zoom-anchor changes, tests and accumulated context. User verified source zoom and 360 zoom locally; latest installed local Release is 1.1 (202610162048). Five focused interaction tests previously passed; subsequent local Release builds/signature checks passed. Help and example packaging have already been published and verified. The uploaded Apple build 202610161844 predates these app changes; a new archive/upload is needed before submitting the current app. No Apple submission was performed.

## Printing with optional thumbnails — 2026-11-02

Generate thumbnail is now an AppStorage-pared cruise right under Filename,
default on. New PublishThumbnailRenderers use the system's WKWebView and exact
exported HTML, initial kamera/FOV, 640x360 perspective, canvas JPEG quality 0.8.
Save HTML/JPEG/PNG and Panorama Browser are unchanged. SFTPPublisher has
optional JPEG path with hidden staging, confirmed compensation and
backup and restoration. HTML success followed by JPEG-fel/avbrott is reported as
partial results. 11 tests run and approved (1 older local Paramiko integration
skipped): real WebKit camera projection at two FOVs, HTML export and SFTP
against saved servers, HTML-only, JPEG, denied or approved JPEG replacement and
missing local JPEG. Browsers verified both UTF-8 test publications and decoded
JPEG 640x360. Automatic test files removed, browser restored 36. No new
addictions. Signed Release 1.4 (202611021747) installed and binary and signature
verified. Back up:
/Users/magnus/Library/Developer/Xcode/PanoWizard-before-publish-thumbnail-20261102-174828.app.
Native dialog checked on available copy work/thumbnail-ui-A; the check box
appears as a checkbox directly under Filename, default on. Manuell Publish
started with 2008/zz-ui-thumbnail-20261102-1749-med.html; verification and cleanup of
it is ongoing. No commit/push. Previous amendments to the worktree were
preserved. Native Publish with the dashboard on was completed with Uploaded
successfully and both HTML and JPEG were on the server. These two temporary UI
test files are also deleted. The off-mode was tested by the automated SFTP
chain, not by a second manual button press. The test project is a copy
available.
