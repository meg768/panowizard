# Creating and Opening Projects

PanoWizard starts in a normal project window with an empty project. The welcome view stays inside that window, so the menus remain available. Click **Add Images…** to choose your source images. Choose **File → New** for another empty project. Use **Open Existing Panorama…** in the welcome view or **File → Open…** to open an existing `.pw` project.

For a finished project to explore, [download the examples](examples.html). Keep the entire example folder together and open its `panorama.pw`. To experiment, duplicate that whole folder first.

## Create a project from a finished panorama

Choose **File → New from Panorama…** and select a full 360° equirectangular PNG with a 2:1 aspect ratio. The new project opens in **Preview**. Use **Retouch** to add patches or **Export** to create an image or publish the interactive panorama.

Save the project as a `.pw` to keep the imported image and any edits together. The project can be reopened after the original PNG is moved.

## Open recent projects

**File → Open Recent** lists up to 10 recently opened or saved projects, newest first. Each entry shows the shortest trailing part of its path needed to distinguish it from the other entries. For example, two projects named `panorama.pw` can appear as `U/panorama.pw` and `G/panorama.pw`. More parent folders appear only when needed. Hover over an entry to see its full path.

**Clear Menu** clears the recent-project history without deleting any project files.

## Save your work

- **File → Save** (Command-S) saves the editable project.
- **File → Save As…** saves a separate copy, useful before changing sources or masks on a finished panorama.
- **File → Revert** discards changes since the last save, after confirmation.

Exporting JPEG, PNG, or HTML creates a finished output; it does not save the project.

Navigating or zooming in Preview does not mark the project as changed. Choose **Save** (Command-S) to remember the current view. Saving other edits also saves the current view; closing without saving restores the previously saved view next time.

A `.pw` project keeps the panorama, masks, patches, and editing settings. **Source photographs remain external**; saving does not copy them into the project. Keep the originals available. When moving work to another Mac, include the originals as well as the project.

If a project needs permission to read its photographs, follow [File Access / Grant Access](file-access.html).

Next: [Adding Source Images](source-images.html).

[Back to PanoWizard Help](index.html)
