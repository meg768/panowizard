# Explore the example panoramas

Start with a finished panorama, then inspect how its source photographs, masks, and retouch patches work together. These are the same downloadable projects used throughout this help, and are suitable for App Store Review.

## Download and open

1. Open the [PanoWizard repository on GitHub](https://github.com/meg768/panowizard) and choose **Code → Download ZIP**. No development tools are required.
2. Double-click the ZIP in Finder. Open the extracted repository folder, then **examples**.
3. Launch PanoWizard. Choose **File → Open…**, then select **panorama.pw** inside A, B, or C.
4. If prompted, select that same A, B, or C folder and click **Grant Access**. This lets macOS read the source photographs.
5. Choose **Panorama → Preview**. Drag to look around; scroll or pinch to zoom.

Keep each entire example folder together: the source JPEGs belong beside `panorama.pw`, not inside it. Moving the whole folder preserves the relative source references. Check the sidebar against the image counts below. See [File Access](file-access.html) if photographs are unavailable.

The saved panoramas and patches are ready to explore. No API key is needed to view or toggle existing AI patches. Only generating new AI results requires your own OpenAI API key and separately billed API usage.

**Before experimenting, duplicate the entire A, B, or C folder in Finder and open the copy.** Changing sources or source masks clears the panorama, patches, and adjustments; rebuilding also clears patches and resets adjustments.

<a id="example-a"></a>

## A — Church square

**9 JPEG photographs · 2 Exclude masks · 1 Include mask · 1 manual patch**

![Example A open in PanoWizard Preview](Images/Examples/a-preview.jpg)

Start here for [source masks](HowTo/Masking/index.html): select `2005-01-16 15-19-32.jpg` or `15-19-39.jpg` and choose **Exclude** to inspect the red masks over the hand and level. Select `2005-01-16 15-18-46.jpg` and choose **Include** to see the green mask preferring an intact pole.

Open **Retouch** to find the saved **Manual Patch**. Its thumbnail locates the repaired pole in Preview. Follow the [manual patch guide](HowTo/ManualPatch/index.html) to compare it with the unpatched view.

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

## Try the next step

- [Getting Started](getting-started.html): open a result or create a panorama from sources.
- [Preview and Adjustments](preview.html): explore the sphere and change its overall appearance.
- [Little Planet](HowTo/LittlePlanet/index.html): turn A into a square planet image.
- [Export](export.html): save an image or an interactive HTML viewer.

[Back to PanoWizard Help](index.html)
