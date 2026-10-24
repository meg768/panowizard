# Mask source images

A source mask guides which real photograph supplies overlapping pixels. Use [example A](../../examples.html#example-a) to inspect both red and green masks. Its nine source photographs and saved project are included in the download.

## Inspect the red masks

Open **A/panorama.pw**. Select `2005-01-16 15-19-32.jpg` in the sidebar, then choose **Exclude**. A red mask covers the hand and level. The next photograph, `2005-01-16 15-19-39.jpg`, has another red mask.

**Red / Exclude:** do not use these source pixels.

![The saved red Exclude mask on A's eighth source photograph](../../Images/Examples/a-exclude.jpg)

## Inspect the green mask

Select `2005-01-16 15-18-46.jpg` and choose **Include**. The green mask follows one intact pole, preferring it over competing overlap.

**Green / Include:** prefer these existing pixels when choosing overlapping content. It does not create missing content.

![The saved green Include mask on A's third source photograph](../../Images/Examples/a-include.jpg)

Selecting an image or switching Exclude/Include lets you inspect masks without repainting them.

## Create your own masks

**Duplicate the entire A folder before changing masks. Changing masks clears the panorama, patches, and adjustments. A successful new Create also clears patches and resets adjustments.** Finish masks before retouching.

- Choose **Paint** (the default) or **Lasso**, independently of **Exclude** / **Include**.
- With **Paint**, **Option-drag** paints as before; brush size follows the existing zoom behavior.
- With **Lasso**, **Option-click** adds a corner and **Option-drag** traces a freehand segment. Mix straight and curved edges in one selection. Moving the pointer previews the next edge; releasing the mouse keeps the outline open.
- Press **Return / Enter**, **Option-double-click**, or **Option-click the first point** to close and fill the selection with the current mask mode. Only the outline appears while editing; the filled mask has sharp edges without feathering.
- **Backspace** removes the last corner or entire freehand segment. **Esc** cancels without changing the mask. Changing image, tool or mask mode also discards an unfinished selection. Zooming and panning preserve it. Tiny or line-only paths do nothing. Paths extending outside the image are clipped to its bounds.
- The latest operation wins: red replaces green, green replaces red, and Paint and Lasso can overwrite each other.
- Drag without Option to pan. Scroll or pinch to zoom.
- **Command-Option-drag** removes painted masking. To erase a lassoed area, start the selection with **Command-Option-click/drag** and complete it normally.
- **Edit → Undo Mask Change** (Command-Z) undoes the last source-mask change for the selected image. Each completed lasso is one undo operation.
- **Clear** removes the selected image's current mask type: Exclude or Include.

Keep masks small. Exclude unwanted content only where another source offers replacement coverage. If holes remain, reduce exclusion or supply a suitable source photograph.

## Rebuild and inspect

In your practice copy, click **Create Panorama** again. Inspect the ground and pole in **Preview**. Mask changes affect the newly stitched result; they do not repaint the saved panorama directly.

![The saved panorama in example A](../../Images/Examples/a-panorama.jpg)

*The downloadable finished A project includes source masks, a manual patch at the pole, and an AI patch on the ground. Rebuilding applies the masks but removes both retouch patches; the two results need not look identical.*

For more masks, inspect [example B](../../examples.html#example-b): each of its eight source images has an Exclude mask.

![An Exclude mask on B's first source photograph](../../Images/Examples/b-exclude.jpg)

[Example E — Ski slope](../../examples.html#example-e) provides another project with both mask types: two Exclude masks and one Include mask across nine source photographs. Its example guide lists the photographs to select. Duplicate the E folder before experimenting; rebuilding clears its saved manual patch.

Next: [Create a manual patch](../ManualPatch/index.html).

[Back to PanoWizard Help](../../index.html)
