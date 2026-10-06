# PanoWizard Help

PanoWizard creates complete 360° × 180° panoramas from one horizontal ring of overlapping fisheye photographs. It lets you inspect the result, correct source masks, apply local retouch patches, and export a panorama or Little Planet.

**Create a project → Add images → Create panorama → Preview → Correct if needed → Export**

## Create or open a project

Choose **Create Your Panorama** on the welcome screen to start, or **Open Panorama…** to open an existing `.pw` project. Save your work with **File → Save** (Command-S).

Source photographs remain external: saving a project does not copy them into `.pw`. Keep them available in their original locations. If PanoWizard needs permission to read them, a native folder picker opens at the expected source folder. Choose **Grant Access**, then save the project so that permission can be restored next time.

## Add source images

Click **Add** in the sidebar and select your image sequence. Use a complete overlapping 360° ring with enough vertical coverage for the full sphere. All images must have the same pixel dimensions; multi-row capture sets are not supported.

Select an image to inspect it. Check the order and, when needed, use **Automatic**, **Panorama Ring**, or **Repair Image** to describe its role. A repair image fills local missing coverage rather than adding another panorama row. Use the rotation button to correct an image's orientation without changing the original file.

## Analyze and stitch

Click **Create** beside **Panorama**. PanoWizard analyzes the overlapping images, aligns them, and stitches the panorama in one operation. There is no separate Analyze step to run first.

A full-resolution sequence can take a few minutes. When complete, inspect the result in **Preview**. Areas without valid source coverage remain empty; stitching does not invent missing content.

## Preview and navigation

Drag or use two-finger scroll to pan. Hold Command while scrolling, or pinch, to zoom. Command-Plus and Command-Minus zoom in and out; Command-0 resets the view.

Inspect seams, the horizon, moving subjects, and the top and bottom of the sphere. Open **Adjustments** for global light and color corrections. These adjustments are saved with the project and included in exports.

## Masks

Select a source image to edit its masks:

- **Exclude / red:** prevent unwanted pixels from being used.
- **Include / green:** prefer that image's content where sources overlap.
- **Option-drag:** paint the selected mask.
- **Command-Option-drag:** erase a mask.

Keep masks small enough to leave useful overlapping content. Click **Create** again to use the changed masks, then inspect the result.

**Recreating the panorama clears existing retouch results.** Make source-mask corrections before adding retouch patches when possible.

## Retouch patches

Open **Retouch** and position the square view over the area to repair.

For a **manual patch**, choose **Add manual patch**, then **Export…**. Edit the 2048 × 2048 PNG in an image editor, keeping its dimensions unchanged and leaving surrounding detail for blending. Return to PanoWizard, choose **Import…**, compare **Before** and **After**, and click **Apply**.

For an **AI patch**, choose **Add AI patch**, mask the unwanted area, and click **AI Retouch**. Review the result before choosing **Apply**. This feature requires your own OpenAI API key and sends the selected view to OpenAI.

Applied patches appear in the **Patches** list. You can enable or disable, edit, or delete them without changing the source photographs.

## Little Planet

In **Export**, choose **Create Little Planet…**. Pan horizontally to rotate the composition, click the panorama to choose the center, and use the slider to change the planet's size. Inspect the square preview, then click **Export…** to save a PNG.

## Export

Open **Export** and choose:

- **Save JPEG…** for a compact panorama image.
- **Save PNG…** for a lossless panorama image.
- **Save HTML…** for a self-contained interactive 360° viewer.

Choose **Size: Original** for the full stitched resolution. Standard panorama images use the 2:1 equirectangular format. Save the `.pw` project too if you want to continue editing later.
