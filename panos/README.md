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

Verify the supplied data files from this directory with:

```sh
shasum -a 256 -c SHA256SUMS
```
