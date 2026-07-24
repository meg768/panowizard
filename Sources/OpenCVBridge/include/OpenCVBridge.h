#ifndef OpenCVBridge_h
#define OpenCVBridge_h

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

bool PWStitchImages(
    const char * const *inputPaths,
    int inputCount,
    bool fisheyeInput,
    const char *outputPath,
    char **errorMessage
);

bool PWRepairNadir(
    const char *inputPath,
    const char *outputPath,
    char **errorMessage
);

bool PWApplyPanoramaRepair(
    const char *panoramaPath,
    const char *repairImagePath,
    const char *maskPath,
    const char *outputPath,
    char **errorMessage
);

void PWFreeString(char *string);

#ifdef __cplusplus
}
#endif

#endif
