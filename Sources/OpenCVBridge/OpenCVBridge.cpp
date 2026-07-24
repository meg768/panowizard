#include "OpenCVBridge.h"

#include <opencv2/features2d.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <map>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace {

constexpr int panoramaWidth = 2400;
constexpr int panoramaHeight = panoramaWidth / 2;
constexpr double maximumPositionError = 120.0;
constexpr double pi = 3.14159265358979323846;

struct NormalizedFeatures {
    std::vector<cv::KeyPoint> keypoints;
    cv::Mat descriptors;
};

struct MatchedPoint {
    cv::DMatch match;
    double positionError;
};

double radians(double degrees) {
    return degrees * pi / 180.0;
}

cv::Matx33d rotationMatrix(const PWOrientation &orientation) {
    const double yaw = radians(orientation.yaw);
    const double pitch = radians(orientation.pitch);
    const double roll = radians(orientation.roll);

    const cv::Matx33d yawRotation(
        std::cos(yaw), 0.0, std::sin(yaw),
        0.0, 1.0, 0.0,
        -std::sin(yaw), 0.0, std::cos(yaw)
    );
    const cv::Matx33d pitchRotation(
        1.0, 0.0, 0.0,
        0.0, std::cos(pitch), -std::sin(pitch),
        0.0, std::sin(pitch), std::cos(pitch)
    );
    const cv::Matx33d rollRotation(
        std::cos(roll), -std::sin(roll), 0.0,
        std::sin(roll), std::cos(roll), 0.0,
        0.0, 0.0, 1.0
    );
    return yawRotation * pitchRotation * rollRotation;
}

cv::Point2d sourcePoint(
    const cv::Point2f &panoramaPoint,
    const cv::Size &sourceSize,
    double horizontalFieldOfView,
    const PWOrientation &orientation
) {
    const double longitude =
        panoramaPoint.x / panoramaWidth * (2.0 * pi) - pi;
    const double latitude =
        pi / 2.0 - panoramaPoint.y / panoramaHeight * pi;
    const cv::Vec3d worldRay(
        std::sin(longitude) * std::cos(latitude),
        -std::sin(latitude),
        std::cos(longitude) * std::cos(latitude)
    );
    const cv::Vec3d cameraRay =
        rotationMatrix(orientation).t() * worldRay;
    const double angle = std::acos(
        std::clamp(cameraRay[2], -1.0, 1.0)
    );
    const double sine = std::sin(angle);
    if (std::abs(sine) < 1e-7) {
        return cv::Point2d(sourceSize.width / 2.0, sourceSize.height / 2.0);
    }

    const double focalLength =
        (sourceSize.width / 2.0)
        / radians(horizontalFieldOfView / 2.0);
    const double scale = focalLength * angle / sine;
    return cv::Point2d(
        sourceSize.width / 2.0 + cameraRay[0] * scale,
        sourceSize.height / 2.0 + cameraRay[1] * scale
    );
}

void makeSourceMap(
    const cv::Size &sourceSize,
    double horizontalFieldOfView,
    const PWOrientation &orientation,
    cv::Mat &mapX,
    cv::Mat &mapY,
    cv::Mat &validMask
) {
    mapX.create(panoramaHeight, panoramaWidth, CV_32F);
    mapY.create(panoramaHeight, panoramaWidth, CV_32F);
    validMask.create(panoramaHeight, panoramaWidth, CV_8U);

    const cv::Matx33d inverseRotation = rotationMatrix(orientation).t();
    const double focalLength =
        (sourceSize.width / 2.0)
        / radians(horizontalFieldOfView / 2.0);

    for (int y = 0; y < panoramaHeight; ++y) {
        float *mapXRow = mapX.ptr<float>(y);
        float *mapYRow = mapY.ptr<float>(y);
        unsigned char *maskRow = validMask.ptr<unsigned char>(y);
        const double latitude = pi / 2.0 - y / double(panoramaHeight) * pi;
        const double cosineLatitude = std::cos(latitude);
        const double worldY = -std::sin(latitude);

        for (int x = 0; x < panoramaWidth; ++x) {
            const double longitude =
                x / double(panoramaWidth) * (2.0 * pi) - pi;
            const cv::Vec3d worldRay(
                std::sin(longitude) * cosineLatitude,
                worldY,
                std::cos(longitude) * cosineLatitude
            );
            const cv::Vec3d cameraRay = inverseRotation * worldRay;
            const double angle = std::acos(
                std::clamp(cameraRay[2], -1.0, 1.0)
            );
            const double sine = std::sin(angle);
            double sourceX = sourceSize.width / 2.0;
            double sourceY = sourceSize.height / 2.0;
            if (std::abs(sine) >= 1e-7) {
                const double scale = focalLength * angle / sine;
                sourceX += cameraRay[0] * scale;
                sourceY += cameraRay[1] * scale;
            }

            mapXRow[x] = float(sourceX);
            mapYRow[x] = float(sourceY);
            maskRow[x] =
                sourceX >= 0.0
                && sourceX < sourceSize.width - 1.0
                && sourceY >= 0.0
                && sourceY < sourceSize.height - 1.0
                && angle < pi / 2.0
                ? 255
                : 0;
        }
    }
}

