# Regression panoramas

Current regression cases, separate from the bundled examples A–H.

| Case | Purpose | Sources |
| --- | --- | --- |
| A | Night scene; sparse blue-channel exposure measurements and Little Planet composition | Five Nikon D80 NEFs |
| B | Daylight comparison; unchanged rendering and source masks | Nine Nikon D70 JPEGs |

Open `A/panorama.pw` or `B/panorama.pw` and keep the containing case folder intact.
Source images, project metadata, masks, existing renders and retouch assets are
preserved as supplied. Native file-access bookmarks and Finder metadata are
excluded; PanoWizard may request access to the source folder when opening.

Use copies for experiments. Files here are snapshots, not synchronized with
Desktop/panorama. The bundled `examples/` download is maintained separately.

## Night A seam investigation checkpoint — 2026-11-19

A's saved 8484 × 4242 result was rendered with the zenith omitted. Its project
metadata currently enables all five sources with Automatic roles, so creating
the panorama again will produce a different result from the saved image.

Known comparisons, without manual masks:

- All five sources on Automatic: a displaced roof edge is visible.
- Disable source 5 (`2007-09-25 22-50-36.nef`): continuous roof, incomplete sky.
- Keep source 5 as Repair Image: continuous roof and almost complete coverage
  (40 uncovered pixels), but a hard tonal boundary remains at the zenith fill.

The remaining issue is in tone/detail blending; no engine correction is included
in this checkpoint. See the dated investigation entries in `../CONTEXT.md`.

Verify the supplied data files from this directory with:

```sh
shasum -a 256 -c SHA256SUMS
```
