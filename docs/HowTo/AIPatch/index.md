# Create an AI patch

An AI patch changes a small area of an otherwise finished panorama. The captured image, mask, and active instruction are sent to OpenAI. The result stays a preview until you choose **Apply**.

## Explore the saved repair in example C

[Download and open example C](../../examples.html#example-c). It has seven source JPEGs and one saved AI patch repairing the mosaic floor below the camera.

1. Open **Retouch** and find **AI Patch** in **Patches**.
2. Click its thumbnail to locate the floor in Preview.
3. Return to Retouch and switch the patch off, then click the thumbnail again to inspect the same area without the repair. Repeat with the switch on.

![Example C's saved AI patch in Retouch](../../Images/Examples/c-retouch.jpg)

![The same floor view with the AI patch disabled on the left and enabled on the right](../../Images/Examples/c-ai-comparison.jpg)

*Left: the camera support is visible. Right: the saved AI result continues the mosaic floor. The source images are unchanged.*

Viewing and toggling the saved patch requires no API key and makes no generation request. To inspect its saved mask and instruction, click its pencil button; choose **Cancel** to leave it unchanged. Do not choose **Try Again** unless you intend to generate a new result.

## Before generating a new repair

AI retouch requires internet access and your own OpenAI API key. API usage is billed separately by OpenAI; it is not included in a ChatGPT or Codex subscription.

Use **Create API Key…** in the patch dialog to open setup, then **Open OpenAI API Keys…** to obtain a key, or paste one you already have. **Change API Key…** replaces it. **Usage…** opens the usage dashboard. For data handling, see [Privacy Policy](../../privacy.html).

## Choose the area

Open **Retouch**, frame the problem in the square view, and click **Add AI patch**. Drag to pan; scroll or pinch to zoom without a modifier.

Use a copy of the entire C folder when practicing, so the finished example stays available.

The dialog contains a fixed capture. Its pan/zoom controls inspect that image; cancel and reposition in Retouch to capture a different area.

## Mask and generate

In **Before**, **Option-drag** over the problem. **Command-Option-drag** erases; **Command-Z** undoes a stroke. **Clear Mask** removes the mask. Transparent gaps are selected automatically in a new patch.

Choose **Replace** to generate content for the masked area, or **Repair** to fix it while preserving as much of its visible original content as possible. New patches start in **Replace** mode. Each mode has its own editable instruction. Switching modes keeps both texts; the reset button restores the default instruction for the selected mode. Only the active instruction is sent to OpenAI.

For example, use **Replace** when something is missing: “Fill the masked area with the same wooden floor pattern as the surrounding boards.” Use **Repair** when the original is visible but needs correction: “Remove the dark stain from the floor. Keep the existing board pattern and preserve the rest of the image.”

When editing an existing patch, its selected mode and both instructions are restored. Choosing **Apply** saves the selected mode and both instruction texts with that patch, so you can return to either mode later without losing edits.

Click **AI Retouch** to generate a preview. A mask and a nonempty active instruction are required; generation may take a while and can be cancelled.

## Review and apply

Inspect lines, textures, color, and the repair boundary in **After**. AI can invent plausible but incorrect details. Choose **Try Again** for another attempt, or **Apply** to keep the result.

![The saved mask and result in C's AI Retouch Patch dialog](../../Images/Examples/c-ai-dialog.jpg)

*The red mask selects the camera support in Before; After contains the saved generated floor repair. An AI repair is generated content, not recovered source pixels.*

[Example A](../../examples.html#example-a) also includes a saved AI repair of the cobblestone ground below the camera, alongside its manual pole repair. Click the **AI Patch** thumbnail in A to locate it, then compare with the patch switched off and on.

[Example B](../../examples.html#example-b) includes a more ambitious AI reconstruction of the Eiffel Tower from above, alongside a manual patch. Inspect it as generated content, not as evidence of the tower's exact appearance.

In **Patches**, use the switch to hide/show a repair, click its thumbnail to locate it, or use the pencil/trash button to edit/delete it. Finish source corrections first: changing sources or masks clears patches. Save the project to keep an accepted repair.

[Back to PanoWizard Help](../../index.html)