NormalizedFeatures normalizedFeatures(
    const std::string &imagePath,
    const cv::Size &requiredSize,
    double horizontalFieldOfView,
    const PWOrientation &orientation,
    const cv::Ptr<cv::SIFT> &detector
) {
    const cv::Mat sourceImage = cv::imread(imagePath, cv::IMREAD_GRAYSCALE);
    if (sourceImage.empty()) {
        throw std::runtime_error("Kunde inte läsa " + imagePath + ".");
    }
    if (sourceImage.size() != requiredSize) {
        throw std::runtime_error("Alla bilder måste ha samma pixelstorlek.");
    }

    cv::Mat mapX;
    cv::Mat mapY;
    cv::Mat validMask;
    makeSourceMap(
        requiredSize,
        horizontalFieldOfView,
        orientation,
        mapX,
        mapY,
        validMask
    );
    cv::Mat normalizedImage;
    cv::remap(
        sourceImage,
        normalizedImage,
        mapX,
        mapY,
        cv::INTER_LINEAR,
        cv::BORDER_CONSTANT,
        cv::Scalar(0)
    );
    cv::Mat visiblePixels;
    cv::compare(normalizedImage, 3, visiblePixels, cv::CMP_GE);
    cv::bitwise_and(validMask, visiblePixels, validMask);

    NormalizedFeatures result;
    detector->detectAndCompute(
        normalizedImage,
        validMask,
        result.keypoints,
        result.descriptors
    );
    if (result.descriptors.empty()) {
        throw std::runtime_error(
            "För få bilddetaljer hittades i " + imagePath + "."
        );
    }
    return result;
}

std::vector<cv::DMatch> mutualRatioMatches(
    const cv::Mat &descriptorsA,
    const cv::Mat &descriptorsB
) {
    cv::BFMatcher matcher(cv::NORM_L2);
    std::vector<std::vector<cv::DMatch>> forward;
    std::vector<std::vector<cv::DMatch>> backward;
    matcher.knnMatch(descriptorsA, descriptorsB, forward, 2);
    matcher.knnMatch(descriptorsB, descriptorsA, backward, 2);

    std::map<int, cv::DMatch> acceptedForward;
    std::map<int, cv::DMatch> acceptedBackward;
    for (const auto &matches : forward) {
        if (
            matches.size() == 2
            && matches[0].distance < 0.88f * matches[1].distance
        ) {
            acceptedForward[matches[0].queryIdx] = matches[0];
        }
    }
    for (const auto &matches : backward) {
        if (
            matches.size() == 2
            && matches[0].distance < 0.88f * matches[1].distance
        ) {
            acceptedBackward[matches[0].queryIdx] = matches[0];
        }
    }

    std::vector<cv::DMatch> result;
    for (const auto &[queryIndex, match] : acceptedForward) {
        const auto reverse = acceptedBackward.find(match.trainIdx);
        if (
            reverse != acceptedBackward.end()
            && reverse->second.trainIdx == queryIndex
        ) {
            result.push_back(match);
        }
    }
    return result;
}

double wrappedDistance(const cv::Point2f &first, const cv::Point2f &second) {
    double horizontal = std::abs(first.x - second.x);
    horizontal = std::min(horizontal, panoramaWidth - horizontal);
    return std::hypot(horizontal, first.y - second.y);
}

