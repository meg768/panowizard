# How Do I Create an AI Patch?

An AI patch removes or repairs a small area of an otherwise finished panorama. The selected view is sent to OpenAI, but nothing is activated until you choose **Apply**.

## Choose the area

Open **Retouch**, then drag or scroll until the square view contains the problem. Command-scroll or pinch to zoom. Click **Add AI patch** when the area is framed correctly.

![Positioning the square view before creating an AI patch](Images/01-position-the-patch.png)

## Mask the problem

In **Before**, Option-drag over the object or damaged area that should be reconstructed. Command-Option-drag erases the mask, and Command-Z undoes the last stroke.

Keep the mask close to the problem while leaving enough surrounding image for context. Add a short instruction when the replacement must follow a specific structure, pattern, or texture, then click **AI Retouch**.

![A red mask over a bucket and the generated replacement floor](Images/02-mask-and-generate.png)

## Review and apply

Compare **Before** and **After**. Choose **Try Again** if the result is not convincing, or **Apply** to add it to the panorama.

![The finished floor in Panorama Preview](Images/03-result-in-preview.png)

The AI patch appears in the **Patches** list. You can hide it, edit it again, or delete it without changing the source images or panorama geometry.

[Back to PanoWizard Help](../../index.html)
