# Explore the example panoramas

Start with a finished panorama, then inspect how its source photographs, masks, and retouch patches work together. These are the same downloadable projects used throughout this help, and are suitable for App Store Review.

## Download and open

1. Choose **Help → Download Examples…** in PanoWizard, or download [examples.zip](https://github.com/meg768/panowizard/releases/download/examples/examples.zip). No development tools are required.
2. Double-click **examples.zip** in Finder and open the extracted **examples** folder.
3. Launch PanoWizard. Choose **File → Open…**, then select **panorama.pw** inside A, B, C, D, E, F, or G.
4. If prompted, select that same A, B, C, D, E, F, or G folder and click **Grant Access**. This lets macOS read the source photographs.
5. Choose **Panorama → Preview**. Drag to look around; scroll or pinch to zoom.

Keep each entire example folder together: the source photographs belong beside `panorama.pw`, not inside it. Moving the whole folder preserves the relative source references. Check the sidebar against the image counts below. See [File Access](file-access.html) if photographs are unavailable.

The saved panoramas and patches are ready to explore. No API key is needed to view or toggle existing AI patches. Only generating new AI results requires your own OpenAI API key and separately billed API usage.

**Before experimenting, duplicate the entire A, B, C, D, E, F, or G folder in Finder and open the copy.** Changing sources or source masks clears the panorama, patches, and adjustments; rebuilding also clears patches and resets adjustments.

<a id="example-a"></a>

## A — Church square

**9 JPEG photographs · 2 Exclude masks · 1 Include mask · 1 manual patch · 1 AI patch**

![Example A open in PanoWizard Preview](Images/Examples/a-preview.jpg)

Start here for [source masks](HowTo/Masking/index.html): select `2005-01-16 15-19-32.jpg` or `15-19-39.jpg` and choose **Exclude** to inspect the red masks over the hand and level. Select `2005-01-16 15-18-46.jpg` and choose **Include** to see the green mask preferring an intact pole.

Open **Retouch** to find the saved **Manual Patch**. Its thumbnail locates the repaired pole in Preview. Follow the [manual patch guide](HowTo/ManualPatch/index.html) to compare it with the unpatched view.

A also contains an **AI Patch** repairing the cobblestone ground directly below the camera. Click its thumbnail to look down at the repair, then toggle it off and on to compare. Both saved patches can be inspected without an API key. See the [AI patch guide](HowTo/AIPatch/index.html) before generating a new result.

![Example A with its saved AI ground repair visible](Images/Examples/a-ai-after.jpg)

*The cobblestone repair is generated content, not recovered source pixels.*

<a id="example-b"></a>

## B — Paris from above

**8 JPEG photographs · Exclude masks on all 8 sources · 1 manual patch · 1 AI patch**

![Example B with both saved patches in Retouch](Images/Examples/b-retouch.jpg)

Select the source photographs to inspect their red masks. In **Retouch**, the two patches can be toggled independently. Click each thumbnail to locate its area in Preview: the manual patch is at the sky and the AI patch is at the ground below the camera.

![Example B with its saved AI reconstruction visible](Images/Examples/b-ai-after.jpg)

The downward AI patch reconstructs the Eiffel Tower from above. This is generated content, not a recovered photograph or a guarantee of architectural accuracy. B is useful for exploring several corrections in one project; C provides a simpler AI repair exercise.

<a id="example-c"></a>

## C — Bathroom floor

**7 JPEG photographs · no source masks · 1 AI patch**

![Example C with the saved floor repair in Preview](Images/Examples/c-preview.jpg)

Open **Retouch**, then click the **AI Patch** thumbnail to look down at the mosaic floor. Toggle that patch off and on to compare the camera support with the saved repair. See the [AI patch guide](HowTo/AIPatch/index.html) for the mask and matching before/after images.

<a id="example-d"></a>

## D — City square and fountain

**11 JPEG photographs · 9 Exclude masks · no Include masks · 1 AI patch**

![Example D open in PanoWizard Preview, showing the square and fountain](Images/Examples/d-preview.jpg)

*Preview shows the saved panorama with its AI patch enabled. The Before and After images below show the ground repair.*

Explore the square, fountain, and patterned paving in **Preview**. Select the source photographs and choose **Exclude** to inspect the nine saved red masks.

Open **Retouch** and click the saved **AI Patch** thumbnail to locate its area in Preview. Toggle the patch off and on to compare. The saved patch is enabled and can be explored without an API key; generating a new result requires your own API key and separately billed usage. AI retouching is generated content, not recovered source pixels.

| Before | After |
| --- | --- |
| ![Example D before AI retouching, with the tripod area marked by a red mask](Images/Examples/d-ai-before.png) | ![Example D after AI retouching, with the stone paving reconstructed](Images/Examples/d-ai-after.png) |

*Before (left): the red mask marks the tripod area. After (right): AI removes the tripod and reconstructs the curved boundaries between the dark and light stones, continuing the surrounding paving pattern. The reconstructed area is AI-generated content.*

To make a similar repair, mask the unwanted object or artifact and choose **Replace**. Describe the surface that should take its place and the details that must continue across the repair. For example:

> Remove the tripod and its support inside the masked area. Replace them with stone paving that continues the surrounding pattern. Follow the curved boundaries between the dark and light stones, keeping their width, direction, and perspective consistent. Match the surrounding stone size, texture, lighting, and color. Preserve the unmasked surroundings.

Naming the paving pattern gives AI more useful guidance than simply asking it to “remove artifacts.” See [Write a useful instruction](HowTo/AIPatch/index.html#write-a-useful-instruction) for more examples.

<a id="example-e"></a>

## E — Ski slope

**9 JPEG photographs · 2 Exclude masks · 1 Include mask · 1 manual patch · no AI patches**

![Example E open in PanoWizard Preview, showing the snow-covered restaurant beside the ski slope](Images/Examples/e-preview.jpg)

Explore the ski slope and surrounding buildings in **Preview**. Select `2005-04-06 14-57-30.jpg` or `2005-04-06 14-57-37.jpg` and choose **Exclude** to inspect the red source masks. Select `2005-04-06 14-58-13.jpg` and choose **Include** to inspect the green source mask. See the [Masks guide](HowTo/Masking/index.html) for how these masks guide overlapping image selection.

Open **Retouch** and click the **Manual Patch** thumbnail to locate its area in Preview. Toggle the patch off and on to compare the saved repair. E provides another example of [manual retouching](HowTo/ManualPatch/index.html), without AI-generated patches.

<a id="example-f"></a>

## F — Snowy outdoor terrace

**6 Nikon NEF RAW photographs · no Exclude masks · 1 Include mask · no retouch patches**

![Example F open in PanoWizard Preview, showing the seated people on the snowy terrace and its six NEF source files in the sidebar](Images/Examples/f-preview.jpg)

Explore the terrace, seated people, and surrounding buildings in **Preview**. F uses Nikon D80 NEF RAW source photographs, unlike the JPEG sources in A–E and G. Keep all six `.NEF` files beside `panorama.pw`.

**No AI was used in F.** The tripod is hidden using only a green **Include** mask, which favors existing pixels from an overlapping source photograph. There are no manual or AI retouch patches.

Select `2008-02-23 14-47-40.NEF` and choose **Include** to inspect that saved green source mask. See the [Masks guide](HowTo/Masking/index.html) for how Include masks influence seam selection.

<a id="example-g"></a>

## G — Autumn garden

**6 full-resolution JPEG photographs · no source masks · 2 AI patches · no manual patches**

![Example G open in PanoWizard Preview, showing an autumn garden and six source photographs](Images/Examples/g-preview.jpg)

G uses full-resolution JPEG sources converted from Nikon NEF originals. Keep all six `.JPG` files beside `panorama.pw`. The saved G panorama is **12288 × 6144 pixels**; its source JPEGs retain their full **4000 × 6000** resolution.

G shows how AI retouching can complete both ends of a panorama from a single horizontal ring of photographs. There is **no separate nadir photograph** looking straight down and **no separate zenith photograph** looking straight up. Two saved AI patches in **Replace** mode reconstruct those areas: grass and fallen leaves below the camera, and branches and leaves above it.

### Nadir — looking straight down

| Before | After |
| --- | --- |
| ![Example G looking down with the nadir AI patch disabled, showing missing coverage in the ground](Images/Examples/g-nadir-before.jpg) | ![The same nadir view with the saved AI patch enabled, continuing the grass and fallen leaves](Images/Examples/g-nadir-after.jpg) |

### Zenith — looking straight up

| Before | After |
| --- | --- |
| ![Example G looking up with the zenith AI patch disabled, showing missing coverage in the tree canopy](Images/Examples/g-zenith-before.jpg) | ![The same zenith view with the saved AI patch enabled, continuing branches and autumn leaves](Images/Examples/g-zenith-after.jpg) |

*Before: missing source coverage appears as a dark gap. After: the saved AI patches complete the ground and tree canopy. The reconstructed areas contain generated content.*

Open **Retouch** to find the two **AI Patch** entries. The first is the nadir repair; the second is the zenith repair. Click each thumbnail to locate its area in **Preview**. Return to Retouch, switch that patch off, and click its thumbnail again to inspect the same view before retouching. Repeat with the switch on. The patches can be toggled independently, and viewing the saved results requires no API key.

To inspect a saved mask and instruction, click the patch’s pencil button and choose **Cancel** when finished. Both saved patches use the default **Replace** instruction. See [AI Retouch](HowTo/AIPatch/index.html) to try this on a copy of the project.

G demonstrates reconstruction of missing coverage at both poles, beyond removing a small object. Stitching itself does not create that content; AI retouching adds it afterward.

## Try the next step

- [Getting Started](getting-started.html): open a result or create a panorama from sources.
- [Preview and Adjustments](preview.html): explore the sphere and change its overall appearance.
- [Little Planet](HowTo/LittlePlanet/index.html): turn A into a square planet image.
- [Export](export.html): save an image or an interactive HTML viewer.

[Back to PanoWizard Help](index.html)