std::vector<cv::DMatch> geometricMatches(
    const NormalizedFeatures &featuresA,
    const NormalizedFeatures &featuresB
) {
    std::vector<MatchedPoint> candidates;
    for (
        const cv::DMatch &match :
        mutualRatioMatches(featuresA.descriptors, featuresB.descriptors)
    ) {
        const double error = wrappedDistance(
            featuresA.keypoints[match.queryIdx].pt,
            featuresB.keypoints[match.trainIdx].pt
        );
        if (error < maximumPositionError) {
            candidates.push_back({match, error});
        }
    }
    std::sort(
        candidates.begin(),
        candidates.end(),
        [](const MatchedPoint &left, const MatchedPoint &right) {
            if (left.positionError != right.positionError) {
                return left.positionError < right.positionError;
            }
            return left.match.distance < right.match.distance;
        }
    );

    std::vector<cv::DMatch> selected;
    for (const MatchedPoint &candidate : candidates) {
        const cv::Point2f pointA =
            featuresA.keypoints[candidate.match.queryIdx].pt;
        const cv::Point2f pointB =
            featuresB.keypoints[candidate.match.trainIdx].pt;
        const bool duplicate = std::any_of(
            selected.begin(),
            selected.end(),
            [&](const cv::DMatch &existing) {
                const cv::Point2f existingA =
                    featuresA.keypoints[existing.queryIdx].pt;
                const cv::Point2f existingB =
                    featuresB.keypoints[existing.trainIdx].pt;
                return std::abs(pointA.x - existingA.x) < 4.0f
                    && std::abs(pointA.y - existingA.y) < 4.0f
                    && std::abs(pointB.x - existingB.x) < 4.0f
                    && std::abs(pointB.y - existingB.y) < 4.0f;
            }
        );
        if (!duplicate) {
            selected.push_back(candidate.match);
            if (selected.size() == 60) {
                break;
            }
        }
    }
    return selected;
}

void appendControlPoints(
    int firstImage,
    int secondImage,
    const NormalizedFeatures &firstFeatures,
    const NormalizedFeatures &secondFeatures,
    const std::vector<cv::DMatch> &matches,
    const cv::Size &sourceSize,
    double horizontalFieldOfView,
    const PWOrientation &firstOrientation,
    const PWOrientation &secondOrientation,
    std::vector<PWControlPoint> &destination
) {
    for (const cv::DMatch &match : matches) {
        const cv::Point2d firstPoint = sourcePoint(
            firstFeatures.keypoints[match.queryIdx].pt,
            sourceSize,
            horizontalFieldOfView,
            firstOrientation
        );
        const cv::Point2d secondPoint = sourcePoint(
            secondFeatures.keypoints[match.trainIdx].pt,
            sourceSize,
            horizontalFieldOfView,
            secondOrientation
        );
        destination.push_back({
            firstImage,
            secondImage,
            firstPoint.x,
            firstPoint.y,
            secondPoint.x,
            secondPoint.y
        });
    }
}

char *copiedString(const std::string &value) {
    char *result = static_cast<char *>(std::malloc(value.size() + 1));
    if (result != nullptr) {
        std::memcpy(result, value.c_str(), value.size() + 1);
    }
    return result;
}

int copyResult(
    const std::vector<PWControlPoint> &points,
    PWControlPoint **controlPoints,
    int *controlPointCount,
    char **errorMessage
) {
    if (
        controlPoints == nullptr
        || controlPointCount == nullptr
        || errorMessage == nullptr
    ) {
        return 0;
    }
    *errorMessage = nullptr;
    *controlPointCount = int(points.size());
    *controlPoints = static_cast<PWControlPoint *>(
        std::malloc(points.size() * sizeof(PWControlPoint))
    );
    if (*controlPoints == nullptr && !points.empty()) {
        *errorMessage = copiedString("Minnet räckte inte för kontrollpunkterna.");
        *controlPointCount = 0;
        return 0;
    }
    if (!points.empty()) {
        std::memcpy(
            *controlPoints,
            points.data(),
            points.size() * sizeof(PWControlPoint)
        );
    }
    return 1;
}

cv::Size sourceSizeForPath(const char *path) {
    const cv::Mat image = cv::imread(path, cv::IMREAD_GRAYSCALE);
    if (image.empty()) {
        throw std::runtime_error(
            "Kunde inte läsa " + std::string(path) + "."
        );
    }
    return image.size();
}

} // namespace

