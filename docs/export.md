# Export

Open **Export** and choose:

- **Save JPEG…** for a compact panorama image.
- **Save PNG…** for a lossless panorama image.
- **Save HTML…** for a self-contained interactive 360° viewer.

![Current export options](Images/04-export.png)

## Image size and quality

JPEG and PNG use the **2:1 equirectangular** format: the whole sphere laid out as a rectangle. It looks stretched in an ordinary image viewer.

**Size: Original** preserves the panorama's existing dimensions. New panoramas are **4096 × 2048**; **4096 px** and **2048 px** choose the image width. **JPEG Quality** affects JPEG only.

![The coastal panorama as a flat 2:1 image](Images/00-finished-panorama.jpg)

## Interactive viewer

Before **Save HTML…**, use **Drag to turn the camera** to make dragging turn the viewing direction, or **Scroll down to zoom in** to choose downward scrolling for zooming in. Pinch zoom keeps its normal direction. Both switches are off by default. Both choices are saved globally for future exports, not in the project. The exported viewer uses your chosen directions.

The HTML file includes the panorama and opens in a browser with WebGL support, without extra image files. It starts at the direction and zoom chosen in Preview. Drag to look around and scroll or pinch to zoom. Saving HTML does not publish it online.

Enabled patches and global adjustments are included in exports. Save the `.pw` project separately if you want to continue editing.

For a square planet image, see [Little Planet](HowTo/LittlePlanet/index.html).

[Back to PanoWizard Help](index.html)
