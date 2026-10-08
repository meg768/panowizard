# Mask source images

Masks help when a seam selects unwanted content and another source photograph has a better view. This example removes a hand and level from the ground below the camera.

![The hand and level before source-mask corrections](Images/01-problem-before-masking.png)

## Exclude unwanted content

Select the source image, choose **Exclude**, then **Option-drag** over the unwanted area.

**Red / Exclude:** do not use these source pixels.

![A current Exclude mask over the hand and level](Images/02-exclude-mask.png)

## Prefer the best overlap

Select a source with the best overlapping content, choose **Include**, and Option-drag over that area. This separate example prefers one intact pole.

**Green / Include:** prefer these existing pixels when choosing overlapping content. It does not create missing content.

![A current Include mask preferring one intact pole](Images/03-include-mask.png)

## Rebuild and inspect

Click **Create** again, then inspect the same place in **Preview**.

![The same ground view after source-mask corrections](Images/04-result-after-masking.png)

*Ground before and after exclusion masks and a new Create. These corrections use real source photographs.*

A small remaining camera-footprint gap can be repaired with a [manual patch](../ManualPatch/index.html).

**Changing masks clears the panorama, patches, and adjustments. A successful new Create also clears patches and resets adjustments.** Finish masks before retouching. Save a separate project with **File → Save As…** before trying masks on a finished result.

## Refine a mask

- Plain drag or scroll moves the image; hold Command while scrolling to zoom in for finer painting.
- **Command-Option-drag** erases. **Edit → Undo Mask Change** (Command-Z) undoes the last source-mask change for the selected image.
- **Clear** removes the selected image's current mask type: Exclude or Include.

Keep masks small. If exclusion leaves uncovered areas, reduce it or supply a source with replacement coverage.

[Back to PanoWizard Help](../../index.html)
