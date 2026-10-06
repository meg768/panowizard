# File Access / Grant Access

Source photographs remain external to the `.pw` project. PanoWizard needs macOS permission to read them.

When you select source images normally, PanoWizard remembers the required access when you save your project.

## When a folder picker appears

If required source images cannot be read because permission is missing, PanoWizard opens the native folder picker at the expected source folder.

1. Choose the folder containing the source images and click **Grant Access**.
2. If images are in other folders that also need permission, authorize each requested folder in turn.
3. PanoWizard retries reading the images. Once the project opens, save it with **File → Save** (Command-S).

The saved project remembers the authorization, so reopening it should not ask again while the source images remain available in those locations. Older projects can gain this access information when you authorize and save them.

Granting access does not copy, move, or embed any photographs. Keep the original files available; folder authorization cannot restore a missing file.

See [Creating and Opening Projects](projects.html).

[Back to PanoWizard Help](index.html)
