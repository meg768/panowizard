#ifndef OPEN_CV_BRIDGE_H
#define OPEN_CV_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    double coveragePercent;
    int holeCount;
    int usedAlignmentCache;
} PWStitchReport;

typedef void (*PWProgressCallback)(
    void *context,
    const char *stage,
    double fraction
);

typedef int (*PWCancellationCallback)(void *context);

int PWStitchPanorama(
    const char *const *imagePaths,
    const char *const *protectedMaskPaths,
    const unsigned char *compositionRoles,
    int imageCount,
    const char *alignmentCachePath,
    const char *outputPath,
    int outputWidth,
    void *callbackContext,
    PWProgressCallback progressCallback,
    PWCancellationCallback cancellationCallback,
    PWStitchReport *report,
    char **errorMessage
);

void PWFreeString(char *string);

#ifdef __cplusplus
}
#endif

#endif