int PWGenerateRingControlPoints(
    const char *const *imagePaths,
    int imageCount,
    double horizontalFieldOfView,
    PWControlPoint **controlPoints,
    int *controlPointCount,
    char **errorMessage
) {
    try {
        if (imagePaths == nullptr || imageCount < 2) {
            throw std::runtime_error(
                "Minst två horisontella bilder krävs."
            );
        }
        cv::setNumThreads(1);
        cv::setRNGSeed(0);
        const cv::Size sourceSize = sourceSizeForPath(imagePaths[0]);
        const cv::Ptr<cv::SIFT> detector = cv::SIFT::create(
            16000,
            3,
            0.012,
            12
        );

        std::vector<PWOrientation> orientations;
        std::vector<NormalizedFeatures> features;
        for (int index = 0; index < imageCount; ++index) {
            const PWOrientation orientation = {
                index * 360.0 / imageCount,
                0.0,
                0.0
            };
            orientations.push_back(orientation);
            features.push_back(normalizedFeatures(
                imagePaths[index],
                sourceSize,
                horizontalFieldOfView,
                orientation,
                detector
            ));
        }

        std::vector<PWControlPoint> result;
        for (int first = 0; first < imageCount; ++first) {
            const int second = (first + 1) % imageCount;
            const std::vector<cv::DMatch> matches = geometricMatches(
                features[first],
                features[second]
            );
            if (matches.size() < 6) {
                throw std::runtime_error(
                    "För få säkra träffar mellan bild "
                    + std::to_string(first + 1)
                    + " och "
                    + std::to_string(second + 1)
                    + "."
                );
            }
            appendControlPoints(
                first,
                second,
                features[first],
                features[second],
                matches,
                sourceSize,
                horizontalFieldOfView,
                orientations[first],
                orientations[second],
                result
            );
        }
        return copyResult(
            result,
            controlPoints,
            controlPointCount,
            errorMessage
        );
    } catch (const std::exception &error) {
        if (errorMessage != nullptr) {
            *errorMessage = copiedString(error.what());
        }
        if (controlPoints != nullptr) {
            *controlPoints = nullptr;
        }
        if (controlPointCount != nullptr) {
            *controlPointCount = 0;
        }
        return 0;
    }
}

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
) {
    try {
        if (
            ringImagePaths == nullptr
            || ringOrientations == nullptr
            || ringImageCount < 2
            || zenithImagePath == nullptr
            || zenithOrientation == nullptr
        ) {
            throw std::runtime_error("Zenitunderlaget är ofullständigt.");
        }
        cv::setNumThreads(1);
        cv::setRNGSeed(0);
        const cv::Size sourceSize = sourceSizeForPath(ringImagePaths[0]);
        const cv::Ptr<cv::SIFT> detector = cv::SIFT::create(
            16000,
            3,
            0.012,
            12
        );

        std::vector<NormalizedFeatures> ringFeatures;
        for (int index = 0; index < ringImageCount; ++index) {
            ringFeatures.push_back(normalizedFeatures(
                ringImagePaths[index],
                sourceSize,
                horizontalFieldOfView,
                ringOrientations[index],
                detector
            ));
        }

        std::vector<PWOrientation> candidates;
        for (double pitch : {90.0, -90.0}) {
            for (double roll : {0.0, 90.0, 180.0, 270.0}) {
                candidates.push_back({0.0, pitch, roll});
            }
        }

        int bestScore = -1;
        NormalizedFeatures bestFeatures;
        std::vector<std::vector<cv::DMatch>> bestMatches;
        PWOrientation bestOrientation = candidates[0];
        for (const PWOrientation &candidate : candidates) {
            NormalizedFeatures candidateFeatures = normalizedFeatures(
                zenithImagePath,
                sourceSize,
                horizontalFieldOfView,
                candidate,
                detector
            );
            std::vector<std::vector<cv::DMatch>> pairMatches;
            int score = 0;
            for (const NormalizedFeatures &ring : ringFeatures) {
                pairMatches.push_back(
                    geometricMatches(ring, candidateFeatures)
                );
                score += int(pairMatches.back().size());
            }
            if (score > bestScore) {
                bestScore = score;
                bestOrientation = candidate;
                bestFeatures = std::move(candidateFeatures);
                bestMatches = std::move(pairMatches);
            }
        }
        if (bestScore < 12) {
            throw std::runtime_error(
                "Zenitbilden kunde inte placeras tillförlitligt."
            );
        }

        std::vector<PWControlPoint> result;
        int connectedImages = 0;
        for (int index = 0; index < ringImageCount; ++index) {
            if (bestMatches[index].size() < 4) {
                continue;
            }
            ++connectedImages;
            appendControlPoints(
                index,
                ringImageCount,
                ringFeatures[index],
                bestFeatures,
                bestMatches[index],
                sourceSize,
                horizontalFieldOfView,
                ringOrientations[index],
                bestOrientation,
                result
            );
        }
        if (connectedImages < 2) {
            throw std::runtime_error(
                "Zenitbilden överlappar för få ringbilder."
            );
        }

        *zenithOrientation = bestOrientation;
        return copyResult(
            result,
            controlPoints,
            controlPointCount,
            errorMessage
        );
    } catch (const std::exception &error) {
        if (errorMessage != nullptr) {
            *errorMessage = copiedString(error.what());
        }
        if (controlPoints != nullptr) {
            *controlPoints = nullptr;
        }
        if (controlPointCount != nullptr) {
            *controlPointCount = 0;
        }
        return 0;
    }
}

void PWFreeControlPoints(PWControlPoint *controlPoints) {
    std::free(controlPoints);
}

void PWFreeString(char *string) {
    std::free(string);
}
