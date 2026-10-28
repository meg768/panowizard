# PanoWizard examples

Seven complete examples for App Store Review and learning PanoWizard. Each folder contains the source photographs and a saved `panorama.pw` project with a finished panorama.

| Example | Scene | Source photographs | Saved retouching | Project to open |
| --- | --- | --- | --- | --- |
| A | Outdoor square and church | 9 JPEGs | Manual pole repair and AI ground repair | `A/panorama.pw` |
| B | View over Paris | 8 JPEGs | Manual sky repair and AI ground reconstruction | `B/panorama.pw` |
| C | Bathroom interior | 7 JPEGs | AI floor repair | `C/panorama.pw` |
| D | City square and fountain | 11 JPEGs | One saved AI patch | `D/panorama.pw` |
| E | Ski slope | 9 JPEGs | One saved manual patch | `E/panorama.pw` |
| F | Snowy outdoor terrace | 6 Nikon NEF RAW files | No retouch patches | `F/panorama.pw` |
| G | Autumn garden | 6 Nikon NEF RAW files | AI nadir and zenith reconstruction | `G/panorama.pw` |

F uses NEF RAW source files and no AI. Its tripod is hidden using only a green Include mask that favors existing source pixels during stitching.

G has no separate downward-facing (nadir) or upward-facing (zenith) source photograph. Two saved AI patches in Replace mode reconstruct the grass and fallen leaves below the camera and the branches and leaves above it. Toggle each patch in Retouch and click its thumbnail to compare the same area in Preview. No API key is needed to explore the saved results.

Keep each example folder intact. Its source photographs must stay beside
`panorama.pw`. You can move or copy the whole A, B, C, D, E, F, or G folder anywhere on your Mac.

## Open an example

1. Launch PanoWizard and choose **File → Open…**.
2. In the extracted `examples` folder, open A, B, C, D, E, F, or G and select **panorama.pw**. Click **Open**. Treat this project package as one file; do not open its internal contents.
3. If PanoWizard asks for permission to read the source photographs, select that same A, B, C, D, E, F, or G folder and click **Grant Access**.
4. Check that the sidebar contains the source count listed above. Choose **Panorama → Preview** to explore the saved panorama: drag to look around and scroll or pinch to zoom.

The panorama is already created, so rebuilding it is optional. No API key is needed to open or explore these examples, including their saved retouching. Generating new AI retouching requires your own OpenAI API key, internet access, and separately billed OpenAI API usage.

## File notes

Source-image references are relative to the example folder. The `.pw` package contains the saved panorama, masks, and retouch patches; keep these even though they are generated images.

macOS may ask you to grant access to the source photographs on your Mac. Follow
the Grant Access step above. Source photographs remain external to the project;
do not move or delete them independently.

## Experiment safely

Duplicate the entire A, B, C, D, E, F, or G folder before making changes. Changing source
images or source masks can invalidate the saved panorama and its retouching.
Rebuilding a panorama clears retouch patches and resets global adjustments.

No development tools are required to use these examples.
