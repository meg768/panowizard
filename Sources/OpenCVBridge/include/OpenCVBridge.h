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

void PWFreeControlPoints(PWControlPoint *controlPoints);
void PWFreeString(char *string);

#ifdef __cplusplus
}
#endif

#endif
