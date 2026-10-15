# PanoWizard examples

Three complete examples for App Store Review and learning PanoWizard. Each folder contains the source photographs and a saved `panorama.pw` project with a finished panorama.

| Example | Scene | Source photographs | Project to open |
| --- | --- | --- | --- |
| A | Outdoor square and church | 9 JPEGs | `A/panorama.pw` |
| B | View over Paris | 8 PNGs | `B/panorama.pw` |
| C | Bathroom interior | 7 PNGs | `C/panorama.pw` |

## Download

1. Open the [PanoWizard repository](https://github.com/meg768/panowizard).
2. Click **Code → Download ZIP**.
3. Double-click the downloaded ZIP in Finder to extract it, then open the extracted folder's `examples` folder.

Keep each example folder intact. Its photographs must stay beside `panorama.pw`; downloading only the project is not sufficient. You can move or copy the whole A, B, or C folder anywhere on your Mac.

## Open an example

1. Launch PanoWizard and choose **File → Open…**.
2. In the downloaded `examples` folder, open A, B, or C and select **panorama.pw**. Click **Open**. Treat this project package as one file; do not open its internal contents.
3. If PanoWizard asks for permission to read the source photographs, select that same A, B, or C folder and click **Grant Access**.
4. Check that the sidebar contains the source count listed above. Choose **Panorama → Preview** to explore the saved panorama: drag to look around and scroll or pinch to zoom.

The panorama is already created, so rebuilding it is optional. No API key is needed to open or explore these examples, including their saved retouching. Generating new AI retouching requires your own OpenAI API key.

## File notes

Source-image references are relative to the example folder. The `.pw` package contains the saved panorama, masks, and retouch patches; keep these even though they are generated images.

Each project's `source-access.json` contains access bookmarks from the original Mac, including absolute paths. These permissions may not transfer to another Mac; use **Grant Access** as described above. Opening on a separate Mac has not yet been verified.

The hidden `.panorama-cache` folders are unnecessary legacy caches. They and Finder's `.DS_Store` files are excluded from Git downloads. Any local copies can be ignored; neither is needed to use the examples.
