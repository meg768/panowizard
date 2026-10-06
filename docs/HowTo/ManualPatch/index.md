# How Do I Create a Manual Patch?

A manual patch repairs a small area of an otherwise finished panorama with an external image editor. It does not alter the source images, masks, or panorama geometry.

## Choose the area

Open **Retouch**, then drag or scroll until the square view contains the problem. Command-scroll or pinch to zoom. Click **Add manual patch** when the area is framed correctly.

![Positioning the square view in Retouch](Images/01-position-the-patch.png)

## Export and edit

Click **Export…** to save the captured view as a 2048 × 2048 PNG. Open that file in your preferred image editor and repair the problem.

Keep the image dimensions unchanged and leave unedited image content around the repair. This gives PanoWizard enough surrounding detail to blend the patch cleanly.

## Import and apply

Return to PanoWizard, click **Import…**, and select the edited PNG. Compare **Before** and **After**, then click **Apply**.

![Comparing the original view and edited manual patch](Images/02-export-edit-import.png)

The patch appears in the **Patches** list. You can temporarily hide it, edit it again, or delete it without changing the underlying panorama.

[Back to PanoWizard Help](../../index.html)
