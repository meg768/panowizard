# Creating the Panorama

Click **Create** beside **Panorama**, or choose **Panorama → Create**. PanoWizard analyzes the overlapping images, aligns them, and stitches the panorama in one operation. There is no separate Analyze step.

The progress dialog shows the current stage. Creation can take a few minutes; **Cancel** stops the operation. When complete, **Preview** opens. The current application creates a **4096 × 2048** panorama.

## Check the result

The status line reports coverage after creation. **100% coverage means source pixels are available everywhere, not that every seam is correct.** Reopened projects may show **Ready** instead. Always inspect the panorama yourself.

Areas without valid source coverage remain empty; stitching does not invent missing content. For a seam using unwanted content, adjust the [source masks](HowTo/Masking/index.html) and create again. A small remaining blemish can be repaired with a [manual patch](HowTo/ManualPatch/index.html) or [AI patch](HowTo/AIPatch/index.html).

**Source changes clear the panorama, patches, and adjustments. A successful new Create also clears patches and resets adjustments.** Finish source corrections before retouching and final color adjustments.

## If creation fails

Click **Show Details** in the status line to read the full error. Check that source files are available, enabled images have matching dimensions, and neighboring ring images overlap. Repair images cannot connect a broken ring. Include the error and your app version when [asking for help](support.html).

Next: [Preview and Navigation](preview.html).

[Back to PanoWizard Help](index.html)
