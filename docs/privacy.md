# Privacy Policy

Last updated: 8 October 2026

PanoWizard is developed by Magnus Egelberg. This policy describes how the app handles your information.

## Images and projects

Image inspection, panorama stitching, masks, manual retouching, previews, Little Planet, and export run locally on your Mac. These operations do not upload your photographs to the developer.

Source images remain in the locations you choose. A saved `.pw` project contains source references, editing settings, masks, generated panorama data, and retouch patches. It can also contain security-scoped bookmarks that let macOS restore access to your selected files or folders.

You choose where to save projects and exports. If you choose a folder managed by iCloud or another cloud service, that service may synchronize the files under its own settings and policies.

## Optional AI retouching

AI retouching uses OpenAI and requires your own OpenAI API key. When you request an AI retouch, PanoWizard sends the prepared image of the selected panorama view and the editing instruction to OpenAI over HTTPS. Your API key authenticates that request. The selected image can contain personal information visible in the photograph.

The developer does not operate an intermediary server for these requests. OpenAI processes the submitted data under its applicable terms and data policies. See [OpenAI's API data documentation](https://platform.openai.com/docs/guides/your-data). Do not submit images or instructions that you are not permitted to share with OpenAI.

You can use the local panorama tools without using AI retouching.

## Local settings and temporary files

PanoWizard stores preferences, including the OpenAI API key you enter, in the app's local settings on your Mac. The API key is currently stored in application preferences, rather than the macOS Keychain. It is not stored in the `.pw` project.

Image processing and retouching can create temporary working files on your Mac. Saved projects and exported files remain until you remove them. Deleting a project does not delete its external source photographs.

## Analytics and tracking

PanoWizard does not include developer-operated analytics, advertising, or tracking services. Apple may separately process purchase information and diagnostics according to your Apple account and system settings.

## Help and support

Opening Help launches the help website in your browser. The website is hosted on GitHub Pages, and support issues are hosted on GitHub; those services handle web requests and submitted information under [GitHub's privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).

Information you submit in a support issue is public and is used to respond to the issue. Never include API keys, private photographs, or other sensitive information. For questions about this policy, see [Support](support.html).

[Back to PanoWizard Help](index.html)
