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
    int imageCount,
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
    const char *overlayOutputPath,
    PWNadirRegistration *registration,
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
    const PWNadirRegistration *registration,
    double translationX,
    double translationY,
    double rotationDegrees,
    double scale,
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
