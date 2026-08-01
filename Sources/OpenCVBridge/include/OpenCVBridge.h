#ifndef OPEN_CV_BRIDGE_H
#define OPEN_CV_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    double yaw;
    double pitch;
    double roll;
} PWOrientation;

typedef struct {
    int firstImage;
    int secondImage;
    double firstX;
    double firstY;
    double secondX;
    double secondY;
} PWControlPoint;

typedef struct {
    double h00;
    double h01;
    double h02;
    double h10;
    double h11;
    double h12;
    double h20;
    double h21;
    double h22;
    int matchedFeatureCount;
    double localViewFieldOfView;
} PWNadirRegistration;

int PWGenerateRingControlPoints(
    const char *const *imagePaths,
    const double *nominalYaws,
    int imageCount,
    double horizontalFieldOfView,
    PWControlPoint **controlPoints,
    int *controlPointCount,
    char **errorMessage
);

int PWGeneratePairControlPoints(
    const char *firstImagePath,
    const char *secondImagePath,
    int firstImageIndex,
    int secondImageIndex,
    int ringImageCount,
    double horizontalFieldOfView,
    PWControlPoint **controlPoints,
    int *controlPointCount,
    char **errorMessage
);

int PWGenerateZenithControlPoints(
    const char *const *ringImagePaths,
    const PWOrientation *ringOrientations,
    int ringImageCount,
    const char *zenithImagePath,
    double horizontalFieldOfView,
    PWOrientation *zenithOrientation,
    PWControlPoint **controlPoints,
    int *controlPointCount,
    char **errorMessage
);

int PWRegisterNadirRepair(
    const char *panoramaPath,
    const char *repairImagePath,
    const char *repairExclusionMaskPath,
    double horizontalFieldOfView,
    double polePitchDegrees,
    const char *overlayOutputPath,
    PWNadirRegistration *registration,
    char **errorMessage
);

int PWGeneratePoleControlPoints(
    const char *panoramaPath,
    const char *repairImagePath,
    double horizontalFieldOfView,
    double polePitchDegrees,
    const char *baseOutputPath,
    const char *repairOutputPath,
    PWControlPoint **controlPoints,
    int *controlPointCount,
    char **errorMessage
);

int PWSolvePoleControlPoints(
    const PWControlPoint *controlPoints,
    int controlPointCount,
    PWNadirRegistration *registration,
    double *errors,
    char **errorMessage
);

int PWRenderNadirRepairOverlay(
    const char *repairImagePath,
    const char *repairExclusionMaskPath,
    double horizontalFieldOfView,
    const PWNadirRegistration *registration,
    const char *overlayOutputPath,
    char **errorMessage
);

int PWPrepareNadirRepairBlend(
    const char *panoramaPath,
    const char *repairImagePath,
    const char *repairExclusionMaskPath,
    double horizontalFieldOfView,
    double polePitchDegrees,
    const PWNadirRegistration *registration,
    double translationX,
    double translationY,
    double rotationDegrees,
    double scale,
    const double *cornerOffsets,
    const double *contentBounds,
    const char *baseOutputPath,
    const char *repairOutputPath,
    char **errorMessage
);

int PWFinishNadirRepairBlend(
    const char *blendedLocalPath,
    const char *overlayOutputPath,
    char **errorMessage
);

void PWFreeControlPoints(PWControlPoint *controlPoints);
void PWFreeString(char *string);

#ifdef __cplusplus
}
#endif

#endif
