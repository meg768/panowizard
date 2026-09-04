#ifndef OPEN_CV_BRIDGE_H
#define OPEN_CV_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    double coveragePercent;
    int holeCount;
    int usedAlignmentCache;
} PWTrialStitchReport;

typedef void (*PWTrialProgressCallback)(
    void *context,
    const char *stage,
    double fraction
);

typedef int (*PWTrialCancellationCallback)(void *context);

int PWStitchTrialPanorama(
    const char *const *imagePaths,
    const char *const *protectedMaskPaths,
    const unsigned char *compositionRoles,
    int imageCount,
    const char *alignmentCachePath,
    const char *outputPath,
    int outputWidth,
    void *callbackContext,
    PWTrialProgressCallback progressCallback,
    PWTrialCancellationCallback cancellationCallback,
    PWTrialStitchReport *report,
    char **errorMessage
);

void PWFreeString(char *string);

#ifdef __cplusplus
}
#endif

#endif
