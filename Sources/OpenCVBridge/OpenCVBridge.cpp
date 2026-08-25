#include "OpenCVBridge.h"

#include <opencv2/calib3d.hpp>
#include <opencv2/features2d.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <limits>
#include <map>
#include <set>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace {

constexpr int panoramaWidth = 2400;
constexpr int panoramaHeight = panoramaWidth / 2;
constexpr int repairLocalViewSize = 1600;
constexpr double repairLocalViewFieldOfView = 120.0;
constexpr double pi = 3.14159265358979323846;
// PTGui's calibrated circular crop for the Sigma 8 mm / Nikon DX source
// is 11.30455 mm on a 28.400704 mm sensor diagonal. For the portrait TIFFs
// that is a 1861 px radius: the circle is clipped by the short image edges.
constexpr double sigmaDXCropRadiusPerLongSide = 0.4787;

struct NormalizedFeatures {
    std::vector<cv::KeyPoint> keypoints;
    cv::Mat descriptors;
};

struct MatchedPoint {
    cv::DMatch match;
    double positionError;
};

thread_local std::vector<PWControlPointPairDiagnostic> lastPairDiagnostics;

struct MatchCounts {
    int ratio = 0;
    int mutual = 0;
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
    const bool circularFisheye = horizontalFieldOfView >= 110.0;
    const double circleRadius =
        std::max(sourceSize.width, sourceSize.height)
        * sigmaDXCropRadiusPerLongSide;
    const cv::Point2d circleCenter(
        sourceSize.width / 2.0,
        sourceSize.height / 2.0
    );

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
            const bool insideFisheyeCircle =
                !circularFisheye
                || std::hypot(
                    sourceX - circleCenter.x,
                    sourceY - circleCenter.y
                ) <= circleRadius;
            maskRow[x] =
                sourceX >= 0.0
                && sourceX < sourceSize.width - 1.0
                && sourceY >= 0.0
                && sourceY < sourceSize.height - 1.0
                && angle < pi / 2.0
                && insideFisheyeCircle
                ? 255
                : 0;
        }
    }
}

NormalizedFeatures normalizedFeatures(
    const std::string &imagePath,
    double horizontalFieldOfView,
    const PWOrientation &orientation,
    const cv::Ptr<cv::SIFT> &detector
) {
    const cv::Mat sourceImage = cv::imread(imagePath, cv::IMREAD_GRAYSCALE);
    if (sourceImage.empty()) {
        throw std::runtime_error("Kunde inte läsa " + imagePath + ".");
    }
    cv::Mat mapX;
    cv::Mat mapY;
    cv::Mat validMask;
    makeSourceMap(
        sourceImage.size(),
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
    const cv::Mat &descriptorsB,
    MatchCounts *counts = nullptr,
    float ratioThreshold = 0.88f
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
            && matches[0].distance < ratioThreshold * matches[1].distance
        ) {
            acceptedForward[matches[0].queryIdx] = matches[0];
        }
    }
    for (const auto &matches : backward) {
        if (
            matches.size() == 2
            && matches[0].distance < ratioThreshold * matches[1].distance
        ) {
            acceptedBackward[matches[0].queryIdx] = matches[0];
        }
    }

    if (counts != nullptr) {
        counts->ratio = int(acceptedForward.size());
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
    if (counts != nullptr) {
        counts->mutual = int(result.size());
    }
    return result;
}

double selectedSpatialCoverage(
    const std::vector<cv::DMatch> &matches,
    const std::vector<cv::KeyPoint> &keypointsA,
    const std::vector<cv::KeyPoint> &keypointsB,
    const cv::Size &sizeA,
    const cv::Size &sizeB
) {
    if (matches.empty()) return 0.0;
    constexpr int columns = 6;
    constexpr int rows = 4;
    std::set<std::pair<int, int>> firstCells;
    std::set<std::pair<int, int>> secondCells;
    for (const cv::DMatch &match : matches) {
        const cv::Point2f a = keypointsA[match.queryIdx].pt;
        const cv::Point2f b = keypointsB[match.trainIdx].pt;
        firstCells.insert({
            std::clamp(int(a.x / std::max(1, sizeA.width) * columns), 0, columns - 1),
            std::clamp(int(a.y / std::max(1, sizeA.height) * rows), 0, rows - 1)
        });
        secondCells.insert({
            std::clamp(int(b.x / std::max(1, sizeB.width) * columns), 0, columns - 1),
            std::clamp(int(b.y / std::max(1, sizeB.height) * rows), 0, rows - 1)
        });
    }
    return std::min(firstCells.size(), secondCells.size())
        / double(columns * rows);
}

std::pair<int, int> sourceCell(const cv::Point2f &point, const cv::Size &size) {
    constexpr int columns = 6;
    constexpr int rows = 4;
    return {
        std::clamp(int(point.x / std::max(1, size.width) * columns), 0, columns - 1),
        std::clamp(int(point.y / std::max(1, size.height) * rows), 0, rows - 1)
    };
}

struct SourceBounds {
    double minimumX;
    double maximumX;
    double minimumY;
    double maximumY;
};

double percentile(std::vector<float> values, double fraction) {
    if (values.empty()) return 0.0;
    std::sort(values.begin(), values.end());
    const double position = std::clamp(fraction, 0.0, 1.0)
        * (values.size() - 1);
    const std::size_t lower = std::size_t(std::floor(position));
    const std::size_t upper = std::size_t(std::ceil(position));
    const double blend = position - lower;
    return values[lower] * (1.0 - blend) + values[upper] * blend;
}

double median(std::vector<double> values) {
    if (values.empty()) return 0.0;
    std::sort(values.begin(), values.end());
    const std::size_t middle = values.size() / 2;
    if (values.size() % 2 == 0) {
        return (values[middle - 1] + values[middle]) * 0.5;
    }
    return values[middle];
}

double percentile(std::vector<double> values, double fraction) {
    if (values.empty()) return 0.0;
    std::sort(values.begin(), values.end());
    const double position = std::clamp(fraction, 0.0, 1.0)
        * (values.size() - 1);
    const std::size_t lower = std::size_t(std::floor(position));
    const std::size_t upper = std::size_t(std::ceil(position));
    const double blend = position - lower;
    return values[lower] * (1.0 - blend) + values[upper] * blend;
}

SourceBounds robustSourceBounds(
    const std::vector<cv::DMatch> &matches,
    const std::vector<cv::KeyPoint> &keypoints,
    bool first
) {
    std::vector<float> horizontal;
    std::vector<float> vertical;
    horizontal.reserve(matches.size());
    vertical.reserve(matches.size());
    for (const cv::DMatch &match : matches) {
        const cv::Point2f point = keypoints[
            first ? match.queryIdx : match.trainIdx
        ].pt;
        horizontal.push_back(point.x);
        vertical.push_back(point.y);
    }
    return {
        percentile(horizontal, 0.05),
        percentile(horizontal, 0.95),
        percentile(vertical, 0.05),
        percentile(vertical, 0.95)
    };
}

cv::Point2d normalizedOverlapPoint(
    const cv::Point2f &point,
    const SourceBounds &bounds
) {
    const double width = std::max(1.0, bounds.maximumX - bounds.minimumX);
    const double height = std::max(1.0, bounds.maximumY - bounds.minimumY);
    return {
        (std::clamp(double(point.x), bounds.minimumX, bounds.maximumX)
            - bounds.minimumX) / width,
        (std::clamp(double(point.y), bounds.minimumY, bounds.maximumY)
            - bounds.minimumY) / height
    };
}

std::pair<int, int> overlapCell(
    const cv::Point2f &point,
    const SourceBounds &bounds
) {
    constexpr int columns = 5;
    constexpr int rows = 5;
    const cv::Point2d normalized = normalizedOverlapPoint(point, bounds);
    return {
        std::clamp(int(normalized.x * columns), 0, columns - 1),
        std::clamp(int(normalized.y * rows), 0, rows - 1)
    };
}

double normalizedSourceDistance(
    const cv::Point2f &first,
    const cv::Point2f &second,
    const SourceBounds &bounds
) {
    const cv::Point2d normalizedFirst = normalizedOverlapPoint(first, bounds);
    const cv::Point2d normalizedSecond = normalizedOverlapPoint(second, bounds);
    return cv::norm(normalizedFirst - normalizedSecond);
}

double normalizedImageDistance(
    const cv::Point2f &first,
    const cv::Point2f &second,
    const cv::Size &size
) {
    const double shortSide = std::max(1, std::min(size.width, size.height));
    return cv::norm(first - second) / shortSide;
}

bool isLowerPolarSupportMatch(
    const cv::DMatch &match,
    const std::vector<cv::KeyPoint> &keypointsA,
    const std::vector<cv::KeyPoint> &keypointsB,
    const cv::Size &sizeA,
    const cv::Size &sizeB
) {
    // Ring images are normalized to their upright EXIF orientation before
    // matching. In a horizontal portrait ring the lower part of both frames
    // therefore supplies the near-field nadir constraints. Keep the test
    // deliberately broad: the later rotation check and bundle adjustment are
    // responsible for deciding whether an individual match is geometrically
    // useful.
    constexpr double polarBandStart = 0.77;
    const cv::Point2f first = keypointsA[match.queryIdx].pt;
    const cv::Point2f second = keypointsB[match.trainIdx].pt;
    return first.y >= sizeA.height * polarBandStart
        && second.y >= sizeB.height * polarBandStart;
}

std::vector<cv::DMatch> spatiallyBalancedSelection(
    const std::vector<cv::DMatch> &inliers,
    const std::vector<cv::KeyPoint> &keypointsA,
    const std::vector<cv::KeyPoint> &keypointsB,
    const cv::Size &sizeA,
    const cv::Size &sizeB,
    bool preferLowerPolarSupport,
    int maximumLowerPolarSupport = -1,
    double minimumImageSeparation = 0.05,
    const std::map<std::pair<int, int>, double> *rotationErrors = nullptr
) {
    if (inliers.empty()) return {};
    std::vector<cv::DMatch> remaining = inliers;
    std::sort(
        remaining.begin(), remaining.end(),
        [](const cv::DMatch &a, const cv::DMatch &b) {
            return a.distance < b.distance;
        }
    );
    const int target = std::min(25, int(remaining.size()));
    // The ordinary five-percent separation is about 100 px for a 2000x3008
    // D70 frame. Require the configured separation at both endpoints: two
    // matches that collapse onto the same local detail in either image add
    // almost no new geometric information, even if their other endpoints are
    // separated. Sparse edge-closure recovery supplies a smaller value.
    const SourceBounds firstBounds = robustSourceBounds(
        inliers, keypointsA, true
    );
    const SourceBounds secondBounds = robustSourceBounds(
        inliers, keypointsB, false
    );
    std::vector<cv::DMatch> selected;
    int selectedLowerPolarCount = 0;
    std::set<std::pair<int, int>> selectedFirstCells;
    std::set<std::pair<int, int>> selectedSecondCells;
    auto appendBalanced = [&](std::vector<cv::DMatch> candidates,
                              int selectionTarget) {
        while (!candidates.empty()
               && int(selected.size()) < selectionTarget) {
            int bestIndex = -1;
            int bestNovelCells = -1;
            double bestRotationError =
                std::numeric_limits<double>::max();
            double bestSeparation = -1.0;
            float bestDescriptorDistance =
                std::numeric_limits<float>::max();
            for (int index = 0; index < int(candidates.size()); ++index) {
                const cv::DMatch &candidate = candidates[index];
                if (maximumLowerPolarSupport >= 0
                    && isLowerPolarSupportMatch(
                        candidate, keypointsA, keypointsB, sizeA, sizeB
                    )
                    && selectedLowerPolarCount
                        >= maximumLowerPolarSupport) {
                    continue;
                }
                const cv::Point2f a = keypointsA[candidate.queryIdx].pt;
                const cv::Point2f b = keypointsB[candidate.trainIdx].pt;
                const bool sufficientlySeparated = std::all_of(
                    selected.begin(),
                    selected.end(),
                    [&](const cv::DMatch &existing) {
                        return normalizedImageDistance(
                            a, keypointsA[existing.queryIdx].pt, sizeA
                        ) >= minimumImageSeparation
                            && normalizedImageDistance(
                                b, keypointsB[existing.trainIdx].pt, sizeB
                            ) >= minimumImageSeparation;
                    }
                );
                if (!sufficientlySeparated) continue;
                double separation = std::numeric_limits<double>::max();
                for (const cv::DMatch &existing : selected) {
                    separation = std::min(separation, std::min(
                        normalizedSourceDistance(
                            a, keypointsA[existing.queryIdx].pt, firstBounds
                        ),
                        normalizedSourceDistance(
                            b, keypointsB[existing.trainIdx].pt, secondBounds
                        )
                    ));
                }
                const int novelCells =
                    (selectedFirstCells.find(overlapCell(a, firstBounds))
                        == selectedFirstCells.end())
                    + (selectedSecondCells.find(overlapCell(b, secondBounds))
                        == selectedSecondCells.end());
                double rotationError = 0.0;
                if (rotationErrors != nullptr) {
                    const auto found = rotationErrors->find({
                        candidate.queryIdx, candidate.trainIdx
                    });
                    rotationError = found == rotationErrors->end()
                        ? std::numeric_limits<double>::max()
                        : found->second;
                }
                if (
                    novelCells > bestNovelCells
                    || (novelCells == bestNovelCells
                        && rotationError < bestRotationError)
                    || (
                        novelCells == bestNovelCells
                        && rotationError == bestRotationError
                        && separation > bestSeparation
                    )
                    || (
                        novelCells == bestNovelCells
                        && rotationError == bestRotationError
                        && separation == bestSeparation
                        && candidate.distance < bestDescriptorDistance
                    )
                ) {
                    bestIndex = index;
                    bestNovelCells = novelCells;
                    bestRotationError = rotationError;
                    bestSeparation = separation;
                    bestDescriptorDistance = candidate.distance;
                }
            }
            if (bestIndex < 0) break;
            const cv::DMatch chosen = candidates[bestIndex];
            selected.push_back(chosen);
            if (isLowerPolarSupportMatch(
                chosen, keypointsA, keypointsB, sizeA, sizeB
            )) {
                ++selectedLowerPolarCount;
            }
            selectedFirstCells.insert(overlapCell(
                keypointsA[chosen.queryIdx].pt, firstBounds
            ));
            selectedSecondCells.insert(overlapCell(
                keypointsB[chosen.trainIdx].pt, secondBounds
            ));
            candidates.erase(candidates.begin() + bestIndex);
        }
    };
    if (preferLowerPolarSupport) {
        std::vector<cv::DMatch> polarCandidates;
        std::copy_if(
            remaining.begin(), remaining.end(),
            std::back_inserter(polarCandidates),
            [&](const cv::DMatch &match) {
                return isLowerPolarSupportMatch(
                    match, keypointsA, keypointsB, sizeA, sizeB
                );
            }
        );
        constexpr int polarTarget = 10;
        appendBalanced(
            std::move(polarCandidates),
            std::min(target, polarTarget)
        );
    }
    appendBalanced(std::move(remaining), target);
    return selected;
}

cv::Vec3d calibratedFisheyeRay(
    const cv::Point2f &point,
    const cv::Size &size,
    double horizontalFieldOfView,
    int lensModel
) {
    // The ring matcher receives the already converted equisolid geometry
    // sources. Undo the shared Hugin radial model approximately so matches
    // from the complete fisheye overlap can be checked by one 3D rotation.
    // A planar homography only describes a small local patch of two views
    // separated by roughly 90 degrees and systematically rejects the useful
    // zenith/nadir constraints.
    const bool isNikon105 = lensModel == PWLensModelNikon105DX;
    const double calibratedFieldOfView = isNikon105
        ? horizontalFieldOfView : 113.4;
    const double distortionA = isNikon105
        ? -0.0252155339841942 : -0.06164565246503961;
    const double distortionB = isNikon105
        ? 0.0605540979849503 : 0.16155732903077044;
    const double distortionC = isNikon105
        ? -0.055438892095899 : -0.12544199818788626;
    const double referenceWidth = isNikon105 ? 2000.0 : 2600.0;
    const double referenceHeight = isNikon105 ? 3008.0 : 3888.0;
    const double scaleX = size.width / referenceWidth;
    const double scaleY = size.height / referenceHeight;
    const double centerShiftX = isNikon105 ? 4.19324585683399 : -26.093;
    const double centerShiftY = isNikon105 ? -1.00751194420142 : -46.95;
    const double centerX = (size.width - 1) * 0.5 + centerShiftX * scaleX;
    const double centerY = (size.height - 1) * 0.5 + centerShiftY * scaleY;
    const double dx = point.x - centerX;
    const double dy = point.y - centerY;
    const double observedRadius = std::hypot(dx, dy);
    if (observedRadius < 1e-9) {
        return cv::Vec3d(0.0, 0.0, 1.0);
    }

    const double normalizationRadius = std::min(size.width, size.height) * 0.5;
    const double distortionConstant =
        1.0 - distortionA - distortionB - distortionC;
    double idealRadius = observedRadius;
    for (int iteration = 0; iteration < 10; ++iteration) {
        const double normalized = idealRadius / normalizationRadius;
        const double polynomial =
            distortionA * std::pow(normalized, 3.0)
            + distortionB * std::pow(normalized, 2.0)
            + distortionC * normalized
            + distortionConstant;
        const double derivative = polynomial + idealRadius / normalizationRadius * (
            3.0 * distortionA * std::pow(normalized, 2.0)
            + 2.0 * distortionB * normalized
            + distortionC
        );
        if (std::abs(derivative) < 1e-9) break;
        idealRadius -= (idealRadius * polynomial - observedRadius) / derivative;
        idealRadius = std::max(0.0, idealRadius);
    }

    const double focalLength = normalizationRadius / (
        2.0 * std::sin(radians(calibratedFieldOfView / 4.0))
    );
    const double angle = 2.0 * std::asin(std::clamp(
        idealRadius / (2.0 * focalLength), 0.0, 1.0
    ));
    const double radialScale = std::sin(angle) / observedRadius;
    return cv::Vec3d(
        dx * radialScale,
        dy * radialScale,
        std::cos(angle)
    );
}

using RayPair = std::pair<cv::Vec3d, cv::Vec3d>;

template<typename RayAt>
cv::Matx33d fittedRayRotation(int rayCount, RayAt rayAt) {
    cv::Matx33d covariance = cv::Matx33d::zeros();
    for (int index = 0; index < rayCount; ++index) {
        const RayPair rays = rayAt(index);
        const cv::Vec3d &first = rays.first;
        const cv::Vec3d &second = rays.second;
        covariance += cv::Matx33d(
            second[0] * first[0], second[0] * first[1], second[0] * first[2],
            second[1] * first[0], second[1] * first[1], second[1] * first[2],
            second[2] * first[0], second[2] * first[1], second[2] * first[2]
        );
    }
    cv::Mat singularValues;
    cv::Mat left;
    cv::Mat rightTranspose;
    cv::SVD::compute(
        cv::Mat(covariance), singularValues, left, rightTranspose,
        cv::SVD::FULL_UV
    );
    cv::Mat rotation = rightTranspose.t() * left.t();
    if (cv::determinant(rotation) < 0.0) {
        cv::Mat correctedRight = rightTranspose.t();
        correctedRight.col(2) *= -1.0;
        rotation = correctedRight * left.t();
    }
    cv::Matx33d result;
    for (int row = 0; row < 3; ++row) {
        for (int column = 0; column < 3; ++column) {
            result(row, column) = rotation.at<double>(row, column);
        }
    }
    return result;
}

double rayRotationError(const RayPair &rays, const cv::Matx33d &rotation) {
    return std::acos(std::clamp(
        rays.first.dot(rotation * rays.second), -1.0, 1.0
    ));
}

struct RotationEdge {
    int first;
    int second;
    cv::Matx33d rotation;
    int inlierCount;
    double medianError;
};

std::vector<cv::Matx33d> worldRotationsFromStrongestEdges(
    const std::vector<RotationEdge> &edges,
    int imageCount,
    int ignoredImage = -1
) {
    std::vector<int> parent(imageCount);
    for (int index = 0; index < imageCount; ++index) parent[index] = index;
    auto root = [&](int image) {
        while (parent[image] != image) {
            parent[image] = parent[parent[image]];
            image = parent[image];
        }
        return image;
    };
    struct Connection { int neighbor; cv::Matx33d rotation; };
    std::vector<std::vector<Connection>> tree(imageCount);
    for (const RotationEdge &edge : edges) {
        const int firstRoot = root(edge.first);
        const int secondRoot = root(edge.second);
        if (firstRoot == secondRoot) continue;
        parent[secondRoot] = firstRoot;
        tree[edge.first].push_back({edge.second, edge.rotation});
        tree[edge.second].push_back({edge.first, edge.rotation.t()});
    }

    std::vector<cv::Matx33d> worldRotations(
        imageCount, cv::Matx33d::eye()
    );
    std::vector<bool> visited(imageCount, false);
    if (ignoredImage >= 0 && ignoredImage < imageCount) {
        visited[ignoredImage] = true;
    }
    int seed = 0;
    while (seed < imageCount && seed == ignoredImage) ++seed;
    if (seed >= imageCount) {
        throw std::runtime_error(
            "Kontrollpunkterna gav ingen kvarvarande 3D-startpose."
        );
    }
    std::vector<int> pending = {seed};
    visited[seed] = true;
    while (!pending.empty()) {
        const int current = pending.back();
        pending.pop_back();
        for (const Connection &connection : tree[current]) {
            if (visited[connection.neighbor]) continue;
            worldRotations[connection.neighbor] =
                worldRotations[current] * connection.rotation;
            visited[connection.neighbor] = true;
            pending.push_back(connection.neighbor);
        }
    }
    if (std::find(visited.begin(), visited.end(), false) != visited.end()) {
        throw std::runtime_error(
            "Kontrollpunkterna gav ingen sammanhangande 3D-startpose."
        );
    }
    return worldRotations;
}

PWOrientation panoramaOrientation(const cv::Matx33d &rotation) {
    // This Y-X-Z extraction produces the same yaw, pitch and roll convention
    // used by PTGui and Hugin for source-image poses.
    const double pitch = std::asin(std::clamp(
        -rotation(1, 2), -1.0, 1.0
    ));
    const double cosinePitch = std::cos(pitch);
    double yaw;
    double roll;
    if (std::abs(cosinePitch) > 1e-7) {
        yaw = std::atan2(rotation(0, 2), rotation(2, 2));
        roll = std::atan2(rotation(1, 0), rotation(1, 1));
    } else {
        yaw = std::atan2(-rotation(2, 0), rotation(0, 0));
        roll = 0.0;
    }
    return {
        yaw * 180.0 / pi,
        pitch * 180.0 / pi,
        roll * 180.0 / pi
    };
}

using RaysByImagePair = std::map<std::pair<int, int>, std::vector<RayPair>>;

RaysByImagePair controlPointRays(
    const PWControlPoint *controlPoints,
    int controlPointCount,
    const int *imageWidths,
    const int *imageHeights,
    int imageCount,
    double horizontalFieldOfView,
    int lensModel
) {
    RaysByImagePair rays;
    for (int index = 0; index < controlPointCount; ++index) {
        const PWControlPoint &point = controlPoints[index];
        if (point.firstImage < 0 || point.secondImage < 0
            || point.firstImage >= imageCount
            || point.secondImage >= imageCount
            || point.firstImage == point.secondImage) {
            continue;
        }
        const int first = std::min(point.firstImage, point.secondImage);
        const int second = std::max(point.firstImage, point.secondImage);
        const bool isForward = point.firstImage == first;
        const cv::Point2f firstPoint(
            float(isForward ? point.firstX : point.secondX),
            float(isForward ? point.firstY : point.secondY)
        );
        const cv::Point2f secondPoint(
            float(isForward ? point.secondX : point.firstX),
            float(isForward ? point.secondY : point.firstY)
        );
        rays[{first, second}].push_back({
            calibratedFisheyeRay(
                firstPoint,
                cv::Size(imageWidths[first], imageHeights[first]),
                horizontalFieldOfView,
                lensModel
            ),
            calibratedFisheyeRay(
                secondPoint,
                cv::Size(imageWidths[second], imageHeights[second]),
                horizontalFieldOfView,
                lensModel
            )
        });
    }
    return rays;
}

std::vector<RotationEdge> strongestRotationEdges(
    const RaysByImagePair &rays,
    int minimumInlierCount = 6
) {
    std::vector<RotationEdge> edges;
    constexpr double inlierThreshold = 1.5 * pi / 180.0;
    for (const auto &entry : rays) {
        const auto &pair = entry.first;
        const auto &pairRays = entry.second;
        if (pairRays.size() < std::size_t(minimumInlierCount)) continue;
        cv::RNG random(pair.first * 1009 + pair.second * 9176);
        std::vector<int> bestIndices;
        const int iterations = std::min(2000, int(pairRays.size() * 30));
        for (int iteration = 0; iteration < iterations; ++iteration) {
            std::set<int> sampleSet;
            while (sampleSet.size() < 3) {
                sampleSet.insert(random.uniform(0, int(pairRays.size())));
            }
            const std::vector<int> sample(sampleSet.begin(), sampleSet.end());
            const cv::Matx33d candidate = fittedRayRotation(
                int(sample.size()),
                [&](int position) { return pairRays[sample[position]]; }
            );
            std::vector<int> inliers;
            for (int index = 0; index < int(pairRays.size()); ++index) {
                if (rayRotationError(pairRays[index], candidate)
                        <= inlierThreshold) {
                    inliers.push_back(index);
                }
            }
            if (inliers.size() > bestIndices.size()) {
                bestIndices = std::move(inliers);
            }
        }
        if (bestIndices.size() < std::size_t(minimumInlierCount)) continue;
        const cv::Matx33d rotation = fittedRayRotation(
            int(bestIndices.size()),
            [&](int position) { return pairRays[bestIndices[position]]; }
        );
        std::vector<double> errors;
        for (const int index : bestIndices) {
            errors.push_back(rayRotationError(pairRays[index], rotation));
        }
        std::sort(errors.begin(), errors.end());
        edges.push_back({
            pair.first, pair.second, rotation, int(bestIndices.size()),
            errors[errors.size() / 2]
        });
    }
    std::sort(
        edges.begin(), edges.end(),
        [](const RotationEdge &a, const RotationEdge &b) {
            if (a.inlierCount != b.inlierCount) {
                return a.inlierCount > b.inlierCount;
            }
            return a.medianError < b.medianError;
        }
    );
    return edges;
}

cv::Matx33d fittedSourceRotation(
    const std::vector<cv::DMatch> &matches,
    const std::vector<cv::KeyPoint> &keypointsA,
    const std::vector<cv::KeyPoint> &keypointsB,
    const cv::Size &sizeA,
    const cv::Size &sizeB,
    const std::vector<int> &indices,
    double horizontalFieldOfView,
    int lensModel
) {
    return fittedRayRotation(int(indices.size()), [&](int position) {
        const cv::DMatch &match = matches[indices[position]];
        return RayPair{
            calibratedFisheyeRay(
                keypointsA[match.queryIdx].pt, sizeA,
                horizontalFieldOfView, lensModel
            ),
            calibratedFisheyeRay(
                keypointsB[match.trainIdx].pt, sizeB,
                horizontalFieldOfView, lensModel
            )
        };
    });
}

double sourceRotationError(
    const cv::DMatch &match,
    const std::vector<cv::KeyPoint> &keypointsA,
    const std::vector<cv::KeyPoint> &keypointsB,
    const cv::Size &sizeA,
    const cv::Size &sizeB,
    const cv::Matx33d &rotation,
    double horizontalFieldOfView,
    int lensModel
) {
    const cv::Vec3d first = calibratedFisheyeRay(
        keypointsA[match.queryIdx].pt, sizeA,
        horizontalFieldOfView, lensModel
    );
    const cv::Vec3d second = calibratedFisheyeRay(
        keypointsB[match.trainIdx].pt, sizeB,
        horizontalFieldOfView, lensModel
    );
    return std::acos(std::clamp(first.dot(rotation * second), -1.0, 1.0));
}

int occupiedSourceCells(
    const std::vector<cv::DMatch> &matches,
    const std::vector<cv::KeyPoint> &keypoints,
    const cv::Size &size,
    const std::vector<int> &indices,
    bool first
) {
    std::set<std::pair<int, int>> cells;
    for (const int index : indices) {
        const cv::DMatch &match = matches[index];
        cells.insert(sourceCell(
            keypoints[first ? match.queryIdx : match.trainIdx].pt,
            size
        ));
    }
    return int(cells.size());
}

std::vector<cv::DMatch> fisheyeRotationConsistentMatches(
    const std::vector<cv::DMatch> &matches,
    const std::vector<cv::DMatch> &polarCandidates,
    const std::vector<cv::KeyPoint> &keypointsA,
    const std::vector<cv::KeyPoint> &keypointsB,
    const cv::Size &sizeA,
    const cv::Size &sizeB,
    double horizontalFieldOfView,
    int lensModel,
    int minimumInlierCount,
    int minimumCellScore,
    bool prioritizesInlierCount,
    std::map<std::pair<int, int>, double> *rotationErrors
) {
    if (rotationErrors != nullptr) rotationErrors->clear();
    if (matches.size() < minimumInlierCount) return {};
    // The loose threshold is only for finding the dominant camera rotation.
    // A second, data-driven threshold below decides which matches actually
    // become candidates. This keeps wind and parallax from becoming a fixed
    // special case in the matcher.
    constexpr double discoveryThreshold = 1.5 * pi / 180.0;
    cv::RNG random(0);
    std::vector<int> bestIndices;
    int bestCellScore = 0;
    const int iterations = std::min(4000, int(matches.size() * 20));
    for (int iteration = 0; iteration < iterations; ++iteration) {
        std::set<int> sampleSet;
        while (sampleSet.size() < 3) {
            sampleSet.insert(random.uniform(0, int(matches.size())));
        }
        const std::vector<int> sample(sampleSet.begin(), sampleSet.end());
        const cv::Matx33d rotation = fittedSourceRotation(
            matches, keypointsA, keypointsB, sizeA, sizeB, sample,
            horizontalFieldOfView, lensModel
        );
        std::vector<int> inliers;
        for (int index = 0; index < int(matches.size()); ++index) {
            if (sourceRotationError(
                    matches[index], keypointsA, keypointsB, sizeA, sizeB,
                    rotation, horizontalFieldOfView, lensModel
                ) < discoveryThreshold) {
                inliers.push_back(index);
            }
        }
        const int cellScore = std::min(
            occupiedSourceCells(matches, keypointsA, sizeA, inliers, true),
            occupiedSourceCells(matches, keypointsB, sizeB, inliers, false)
        );
        const bool improvesConsensus = prioritizesInlierCount
            ? inliers.size() > bestIndices.size()
                || (inliers.size() == bestIndices.size()
                    && cellScore > bestCellScore)
            : cellScore > bestCellScore
                || (cellScore == bestCellScore
                    && inliers.size() > bestIndices.size());
        if (improvesConsensus) {
            bestCellScore = cellScore;
            bestIndices = std::move(inliers);
        }
    }
    if (bestIndices.size() < minimumInlierCount
        || bestCellScore < minimumCellScore) return {};
    const cv::Matx33d discoveryRotation = fittedSourceRotation(
        matches, keypointsA, keypointsB, sizeA, sizeB, bestIndices,
        horizontalFieldOfView, lensModel
    );
    std::vector<double> discoveryErrors;
    discoveryErrors.reserve(matches.size());
    for (const cv::DMatch &match : matches) {
        const double error = sourceRotationError(
            match, keypointsA, keypointsB, sizeA, sizeB,
            discoveryRotation, horizontalFieldOfView, lensModel
        );
        if (error < discoveryThreshold) discoveryErrors.push_back(error);
    }
    if (discoveryErrors.size() < minimumInlierCount) return {};

    const double medianError = median(discoveryErrors);
    std::vector<double> deviations;
    deviations.reserve(discoveryErrors.size());
    for (const double error : discoveryErrors) {
        deviations.push_back(std::abs(error - medianError));
    }
    const double robustSigma = 1.4826 * median(deviations);
    const double adaptiveConsistencyThreshold = std::clamp(
        medianError + 3.0 * robustSigma,
        0.25 * pi / 180.0,
        0.75 * pi / 180.0
    );
    // The sparse closure fallback needs the complete RANSAC consensus. A
    // rotation fitted mostly from one thin edge patch is weakly constrained;
    // applying the ordinary sub-degree refinement can discard the few points
    // from the second edge cell that resolve that ambiguity. Bundle adjustment
    // and control-point cleaning provide the precise final rejection.
    const double consistencyThreshold = prioritizesInlierCount
        ? discoveryThreshold
        : adaptiveConsistencyThreshold;

    std::vector<int> consistentIndices;
    for (int index = 0; index < int(matches.size()); ++index) {
        if (sourceRotationError(
            matches[index], keypointsA, keypointsB, sizeA, sizeB,
            discoveryRotation, horizontalFieldOfView, lensModel
            ) <= consistencyThreshold) {
            consistentIndices.push_back(index);
        }
    }
    const int consistentCellScore = std::min(
        occupiedSourceCells(
            matches, keypointsA, sizeA, consistentIndices, true
        ),
        occupiedSourceCells(
            matches, keypointsB, sizeB, consistentIndices, false
        )
    );
    if (consistentIndices.size() < minimumInlierCount
        || consistentCellScore < minimumCellScore) {
        return {};
    }

    const cv::Matx33d refinedRotation = fittedSourceRotation(
        matches, keypointsA, keypointsB, sizeA, sizeB, consistentIndices,
        horizontalFieldOfView, lensModel
    );
    std::vector<cv::DMatch> result;
    std::set<std::pair<int, int>> resultIndices;
    for (const cv::DMatch &match : matches) {
        const double error = sourceRotationError(
            match, keypointsA, keypointsB, sizeA, sizeB,
            refinedRotation, horizontalFieldOfView, lensModel
        );
        if (error <= consistencyThreshold) {
            result.push_back(match);
            resultIndices.insert({match.queryIdx, match.trainIdx});
            if (rotationErrors != nullptr) {
                (*rotationErrors)[{match.queryIdx, match.trainIdx}] = error;
            }
        }
    }
    // Repetitive paving is often rejected by the ordinary descriptor-ratio
    // test even when the reciprocal match is useful. Revisit only the lower
    // polar band with a looser descriptor pool and the already established
    // camera rotation. This cannot create a new pair by itself: the strict
    // global solve above must have succeeded first.
    constexpr double polarSupportThreshold = 10.0 * pi / 180.0;
    for (const cv::DMatch &match : polarCandidates) {
        if (resultIndices.find({match.queryIdx, match.trainIdx})
                != resultIndices.end()
            || !isLowerPolarSupportMatch(
                match, keypointsA, keypointsB, sizeA, sizeB
            )
            || sourceRotationError(
                match, keypointsA, keypointsB, sizeA, sizeB,
                refinedRotation, horizontalFieldOfView, lensModel
            ) > polarSupportThreshold) {
            continue;
        }
        const double error = sourceRotationError(
            match, keypointsA, keypointsB, sizeA, sizeB,
            refinedRotation, horizontalFieldOfView, lensModel
        );
        result.push_back(match);
        resultIndices.insert({match.queryIdx, match.trainIdx});
        if (rotationErrors != nullptr) {
            (*rotationErrors)[{match.queryIdx, match.trainIdx}] = error;
        }
    }
    return result;
}

double wrappedDistance(const cv::Point2f &first, const cv::Point2f &second) {
    double horizontal = std::abs(first.x - second.x);
    horizontal = std::min(horizontal, panoramaWidth - horizontal);
    return std::hypot(horizontal, first.y - second.y);
}

cv::Vec3d panoramaRay(const cv::Point2f &point) {
    const double longitude =
        point.x / panoramaWidth * (2.0 * pi) - pi;
    const double latitude =
        pi / 2.0 - point.y / panoramaHeight * pi;
    return cv::Vec3d(
        std::sin(longitude) * std::cos(latitude),
        -std::sin(latitude),
        std::cos(longitude) * std::cos(latitude)
    );
}

cv::Matx33d fittedRotation(
    const NormalizedFeatures &featuresA,
    const NormalizedFeatures &featuresB,
    const std::vector<cv::DMatch> &matches,
    const std::vector<int> &indices
) {
    cv::Matx33d covariance = cv::Matx33d::zeros();
    for (const int index : indices) {
        const cv::DMatch &match = matches[index];
        const cv::Vec3d first = panoramaRay(
            featuresA.keypoints[match.queryIdx].pt
        );
        const cv::Vec3d second = panoramaRay(
            featuresB.keypoints[match.trainIdx].pt
        );
        covariance += cv::Matx33d(
            second[0] * first[0], second[0] * first[1], second[0] * first[2],
            second[1] * first[0], second[1] * first[1], second[1] * first[2],
            second[2] * first[0], second[2] * first[1], second[2] * first[2]
        );
    }

    cv::Mat singularValues;
    cv::Mat left;
    cv::Mat rightTranspose;
    cv::SVD::compute(
        cv::Mat(covariance),
        singularValues,
        left,
        rightTranspose,
        cv::SVD::FULL_UV
    );
    cv::Mat rotation = rightTranspose.t() * left.t();
    if (cv::determinant(rotation) < 0.0) {
        cv::Mat correctedRight = rightTranspose.t();
        correctedRight.col(2) *= -1.0;
        rotation = correctedRight * left.t();
    }
    cv::Matx33d result;
    for (int row = 0; row < 3; ++row) {
        for (int column = 0; column < 3; ++column) {
            result(row, column) = rotation.at<double>(row, column);
        }
    }
    return result;
}

double rotationError(
    const NormalizedFeatures &featuresA,
    const NormalizedFeatures &featuresB,
    const cv::DMatch &match,
    const cv::Matx33d &rotation
) {
    const cv::Vec3d first = panoramaRay(
        featuresA.keypoints[match.queryIdx].pt
    );
    const cv::Vec3d second = panoramaRay(
        featuresB.keypoints[match.trainIdx].pt
    );
    return std::acos(std::clamp(first.dot(rotation * second), -1.0, 1.0));
}

int occupiedFeatureCells(
    const NormalizedFeatures &features,
    const std::vector<cv::DMatch> &matches,
    const std::vector<int> &indices,
    bool first
) {
    std::set<std::pair<int, int>> cells;
    for (const int index : indices) {
        const cv::DMatch &match = matches[index];
        const cv::Point2f point = features.keypoints[
            first ? match.queryIdx : match.trainIdx
        ].pt;
        cells.insert({
            std::clamp(int(point.x / panoramaWidth * 16), 0, 15),
            std::clamp(int(point.y / panoramaHeight * 8), 0, 7)
        });
    }
    return int(cells.size());
}

std::vector<cv::DMatch> rotationConsistentMatches(
    const NormalizedFeatures &featuresA,
    const NormalizedFeatures &featuresB,
    const std::vector<cv::DMatch> &matches
) {
    if (matches.size() < 5) {
        return {};
    }

    constexpr double inlierThreshold = 4.0 * pi / 180.0;
    cv::RNG random(0);
    std::vector<int> bestIndices;
    int bestCellScore = 0;
    const int iterations = std::min(2000, int(matches.size() * 30));
    for (int iteration = 0; iteration < iterations; ++iteration) {
        std::set<int> sampleSet;
        while (sampleSet.size() < 3) {
            sampleSet.insert(random.uniform(0, int(matches.size())));
        }
        const std::vector<int> sample(sampleSet.begin(), sampleSet.end());
        const cv::Matx33d rotation = fittedRotation(
            featuresA,
            featuresB,
            matches,
            sample
        );
        std::vector<int> inliers;
        for (int index = 0; index < int(matches.size()); ++index) {
            if (
                rotationError(
                    featuresA,
                    featuresB,
                    matches[index],
                    rotation
                ) < inlierThreshold
            ) {
                inliers.push_back(index);
            }
        }
        const int cellScore = std::min(
            occupiedFeatureCells(featuresA, matches, inliers, true),
            occupiedFeatureCells(featuresB, matches, inliers, false)
        );
        if (
            cellScore > bestCellScore
            || (
                cellScore == bestCellScore
                && inliers.size() > bestIndices.size()
            )
        ) {
            bestCellScore = cellScore;
            bestIndices = std::move(inliers);
        }
    }
    if (bestIndices.size() < 5) {
        return {};
    }
    if (bestCellScore < 2) {
        return {};
    }

    const cv::Matx33d refinedRotation = fittedRotation(
        featuresA,
        featuresB,
        matches,
        bestIndices
    );
    std::vector<cv::DMatch> result;
    for (const cv::DMatch &match : matches) {
        if (
            rotationError(
                featuresA,
                featuresB,
                match,
                refinedRotation
            ) < inlierThreshold
        ) {
            result.push_back(match);
        }
    }
    return result;
}

std::vector<cv::DMatch> geometricMatches(
    const NormalizedFeatures &featuresA,
    const NormalizedFeatures &featuresB,
    bool requireRotationConsistency = true
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
        candidates.push_back({match, error});
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
    if (requireRotationConsistency) {
        std::vector<cv::DMatch> candidateMatches;
        candidateMatches.reserve(candidates.size());
        for (const MatchedPoint &candidate : candidates) {
            candidateMatches.push_back(candidate.match);
        }
        const std::vector<cv::DMatch> consistentMatches =
            rotationConsistentMatches(featuresA, featuresB, candidateMatches);
        std::set<std::pair<int, int>> consistentIndices;
        for (const cv::DMatch &match : consistentMatches) {
            consistentIndices.insert({match.queryIdx, match.trainIdx});
        }
        candidates.erase(
            std::remove_if(
                candidates.begin(),
                candidates.end(),
                [&](const MatchedPoint &candidate) {
                    return consistentIndices.find({
                        candidate.match.queryIdx,
                        candidate.match.trainIdx
                    }) == consistentIndices.end();
                }
            ),
            candidates.end()
        );
    }

    constexpr double minimumSeparation = 20.0;
    constexpr std::size_t maximumSelectedMatches = 20;
    std::vector<cv::DMatch> selected;
    for (const MatchedPoint &candidate : candidates) {
        const cv::Point2f pointA =
            featuresA.keypoints[candidate.match.queryIdx].pt;
        const cv::Point2f pointB =
            featuresB.keypoints[candidate.match.trainIdx].pt;
        const bool tooClose = std::any_of(
            selected.begin(),
            selected.end(),
            [&](const cv::DMatch &existing) {
                const cv::Point2f existingA =
                    featuresA.keypoints[existing.queryIdx].pt;
                const cv::Point2f existingB =
                    featuresB.keypoints[existing.trainIdx].pt;
                return wrappedDistance(pointA, existingA) < minimumSeparation
                    || wrappedDistance(pointB, existingB) < minimumSeparation;
            }
        );
        if (!tooClose) {
            selected.push_back(candidate.match);
            if (selected.size() == maximumSelectedMatches) {
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
    const cv::Size &firstSourceSize,
    const cv::Size &secondSourceSize,
    double horizontalFieldOfView,
    const PWOrientation &firstOrientation,
    const PWOrientation &secondOrientation,
    std::vector<PWControlPoint> &destination
) {
    for (const cv::DMatch &match : matches) {
        const cv::Point2d firstPoint = sourcePoint(
            firstFeatures.keypoints[match.queryIdx].pt,
            firstSourceSize,
            horizontalFieldOfView,
            firstOrientation
        );
        const cv::Point2d secondPoint = sourcePoint(
            secondFeatures.keypoints[match.trainIdx].pt,
            secondSourceSize,
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

void makeNadirLocalPanoramaMap(
    const cv::Size &panoramaSize,
    double polePitchDegrees,
    cv::Mat &mapX,
    cv::Mat &mapY
) {
    mapX.create(repairLocalViewSize, repairLocalViewSize, CV_32F);
    mapY.create(repairLocalViewSize, repairLocalViewSize, CV_32F);

    const PWOrientation orientation = {0.0, polePitchDegrees, 0.0};
    const cv::Matx33d rotation = rotationMatrix(orientation);
    const double center = repairLocalViewSize / 2.0;
    const double focalLength =
        center / std::tan(radians(repairLocalViewFieldOfView / 2.0));

    for (int y = 0; y < repairLocalViewSize; ++y) {
        float *mapXRow = mapX.ptr<float>(y);
        float *mapYRow = mapY.ptr<float>(y);
        for (int x = 0; x < repairLocalViewSize; ++x) {
            const cv::Vec3d cameraRay = cv::normalize(cv::Vec3d(
                (x - center) / focalLength,
                (y - center) / focalLength,
                1.0
            ));
            const cv::Vec3d worldRay = rotation * cameraRay;
            const double longitude = std::atan2(worldRay[0], worldRay[2]);
            const double latitude = std::asin(
                std::clamp(-worldRay[1], -1.0, 1.0)
            );
            double panoramaX =
                (longitude + pi) / (2.0 * pi) * panoramaSize.width;
            if (panoramaX < 0.0) {
                panoramaX += panoramaSize.width;
            } else if (panoramaX >= panoramaSize.width) {
                panoramaX -= panoramaSize.width;
            }
            const double panoramaY = std::clamp(
                (pi / 2.0 - latitude) / pi * panoramaSize.height,
                0.0,
                panoramaSize.height - 1.0
            );
            mapXRow[x] = float(panoramaX);
            mapYRow[x] = float(panoramaY);
        }
    }
}

void makeRepairLocalMap(
    const cv::Size &sourceSize,
    double horizontalFieldOfView,
    cv::Mat &mapX,
    cv::Mat &mapY,
    cv::Mat &validMask
) {
    mapX.create(repairLocalViewSize, repairLocalViewSize, CV_32F);
    mapY.create(repairLocalViewSize, repairLocalViewSize, CV_32F);
    validMask.create(
        repairLocalViewSize,
        repairLocalViewSize,
        CV_8U
    );

    const double center = repairLocalViewSize / 2.0;
    const double rectilinearFocalLength =
        center / std::tan(radians(repairLocalViewFieldOfView / 2.0));
    const bool nikkor105Projection = horizontalFieldOfView < 110.0;
    // The calibrated 87.44° Nikkor HFOV belongs to the portrait ring's
    // 4000 px sensor axis. A landscape pole image is 6000 px wide but has the
    // same focal length in pixels; derive it from the shared short sensor axis
    // so EXIF orientation cannot change the lens calibration.
    const double calibratedAxis = std::min(
        sourceSize.width,
        sourceSize.height
    );
    const double distortionA = nikkor105Projection
        ? -0.0252155339841942
        : -0.06164565246503961;
    const double distortionB = nikkor105Projection
        ? 0.0605540979849503
        : 0.16155732903077044;
    const double distortionC = nikkor105Projection
        ? -0.055438892095899
        : -0.12544199818788626;
    const double distortionConstant =
        1.0 - distortionA - distortionB - distortionC;
    const double centerShiftX = nikkor105Projection
        ? 4.19324585683399
        : -26.093;
    const double centerShiftY = nikkor105Projection
        ? -1.00751194420142
        : -46.95;
    // Both supported fisheyes use Hugin's equisolid base projection. Sigma
    // used to fall through to an equidistant approximation here, even though
    // the ring optimizer used the calibrated equisolid Sigma model.
    const double fisheyeFocalLength =
        (calibratedAxis / 2.0)
        / (2.0 * std::sin(radians(horizontalFieldOfView / 4.0)));

    for (int y = 0; y < repairLocalViewSize; ++y) {
        float *mapXRow = mapX.ptr<float>(y);
        float *mapYRow = mapY.ptr<float>(y);
        unsigned char *maskRow = validMask.ptr<unsigned char>(y);
        for (int x = 0; x < repairLocalViewSize; ++x) {
            const cv::Vec3d cameraRay = cv::normalize(cv::Vec3d(
                (x - center) / rectilinearFocalLength,
                (y - center) / rectilinearFocalLength,
                1.0
            ));
            const double angle = std::acos(
                std::clamp(cameraRay[2], -1.0, 1.0)
            );
            const double sine = std::sin(angle);
            double sourceX = sourceSize.width / 2.0;
            double sourceY = sourceSize.height / 2.0;
            if (std::abs(sine) >= 1e-7) {
                const double idealRadialDistance =
                    2.0 * fisheyeFocalLength * std::sin(angle / 2.0);
                const double normalizedRadius =
                    idealRadialDistance / (calibratedAxis / 2.0);
                const double radialDistance = idealRadialDistance * (
                    distortionA * std::pow(normalizedRadius, 3.0)
                    + distortionB * std::pow(normalizedRadius, 2.0)
                    + distortionC * normalizedRadius
                    + distortionConstant
                );
                const double scale = radialDistance / sine;
                sourceX += centerShiftX + cameraRay[0] * scale;
                sourceY += centerShiftY + cameraRay[1] * scale;
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

cv::Mat grayscaleWithVisibleMask(
    const cv::Mat &image,
    const cv::Mat &projectionMask,
    cv::Mat &featureMask
) {
    cv::Mat grayscale;
    cv::cvtColor(image, grayscale, cv::COLOR_BGR2GRAY);
    cv::Mat visible;
    cv::compare(grayscale, 5, visible, cv::CMP_GT);
    cv::bitwise_and(projectionMask, visible, featureMask);
    return grayscale;
}

cv::Mat registerRepairHomography(
    const cv::Mat &baseLocal,
    const cv::Mat &baseMask,
    const cv::Mat &repairLocal,
    const cv::Mat &repairMask,
    int &inlierCount,
    std::vector<PWControlPoint> *outputPoints = nullptr
) {
    cv::Mat baseFeatureMask;
    cv::Mat repairFeatureMask;
    const cv::Mat baseGray = grayscaleWithVisibleMask(
        baseLocal,
        baseMask,
        baseFeatureMask
    );
    const cv::Mat repairGray = grayscaleWithVisibleMask(
        repairLocal,
        repairMask,
        repairFeatureMask
    );

    const cv::Ptr<cv::SIFT> detector = cv::SIFT::create(
        18000,
        3,
        0.010,
        12
    );
    std::vector<cv::KeyPoint> baseKeypoints;
    std::vector<cv::KeyPoint> repairKeypoints;
    cv::Mat baseDescriptors;
    cv::Mat repairDescriptors;
    detector->detectAndCompute(
        baseGray,
        baseFeatureMask,
        baseKeypoints,
        baseDescriptors
    );
    detector->detectAndCompute(
        repairGray,
        repairFeatureMask,
        repairKeypoints,
        repairDescriptors
    );
    if (baseDescriptors.empty() || repairDescriptors.empty()) {
        throw std::runtime_error(
            "För få bilddetaljer hittades runt nadir."
        );
    }

    const std::vector<cv::DMatch> matches = mutualRatioMatches(
        repairDescriptors,
        baseDescriptors
    );
    if (matches.size() < 12) {
        throw std::runtime_error(
            "Polbilden gav för få säkra lokala träffar."
        );
    }

    std::vector<cv::Point2f> repairPoints;
    std::vector<cv::Point2f> basePoints;
    repairPoints.reserve(matches.size());
    basePoints.reserve(matches.size());
    for (const cv::DMatch &match : matches) {
        repairPoints.push_back(repairKeypoints[match.queryIdx].pt);
        basePoints.push_back(baseKeypoints[match.trainIdx].pt);
    }

    cv::Mat inliers;
    cv::Mat homography = cv::findHomography(
        repairPoints,
        basePoints,
        cv::RANSAC,
        5.0,
        inliers,
        3000,
        0.995
    );
    if (homography.empty()) {
        throw std::runtime_error(
            "Ingen stabil lokal transform kunde beräknas för nadirbilden."
        );
    }
    inlierCount = cv::countNonZero(inliers);
    if (inlierCount < 12) {
        throw std::runtime_error(
            "Nadirbildens lokala position är inte tillräckligt säker."
        );
    }
    if (outputPoints != nullptr) {
        std::vector<PWControlPoint> inlierPoints;
        for (int index = 0; index < int(matches.size()); ++index) {
            if (inliers.at<unsigned char>(index) == 0) {
                continue;
            }
            inlierPoints.push_back(PWControlPoint{
                0,
                1,
                repairPoints[index].x,
                repairPoints[index].y,
                basePoints[index].x,
                basePoints[index].y
            });
        }
        outputPoints->clear();
        constexpr int maximumEditablePoints = 30;
        const double stride = std::max(
            1.0,
            double(inlierPoints.size()) / maximumEditablePoints
        );
        for (double position = 0.0;
             int(position) < int(inlierPoints.size())
                && int(outputPoints->size()) < maximumEditablePoints;
             position += stride) {
            outputPoints->push_back(inlierPoints[int(position)]);
        }
    }
    homography.convertTo(homography, CV_64F);
    return homography;
}

cv::Mat repairOutputMask(
    const cv::Mat &projectionMask,
    const cv::Mat &mapX,
    const cv::Mat &mapY,
    const cv::Size &sourceSize,
    const char *exclusionMaskPath
) {
    if (
        exclusionMaskPath == nullptr
        || std::strlen(exclusionMaskPath) == 0
    ) {
        return projectionMask.clone();
    }

    const cv::Mat sourceMask = cv::imread(
        exclusionMaskPath,
        cv::IMREAD_UNCHANGED
    );
    if (sourceMask.empty()) {
        throw std::runtime_error(
            "Nadirbildens exkluderingsmask kunde inte läsas."
        );
    }

    cv::Mat exclusionAlpha;
    if (sourceMask.channels() == 4) {
        cv::extractChannel(sourceMask, exclusionAlpha, 3);
    } else if (sourceMask.channels() == 1) {
        exclusionAlpha = sourceMask;
    } else {
        cv::cvtColor(
            sourceMask,
            exclusionAlpha,
            cv::COLOR_BGR2GRAY
        );
    }
    if (exclusionAlpha.size() != sourceSize) {
        cv::resize(
            exclusionAlpha,
            exclusionAlpha,
            sourceSize,
            0.0,
            0.0,
            cv::INTER_LINEAR
        );
    }

    cv::Mat localSelection;
    cv::remap(
        exclusionAlpha,
        localSelection,
        mapX,
        mapY,
        cv::INTER_LINEAR,
        cv::BORDER_CONSTANT,
        cv::Scalar(0)
    );
    cv::Mat outputMask;
    cv::Mat localVisibility;
    cv::subtract(
        cv::Scalar::all(255),
        localSelection,
        localVisibility
    );
    cv::multiply(
        projectionMask,
        localVisibility,
        outputMask,
        1.0 / 255.0,
        CV_8U
    );
    return outputMask;
}

void writeNadirOverlay(
    const cv::Mat &repairLocal,
    const cv::Mat &repairMask,
    const cv::Mat &homography,
    const std::string &outputPath
) {
    cv::Mat alignedRepair;
    cv::Mat alignedAlpha;
    cv::warpPerspective(
        repairLocal,
        alignedRepair,
        homography,
        cv::Size(repairLocalViewSize, repairLocalViewSize),
        cv::INTER_LINEAR,
        cv::BORDER_CONSTANT,
        cv::Scalar(0, 0, 0)
    );
    cv::warpPerspective(
        repairMask,
        alignedAlpha,
        homography,
        cv::Size(repairLocalViewSize, repairLocalViewSize),
        cv::INTER_LINEAR,
        cv::BORDER_CONSTANT,
        cv::Scalar(0)
    );

    std::vector<cv::Mat> colorChannels;
    cv::split(alignedRepair, colorChannels);
    colorChannels.push_back(alignedAlpha);
    cv::Mat overlay;
    cv::merge(colorChannels, overlay);
    if (!cv::imwrite(outputPath, overlay)) {
        throw std::runtime_error(
            "Det positionerade nadirlagret kunde inte sparas."
        );
    }
}

cv::Mat registrationHomography(
    const PWNadirRegistration &registration
) {
    const double values[] = {
        registration.h00,
        registration.h01,
        registration.h02,
        registration.h10,
        registration.h11,
        registration.h12,
        registration.h20,
        registration.h21,
        registration.h22
    };
    cv::Mat homography(3, 3, CV_64F);
    std::memcpy(
        homography.ptr<double>(),
        values,
        sizeof(values)
    );
    return homography;
}

cv::Mat manualRepairHomography(
    double translationX,
    double translationY,
    double rotationDegrees,
    double scale
) {
    const double angle = radians(rotationDegrees);
    const double cosine = std::cos(angle) * scale;
    const double sine = std::sin(angle) * scale;
    const double center = repairLocalViewSize / 2.0;
    const double values[] = {
        cosine,
        -sine,
        center + translationX - cosine * center + sine * center,
        sine,
        cosine,
        center + translationY - sine * center - cosine * center,
        0.0,
        0.0,
        1.0
    };
    cv::Mat homography(3, 3, CV_64F);
    std::memcpy(
        homography.ptr<double>(),
        values,
        sizeof(values)
    );
    return homography;
}

cv::Mat cornerRepairHomography(
    const double *offsets,
    const double *bounds
) {
    if (offsets == nullptr || bounds == nullptr) {
        return cv::Mat::eye(3, 3, CV_64F);
    }
    const float left = float(bounds[0] * repairLocalViewSize);
    const float top = float(bounds[1] * repairLocalViewSize);
    const float right = float(
        (bounds[0] + bounds[2]) * repairLocalViewSize
    );
    const float bottom = float(
        (bounds[1] + bounds[3]) * repairLocalViewSize
    );
    const cv::Point2f source[] = {
        {left, top}, {right, top}, {right, bottom}, {left, bottom}
    };
    const cv::Point2f destination[] = {
        {left + float(offsets[0]), top + float(offsets[1])},
        {right + float(offsets[2]), top + float(offsets[3])},
        {right + float(offsets[4]), bottom + float(offsets[5])},
        {left + float(offsets[6]), bottom + float(offsets[7])}
    };
    return cv::getPerspectiveTransform(source, destination);
}

cv::Mat imageWithAlpha(
    const cv::Mat &color,
    const cv::Mat &alpha
) {
    std::vector<cv::Mat> channels;
    cv::split(color, channels);
    channels.push_back(alpha);
    cv::Mat result;
    cv::merge(channels, result);
    return result;
}

cv::Mat colorMatchedRepair(
    const cv::Mat &base,
    const cv::Mat &repair,
    const cv::Mat &alpha
) {
    cv::Mat visible;
    cv::compare(alpha, 96, visible, cv::CMP_GT);
    if (cv::countNonZero(visible) < 256) {
        return repair;
    }

    cv::Mat baseLab;
    cv::Mat repairLab;
    cv::cvtColor(base, baseLab, cv::COLOR_BGR2Lab);
    cv::cvtColor(repair, repairLab, cv::COLOR_BGR2Lab);
    baseLab.convertTo(baseLab, CV_32F);
    repairLab.convertTo(repairLab, CV_32F);

    cv::Scalar baseMean;
    cv::Scalar baseDeviation;
    cv::Scalar repairMean;
    cv::Scalar repairDeviation;
    cv::meanStdDev(baseLab, baseMean, baseDeviation, visible);
    cv::meanStdDev(repairLab, repairMean, repairDeviation, visible);

    std::vector<cv::Mat> channels;
    cv::split(repairLab, channels);
    for (int channel = 0; channel < 3; ++channel) {
        // Match luminance contrast conservatively. For chroma, an offset is
        // safer than scaling and keeps coloured objects in the repair intact.
        const double gain = channel == 0
            ? std::clamp(
                baseDeviation[channel]
                    / std::max(1.0, repairDeviation[channel]),
                0.75,
                1.25
            )
            : 1.0;
        channels[channel] =
            (channels[channel] - repairMean[channel]) * gain
            + baseMean[channel];
    }
    cv::merge(channels, repairLab);
    repairLab.convertTo(repairLab, CV_8U);
    cv::Mat matched;
    cv::cvtColor(repairLab, matched, cv::COLOR_Lab2BGR);
    return matched;
}

cv::Mat centeredPoleHoleMask(const cv::Mat &baseLocal) {
    cv::Mat gray;
    cv::cvtColor(baseLocal, gray, cv::COLOR_BGR2GRAY);

    // The stitched ring has no alpha channel. Pixels outside its coverage are
    // consequently black in result.jpg. Keep only the dark component that
    // actually contains the pole; naturally black objects elsewhere must not
    // enlarge the repair area.
    cv::Mat dark;
    // JPEG compression and interpolation turn nominally empty black coverage
    // into dark blue/gray edge pixels (C reaches roughly luma 35 at nadir).
    // A connected-component check at the exact pole keeps the more generous
    // threshold from mistaking unrelated dark objects for the coverage hole.
    cv::threshold(gray, dark, 48, 255, cv::THRESH_BINARY_INV);
    cv::morphologyEx(
        dark,
        dark,
        cv::MORPH_CLOSE,
        cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(5, 5))
    );
    const cv::Point center(
        baseLocal.cols / 2,
        baseLocal.rows / 2
    );
    if (dark.at<unsigned char>(center) == 0) {
        return cv::Mat::zeros(baseLocal.size(), CV_8U);
    }

    cv::Mat labels;
    cv::connectedComponents(dark, labels, 8, CV_32S);
    const int poleLabel = labels.at<int>(center);
    cv::Mat hole;
    cv::compare(labels, poleLabel, hole, cv::CMP_EQ);
    const int holeArea = cv::countNonZero(hole);
    const cv::Rect bounds = cv::boundingRect(hole);
    const int margin = 8;
    const bool touchesProjectionEdge = bounds.x < margin
        || bounds.y < margin
        || bounds.br().x > baseLocal.cols - margin
        || bounds.br().y > baseLocal.rows - margin;
    if (holeArea < 256
        || holeArea > int(baseLocal.total() * 0.20)
        || touchesProjectionEdge) {
        // At a covered pole, a black tripod, coat or the equirectangular
        // singularity can form one enormous dark component through the exact
        // centre. That is scene content, not missing image coverage. Treat it
        // as a normal covered pole; the seam logic can then use the verified
        // repair layer's useful coverage instead of following the dark object.
        return cv::Mat::zeros(baseLocal.size(), CV_8U);
    }
    return hole;
}

void writeNadirBlendInputs(
    const cv::Mat &baseLocal,
    const cv::Mat &repairLocal,
    const cv::Mat &repairMask,
    const cv::Mat &homography,
    bool automaticPoleBlend,
    double translationX,
    double translationY,
    double rotationDegrees,
    double scale,
    const double *cornerOffsets,
    const double *contentBounds,
    const std::string &baseOutputPath,
    const std::string &repairOutputPath
) {
    const cv::Mat adjustedHomography =
        cornerRepairHomography(cornerOffsets, contentBounds)
            * manualRepairHomography(
            translationX,
            translationY,
            rotationDegrees,
            scale
        ) * homography;

    cv::Mat alignedRepair;
    cv::Mat alignedAlpha;
    cv::warpPerspective(
        repairLocal,
        alignedRepair,
        adjustedHomography,
        cv::Size(repairLocalViewSize, repairLocalViewSize),
        cv::INTER_LINEAR,
        cv::BORDER_CONSTANT,
        cv::Scalar(0, 0, 0)
    );
    cv::warpPerspective(
        repairMask,
        alignedAlpha,
        adjustedHomography,
        cv::Size(repairLocalViewSize, repairLocalViewSize),
        cv::INTER_LINEAR,
        cv::BORDER_CONSTANT,
        cv::Scalar(0)
    );

    alignedRepair = colorMatchedRepair(
        baseLocal,
        alignedRepair,
        alignedAlpha
    );

    cv::Mat baseAlpha(
        baseLocal.size(),
        CV_8U,
        cv::Scalar(255)
    );
    const cv::Mat poleHole = automaticPoleBlend
        ? centeredPoleHoleMask(baseLocal)
        : cv::Mat::zeros(baseLocal.size(), CV_8U);
    if (automaticPoleBlend) {
        if (cv::countNonZero(poleHole) >= 256) {
            // Fill the actual uncovered cap and give Enblend a broad ring of
            // valid overlap in which to hide the seam. Do not let a pole image
            // replace the entire otherwise valid ring view merely because its
            // projection happens to cover all 1600x1600 local pixels.
            cv::Mat outsideHole;
            cv::bitwise_not(poleHole, outsideHole);
            cv::Mat distanceFromHole;
            cv::distanceTransform(
                outsideHole,
                distanceFromHole,
                cv::DIST_L2,
                cv::DIST_MASK_PRECISE
            );
            cv::Mat repairRegion;
            cv::compare(distanceFromHole, 160.0, repairRegion, cv::CMP_LE);
            cv::Mat outsideRepairRegion;
            cv::bitwise_not(repairRegion, outsideRepairRegion);
            alignedAlpha.setTo(cv::Scalar(0), outsideRepairRegion);
            baseAlpha.setTo(cv::Scalar(0), poleHole);
        } else {
            // A hand-held pole image has a different camera centre. Give
            // Enblend enough overlap to follow ground-plane details, but keep
            // the repair local to the pole so parallax cannot pull nearby
            // tables, chairs, or people into the published overlay.
            cv::Mat repairVisibility;
            cv::compare(
                alignedAlpha,
                8,
                repairVisibility,
                cv::CMP_GT
            );
            cv::Mat maximumRepairRegion = cv::Mat::zeros(
                alignedAlpha.size(),
                CV_8U
            );
            cv::circle(
                maximumRepairRegion,
                cv::Point(
                    repairLocalViewSize / 2,
                    repairLocalViewSize / 2
                ),
                static_cast<int>(repairLocalViewSize * 0.30),
                cv::Scalar(255),
                cv::FILLED,
                cv::LINE_AA
            );
            cv::bitwise_and(
                maximumRepairRegion,
                repairVisibility,
                maximumRepairRegion
            );
            cv::Mat outsideMaximumRepairRegion;
            cv::bitwise_not(
                maximumRepairRegion,
                outsideMaximumRepairRegion
            );
            alignedAlpha.setTo(
                cv::Scalar(0),
                outsideMaximumRepairRegion
            );

            cv::Mat forcedRepairCore;
            forcedRepairCore = cv::Mat::zeros(
                alignedAlpha.size(),
                CV_8U
            );
            cv::circle(
                forcedRepairCore,
                cv::Point(
                    repairLocalViewSize / 2,
                    repairLocalViewSize / 2
                ),
                static_cast<int>(repairLocalViewSize * 0.10),
                cv::Scalar(255),
                cv::FILLED,
                cv::LINE_AA
            );
            cv::bitwise_and(
                forcedRepairCore,
                maximumRepairRegion,
                forcedRepairCore
            );
            baseAlpha.setTo(cv::Scalar(0), forcedRepairCore);
        }
    } else {
        // A fully covered pole can still be an intentional repair (for
        // example to remove a tripod). Preserve the established behaviour in
        // that case and force the selected repair except for a narrow overlap.
        cv::Mat repairVisibility;
        cv::compare(
            alignedAlpha,
            8,
            repairVisibility,
            cv::CMP_GT
        );
        cv::Mat distanceInsideRepair;
        cv::distanceTransform(
            repairVisibility,
            distanceInsideRepair,
            cv::DIST_L2,
            cv::DIST_MASK_PRECISE
        );
        double maximumDistance = 0.0;
        cv::minMaxLoc(
            distanceInsideRepair,
            nullptr,
            &maximumDistance
        );
        const double overlapWidth = std::min(
            16.0,
            maximumDistance * 0.2
        );
        cv::Mat forcedRepairCore;
        cv::compare(
            distanceInsideRepair,
            overlapWidth,
            forcedRepairCore,
            cv::CMP_GT
        );
        baseAlpha.setTo(cv::Scalar(0), forcedRepairCore);
    }
    if (!cv::imwrite(
        baseOutputPath,
        imageWithAlpha(baseLocal, baseAlpha)
    )) {
        throw std::runtime_error(
            "Panoramats lokala nadirvy kunde inte förberedas för Enblend."
        );
    }
    if (!cv::imwrite(
        repairOutputPath,
        imageWithAlpha(alignedRepair, alignedAlpha)
    )) {
        throw std::runtime_error(
            "Nadirreparationen kunde inte förberedas för Enblend."
        );
    }
}

void writeBlendedNadirOverlay(
    const cv::Mat &blendedLocal,
    const cv::Mat &repairLayer,
    const cv::Mat &repairSeamMask,
    const std::string &outputPath
) {
    cv::Mat color;
    if (blendedLocal.channels() == 4) {
        cv::cvtColor(blendedLocal, color, cv::COLOR_BGRA2BGR);
    } else if (blendedLocal.channels() == 3) {
        color = blendedLocal;
    } else if (blendedLocal.channels() == 1) {
        cv::cvtColor(blendedLocal, color, cv::COLOR_GRAY2BGR);
    } else {
        throw std::runtime_error(
            "Enblend skapade ett lokalt resultat med okänt pixelformat."
        );
    }
    if (
        color.cols != repairLocalViewSize
        || color.rows != repairLocalViewSize
    ) {
        throw std::runtime_error(
            "Enblend skapade en lokal nadirvy med fel pixelstorlek."
        );
    }

    if (repairLayer.empty() || repairLayer.size() != color.size()
        || repairLayer.channels() != 4) {
        throw std::runtime_error(
            "Enblends reparationslager saknar giltig alfa."
        );
    }
    std::vector<cv::Mat> repairChannels;
    cv::split(repairLayer, repairChannels);
    cv::Mat repairCoverage;
    cv::compare(repairChannels[3], 8, repairCoverage, cv::CMP_GT);

    if (repairSeamMask.empty() || repairSeamMask.size() != color.size()) {
        throw std::runtime_error(
            "Enblends sömmask för reparationsbilden är ogiltig."
        );
    }
    cv::Mat seamGray;
    if (repairSeamMask.channels() == 1) {
        seamGray = repairSeamMask;
    } else if (repairSeamMask.channels() == 3) {
        cv::cvtColor(repairSeamMask, seamGray, cv::COLOR_BGR2GRAY);
    } else if (repairSeamMask.channels() == 4) {
        cv::cvtColor(repairSeamMask, seamGray, cv::COLOR_BGRA2GRAY);
    } else {
        throw std::runtime_error(
            "Enblends sömmask har ett okänt pixelformat."
        );
    }
    cv::Mat seamSelection;
    cv::compare(seamGray, 0, seamSelection, cv::CMP_GT);
    cv::bitwise_and(seamSelection, repairCoverage, seamSelection);

    // Enblend has already decided where the repair wins. Publish that actual
    // seam instead of the repair image's entire projected coverage. A small
    // dilation includes Enblend's multiresolution transition; an internal
    // feather then joins the local result back to the live panorama cleanly.
    cv::Mat publishedRegion;
    cv::dilate(
        seamSelection,
        publishedRegion,
        cv::getStructuringElement(
            cv::MORPH_ELLIPSE,
            cv::Size(65, 65)
        )
    );
    cv::bitwise_and(publishedRegion, repairCoverage, publishedRegion);
    if (cv::countNonZero(publishedRegion) < 256) {
        throw std::runtime_error(
            "Enblends sömmask innehåller ingen användbar nadirreparation."
        );
    }
    cv::Mat distanceInsidePublishedRegion;
    cv::distanceTransform(
        publishedRegion,
        distanceInsidePublishedRegion,
        cv::DIST_L2,
        cv::DIST_MASK_PRECISE
    );
    constexpr double featherWidth = 24.0;
    cv::Mat normalized;
    distanceInsidePublishedRegion.convertTo(
        normalized,
        CV_32F,
        1.0 / featherWidth
    );
    cv::min(normalized, 1.0, normalized);
    cv::Mat alpha;
    normalized.convertTo(alpha, CV_8U, 255.0);

    if (!cv::imwrite(outputPath, imageWithAlpha(color, alpha))) {
        throw std::runtime_error(
            "Den blandade nadirförhandsvisningen kunde inte sparas."
        );
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
    const double *nominalYaws,
    const int *positioningImageFlags,
    int imageCount,
    double horizontalFieldOfView,
    int lensModel,
    PWControlPoint **controlPoints,
    int *controlPointCount,
    char **errorMessage
) {
    try {
        lastPairDiagnostics.clear();
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

        if (nominalYaws == nullptr) {
            const cv::Ptr<cv::SIFT> rawDetector = cv::SIFT::create(
                5000, 3, 0.018, 12
            );
            struct RawFeatures {
                std::vector<cv::KeyPoint> keypoints;
                cv::Mat descriptors;
                double scale = 1.0;
            };
            std::vector<RawFeatures> rawFeatures(imageCount);
            std::vector<cv::Size> rawSizes(imageCount);
            for (int index = 0; index < imageCount; ++index) {
                const cv::Mat image = cv::imread(
                    imagePaths[index], cv::IMREAD_GRAYSCALE
                );
                if (image.empty()) {
                    throw std::runtime_error(
                        "Kunde inte läsa " + std::string(imagePaths[index]) + "."
                    );
                }
                rawSizes[index] = image.size();
                cv::Mat matchingImage;
                rawFeatures[index].scale = std::min(
                    1.0, 2000.0 / std::max(image.cols, image.rows)
                );
                cv::resize(
                    image, matchingImage, cv::Size(),
                    rawFeatures[index].scale,
                    rawFeatures[index].scale,
                    cv::INTER_AREA
                );
                cv::Mat valid;
                cv::compare(matchingImage, 3, valid, cv::CMP_GE);
                if (horizontalFieldOfView >= 110.0) {
                    // The black rim of a circular Sigma frame is identical in
                    // every exposure and otherwise produces very convincing
                    // false SIFT matches between non-overlapping views. Keep
                    // raw features a small descriptor-width inside the
                    // calibrated image circle.
                    const int longSide = std::max(
                        matchingImage.cols,
                        matchingImage.rows
                    );
                    const int radius = std::max(
                        1,
                        int(std::lround(
                            longSide
                            * (sigmaDXCropRadiusPerLongSide - 0.025)
                        ))
                    );
                    cv::Mat circleMask = cv::Mat::zeros(
                        matchingImage.size(),
                        CV_8U
                    );
                    cv::circle(
                        circleMask,
                        cv::Point(
                            matchingImage.cols / 2,
                            matchingImage.rows / 2
                        ),
                        radius,
                        cv::Scalar(255),
                        cv::FILLED,
                        cv::LINE_8
                    );
                    cv::bitwise_and(valid, circleMask, valid);
                }
                rawDetector->detectAndCompute(
                    matchingImage, valid, rawFeatures[index].keypoints,
                    rawFeatures[index].descriptors
                );
            }

            std::vector<PWControlPoint> rawResult;
            std::vector<std::vector<int>> rawGraph(imageCount);
            std::vector<int> positioningImageIndices;
            for (int index = 0; index < imageCount; ++index) {
                if (positioningImageFlags == nullptr
                    || positioningImageFlags[index] != 0) {
                    positioningImageIndices.push_back(index);
                }
            }
            auto isPositioningSequenceTransition = [&](int first, int second) {
                if (positioningImageIndices.size() < 2) return false;
                for (int position = 0;
                     position < int(positioningImageIndices.size());
                     ++position) {
                    const int current = positioningImageIndices[position];
                    const int next = positioningImageIndices[
                        (position + 1) % positioningImageIndices.size()
                    ];
                    if ((current == first && next == second)
                        || (current == second && next == first)) {
                        return true;
                    }
                }
                return false;
            };
            for (int first = 0; first < imageCount; ++first) {
                for (int second = first + 1; second < imageCount; ++second) {
                    const bool requiredSparseRingTransition =
                        lensModel != PWLensModelRectilinear
                        && isPositioningSequenceTransition(first, second);
                    MatchCounts matchCounts;
                    const auto matches = mutualRatioMatches(
                        rawFeatures[first].descriptors,
                        rawFeatures[second].descriptors,
                        &matchCounts
                    );
                    // The relaxed lower-pole pool is valuable in denser
                    // Sigma rigs, but a four-frame ring has only one overlap
                    // on either side of every image. A handful of merely
                    // rotation-plausible paving matches can then outweigh
                    // the strict matches and tip the complete ring into the
                    // wrong pitch. Keep four-frame rings on the reciprocal
                    // descriptor pool; genuine polar matches from that pool
                    // remain eligible for the balanced selection below.
                    const std::vector<cv::DMatch> polarCandidates =
                        lensModel == PWLensModelSigma8DX && imageCount > 4
                        ? mutualRatioMatches(
                            rawFeatures[first].descriptors,
                            rawFeatures[second].descriptors,
                            nullptr,
                            0.99f
                        )
                        : matches;
                    const int minimumDescriptorMatchCount =
                        requiredSparseRingTransition ? 6 : 8;
                    if (matches.size() < minimumDescriptorMatchCount) {
                        lastPairDiagnostics.push_back({
                            first, second,
                            int(rawFeatures[first].keypoints.size()),
                            int(rawFeatures[second].keypoints.size()),
                            matchCounts.ratio, matchCounts.mutual,
                            0, 0, 0.0, 0.0
                        });
                        continue;
                    }
                    const cv::Size firstMatchingSize(
                        int(rawSizes[first].width * rawFeatures[first].scale),
                        int(rawSizes[first].height * rawFeatures[first].scale)
                    );
                    const cv::Size secondMatchingSize(
                        int(rawSizes[second].width * rawFeatures[second].scale),
                        int(rawSizes[second].height * rawFeatures[second].scale)
                    );
                    // A calibrated 3D rotation describes every pair captured
                    // from one tripod position, including ring-to-zenith
                    // pairs. Do not fall back to a planar homography merely
                    // because a zenith image makes the alignment set larger
                    // than four images; a homography only retains one local
                    // patch of a wide fisheye overlap.
                    const bool calibratedFisheye =
                        lensModel != PWLensModelRectilinear;
                    const int minimumGeometricMatchCount =
                        requiredSparseRingTransition ? 6 : 8;
                    std::vector<cv::DMatch> inliers;
                    std::map<std::pair<int, int>, double> rotationErrors;
                    bool usedSparseClosureFallback = false;
                    if (calibratedFisheye) {
                        inliers = fisheyeRotationConsistentMatches(
                            matches,
                            polarCandidates,
                            rawFeatures[first].keypoints,
                            rawFeatures[second].keypoints,
                            firstMatchingSize,
                            secondMatchingSize,
                            horizontalFieldOfView,
                            lensModel,
                            8,
                            3,
                            false,
                            &rotationErrors
                        );
                        // A circular-fisheye ring can close through a narrow
                        // strip at the frame edges. Preserve the
                        // normal, coverage-first result whenever it succeeds.
                        // Only a missing real ring transition gets a second
                        // pass that favors the dominant rotation consensus;
                        // PTGui can solve such a transition from six or seven
                        // consistent points across two edge cells. The bundle
                        // adjustment later rejects it unless its final
                        // residuals agree with the other ring transitions.
                        if (inliers.size() < 8
                            && requiredSparseRingTransition) {
                            inliers = fisheyeRotationConsistentMatches(
                                matches,
                                polarCandidates,
                                rawFeatures[first].keypoints,
                                rawFeatures[second].keypoints,
                                firstMatchingSize,
                                secondMatchingSize,
                                horizontalFieldOfView,
                                lensModel,
                                6,
                                2,
                                true,
                                &rotationErrors
                            );
                            usedSparseClosureFallback = !inliers.empty();
                        }
                    } else {
                        std::vector<cv::Point2f> firstPoints;
                        std::vector<cv::Point2f> secondPoints;
                        for (const auto &match : matches) {
                            firstPoints.push_back(
                                rawFeatures[first].keypoints[match.queryIdx].pt
                            );
                            secondPoints.push_back(
                                rawFeatures[second].keypoints[match.trainIdx].pt
                            );
                        }
                        cv::Mat inlierMask;
                        cv::findHomography(
                            firstPoints, secondPoints, cv::RANSAC, 4.0,
                            inlierMask, 3000, 0.997
                        );
                        for (int index = 0;
                             index < int(matches.size()); ++index) {
                            if (inlierMask.rows > index
                                && inlierMask.at<unsigned char>(index) != 0) {
                                inliers.push_back(matches[index]);
                            }
                        }
                    }
                    if (inliers.size() < minimumGeometricMatchCount) {
                        lastPairDiagnostics.push_back({
                            first, second,
                            int(rawFeatures[first].keypoints.size()),
                            int(rawFeatures[second].keypoints.size()),
                            matchCounts.ratio, matchCounts.mutual,
                            int(inliers.size()), 0, 0.0, 0.0
                        });
                        continue;
                    }
                    // Keep the strongest matches across the complete overlap
                    // and balance both endpoints independently. This is
                    // important for ring and pole images alike.
                    std::vector<cv::DMatch> selected =
                        spatiallyBalancedSelection(
                            inliers,
                            rawFeatures[first].keypoints,
                            rawFeatures[second].keypoints,
                            firstMatchingSize,
                            secondMatchingSize,
                            lensModel == PWLensModelSigma8DX && imageCount > 4,
                            -1,
                            usedSparseClosureFallback ? 0.02 : 0.05,
                            calibratedFisheye ? &rotationErrors : nullptr
                        );
                    if (lensModel == PWLensModelSigma8DX
                        && imageCount == 4
                        && selected.size() < 20
                        && !usedSparseClosureFallback) {
                        // A sparse side of a four-frame ring is geometrically
                        // dominated by its ordinary overlap. Keep at most one
                        // deep-pole constraint there: that is enough to anchor
                        // the vertical extent without allowing a small second
                        // cluster to rotate the entire ring into another valid
                        // but upside-shifted fisheye solution.
                        selected = spatiallyBalancedSelection(
                            inliers,
                            rawFeatures[first].keypoints,
                            rawFeatures[second].keypoints,
                            firstMatchingSize,
                            secondMatchingSize,
                            false,
                            1,
                            0.05,
                            &rotationErrors
                        );
                    }
                    lastPairDiagnostics.push_back({
                        first, second,
                        int(rawFeatures[first].keypoints.size()),
                        int(rawFeatures[second].keypoints.size()),
                        matchCounts.ratio, matchCounts.mutual,
                        int(inliers.size()), int(selected.size()),
                        0.0, selectedSpatialCoverage(
                            selected,
                            rawFeatures[first].keypoints,
                            rawFeatures[second].keypoints,
                            firstMatchingSize,
                            secondMatchingSize
                        )
                    });
                    // A calibrated closing transition may cover only three
                    // independent cells even when its rotation consensus is
                    // strong. Keep that narrow closure for the global
                    // residual check; ordinary extra pairs still require six
                    // selected points.
                    const int minimumSelectedControlPointCount =
                        requiredSparseRingTransition ? 3 : 6;
                    if (selected.size() < minimumSelectedControlPointCount) {
                        continue;
                    }
                    rawGraph[first].push_back(second);
                    rawGraph[second].push_back(first);
                    for (const auto &match : selected) {
                        const cv::Point2f a = rawFeatures[first]
                            .keypoints[match.queryIdx].pt;
                        const cv::Point2f b = rawFeatures[second]
                            .keypoints[match.trainIdx].pt;
                        rawResult.push_back({
                            first, second,
                            a.x / rawFeatures[first].scale,
                            a.y / rawFeatures[first].scale,
                            b.x / rawFeatures[second].scale,
                            b.y / rawFeatures[second].scale
                        });
                    }
                }
            }
            std::vector<bool> visited(imageCount, false);
            std::vector<int> pending = {0};
            visited[0] = true;
            while (!pending.empty()) {
                const int current = pending.back();
                pending.pop_back();
                for (const int neighbor : rawGraph[current]) {
                    if (!visited[neighbor]) {
                        visited[neighbor] = true;
                        pending.push_back(neighbor);
                    }
                }
            }
            if (std::find(visited.begin(), visited.end(), false)
                != visited.end()) {
                throw std::runtime_error(
                    "Kontrollpunkterna bildar inte en sammanhängande 360°-ring."
                );
            }
            return copyResult(
                rawResult, controlPoints, controlPointCount, errorMessage
            );
        }

        std::vector<PWOrientation> orientations;
        std::vector<cv::Size> sourceSizes;
        std::vector<NormalizedFeatures> features;
        for (int index = 0; index < imageCount; ++index) {
            const PWOrientation orientation = {
                nominalYaws == nullptr
                    ? index * 360.0 / imageCount
                    : nominalYaws[index],
                0.0,
                0.0
            };
            orientations.push_back(orientation);
            sourceSizes.push_back(sourceSizeForPath(imagePaths[index]));
            features.push_back(normalizedFeatures(
                imagePaths[index],
                horizontalFieldOfView,
                orientation,
                detector
            ));
        }

        std::vector<PWControlPoint> result;
        std::vector<std::vector<int>> overlapGraph(imageCount);
        for (int first = 0; first < imageCount; ++first) {
            for (int second = first + 1; second < imageCount; ++second) {
                const std::vector<cv::DMatch> matches = geometricMatches(
                    features[first],
                    features[second]
                );
                if (matches.size() < 12) {
                    continue;
                }
                overlapGraph[first].push_back(second);
                overlapGraph[second].push_back(first);
                appendControlPoints(
                    first,
                    second,
                    features[first],
                    features[second],
                    matches,
                    sourceSizes[first],
                    sourceSizes[second],
                    horizontalFieldOfView,
                    orientations[first],
                    orientations[second],
                    result
                );
            }
        }
        std::vector<bool> visited(imageCount, false);
        std::vector<int> pending = {0};
        visited[0] = true;
        while (!pending.empty()) {
            const int current = pending.back();
            pending.pop_back();
            for (const int neighbor : overlapGraph[current]) {
                if (!visited[neighbor]) {
                    visited[neighbor] = true;
                    pending.push_back(neighbor);
                }
            }
        }
        const auto disconnected = std::find(
            visited.begin(),
            visited.end(),
            false
        );
        if (disconnected != visited.end()) {
            throw std::runtime_error(
                "Kontrollpunkterna bildar inte en sammanhängande 360°-ring."
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

int PWGeneratePairControlPoints(
    const char *firstImagePath,
    const char *secondImagePath,
    int firstImageIndex,
    int secondImageIndex,
    int ringImageCount,
    double horizontalFieldOfView,
    int lensModel,
    PWControlPoint **controlPoints,
    int *controlPointCount,
    char **errorMessage
) {
    try {
        if (
            firstImagePath == nullptr
            || secondImagePath == nullptr
            || ringImageCount < 2
            || firstImageIndex < 0
            || secondImageIndex < 0
            || firstImageIndex >= ringImageCount
            || secondImageIndex >= ringImageCount
            || firstImageIndex == secondImageIndex
        ) {
            throw std::runtime_error("Det valda bildparet är ogiltigt.");
        }
        const char *paths[] = {firstImagePath, secondImagePath};
        const int succeeded = PWGenerateRingControlPoints(
            paths,
            nullptr,
            nullptr,
            2,
            horizontalFieldOfView,
            lensModel,
            controlPoints,
            controlPointCount,
            errorMessage
        );
        if (!succeeded) return 0;
        for (int index = 0; index < *controlPointCount; ++index) {
            (*controlPoints)[index].firstImage = firstImageIndex;
            (*controlPoints)[index].secondImage = secondImageIndex;
        }
        return 1;
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

int PWCopyLastControlPointPairDiagnostics(
    PWControlPointPairDiagnostic **diagnostics,
    int *diagnosticCount
) {
    if (diagnostics == nullptr || diagnosticCount == nullptr) return 0;
    *diagnosticCount = int(lastPairDiagnostics.size());
    *diagnostics = static_cast<PWControlPointPairDiagnostic *>(std::malloc(
        lastPairDiagnostics.size() * sizeof(PWControlPointPairDiagnostic)
    ));
    if (*diagnostics == nullptr && !lastPairDiagnostics.empty()) {
        *diagnosticCount = 0;
        return 0;
    }
    if (!lastPairDiagnostics.empty()) {
        std::memcpy(
            *diagnostics,
            lastPairDiagnostics.data(),
            lastPairDiagnostics.size() * sizeof(PWControlPointPairDiagnostic)
        );
    }
    return 1;
}

int PWEstimateControlPointOrientations(
    const PWControlPoint *controlPoints,
    int controlPointCount,
    const int *imageWidths,
    const int *imageHeights,
    int imageCount,
    double horizontalFieldOfView,
    int lensModel,
    PWOrientation *orientations,
    char **errorMessage
) {
    try {
        if (controlPoints == nullptr || controlPointCount < 1
            || imageWidths == nullptr || imageHeights == nullptr
            || imageCount < 2 || orientations == nullptr
            || errorMessage == nullptr
            || lensModel == PWLensModelRectilinear) {
            throw std::runtime_error(
                "Underlaget for sfariska startposer ar ofullstandigt."
            );
        }
        *errorMessage = nullptr;

        const RaysByImagePair rays = controlPointRays(
            controlPoints,
            controlPointCount,
            imageWidths,
            imageHeights,
            imageCount,
            horizontalFieldOfView,
            lensModel
        );
        // Recovery points have already survived Hugin's global residual
        // filtering. A sparse zenith view may retain only three to five good
        // points on its sole connection, which is still enough to seed a 3D
        // rotation. Positioning evidence keeps the stricter six-point rule.
        const std::vector<RotationEdge> edges = strongestRotationEdges(rays, 3);
        const std::vector<cv::Matx33d> worldRotations =
            worldRotationsFromStrongestEdges(edges, imageCount);
        for (int index = 0; index < imageCount; ++index) {
            orientations[index] = panoramaOrientation(worldRotations[index]);
        }
        return 1;
    } catch (const std::exception &error) {
        if (errorMessage != nullptr) {
            *errorMessage = copiedString(error.what());
        }
        return 0;
    }
}

int PWEstimatePositioningEvidence(
    const PWControlPoint *controlPoints,
    int controlPointCount,
    const int *imageWidths,
    const int *imageHeights,
    int imageCount,
    double horizontalFieldOfView,
    int lensModel,
    PWPositioningEvidence *evidence,
    char **errorMessage
) {
    try {
        if (controlPoints == nullptr || controlPointCount < 1
            || imageWidths == nullptr || imageHeights == nullptr
            || imageCount < 2 || evidence == nullptr
            || errorMessage == nullptr
            || lensModel == PWLensModelRectilinear) {
            throw std::runtime_error(
                "Underlaget for geometrisk positioneringsevidens ar "
                "ofullstandigt."
            );
        }
        *errorMessage = nullptr;

        const RaysByImagePair rays = controlPointRays(
            controlPoints,
            controlPointCount,
            imageWidths,
            imageHeights,
            imageCount,
            horizontalFieldOfView,
            lensModel
        );
        const std::vector<RotationEdge> edges = strongestRotationEdges(rays);
        const std::vector<cv::Matx33d> worldRotations =
            worldRotationsFromStrongestEdges(edges, imageCount);

        std::vector<std::vector<double>> residuals(imageCount);
        std::vector<std::set<int>> connectedImages(imageCount);
        for (const auto &entry : rays) {
            const int first = entry.first.first;
            const int second = entry.first.second;
            const cv::Matx33d predictedRotation =
                worldRotations[first].t() * worldRotations[second];
            connectedImages[first].insert(second);
            connectedImages[second].insert(first);
            for (const RayPair &pair : entry.second) {
                const double degrees =
                    rayRotationError(pair, predictedRotation) * 180.0 / pi;
                residuals[first].push_back(degrees);
                residuals[second].push_back(degrees);
            }
        }

        for (int image = 0; image < imageCount; ++image) {
            std::vector<double> contaminatedRigResiduals;
            for (const auto &entry : rays) {
                const int first = entry.first.first;
                const int second = entry.first.second;
                if (first == image || second == image) continue;
                const cv::Matx33d predictedRotation =
                    worldRotations[first].t() * worldRotations[second];
                for (const RayPair &pair : entry.second) {
                    contaminatedRigResiduals.push_back(
                        rayRotationError(pair, predictedRotation)
                            * 180.0 / pi
                    );
                }
            }

            std::vector<double> rigResiduals;
            RaysByImagePair rigRays;
            for (const auto &entry : rays) {
                if (entry.first.first != image
                    && entry.first.second != image) {
                    rigRays.insert(entry);
                }
            }
            try {
                const std::vector<RotationEdge> rigEdges =
                    strongestRotationEdges(rigRays);
                const std::vector<cv::Matx33d> rigRotations =
                    worldRotationsFromStrongestEdges(
                        rigEdges, imageCount, image
                    );
                for (const auto &entry : rigRays) {
                    const int first = entry.first.first;
                    const int second = entry.first.second;
                    const cv::Matx33d predictedRotation =
                        rigRotations[first].t() * rigRotations[second];
                    for (const RayPair &pair : entry.second) {
                        rigResiduals.push_back(
                            rayRotationError(pair, predictedRotation)
                                * 180.0 / pi
                        );
                    }
                }
            } catch (const std::exception &) {
                // A disconnected leave-one-out graph cannot prove that
                // removing this image improves the shared camera rig.
                rigResiduals.clear();
            }
            const PWOrientation orientation =
                panoramaOrientation(worldRotations[image]);
            const double unavailable =
                std::numeric_limits<double>::infinity();
            evidence[image] = {
                orientation.yaw,
                orientation.pitch,
                orientation.roll,
                int(residuals[image].size()),
                int(connectedImages[image].size()),
                median(residuals[image]),
                percentile(residuals[image], 0.9),
                median(contaminatedRigResiduals),
                percentile(contaminatedRigResiduals, 0.9),
                rigResiduals.empty() ? unavailable : median(rigResiduals),
                rigResiduals.empty() ? unavailable
                    : percentile(rigResiduals, 0.9)
            };
        }
        return 1;
    } catch (const std::exception &error) {
        if (errorMessage != nullptr) {
            *errorMessage = copiedString(error.what());
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
        const cv::Size zenithSourceSize = sourceSizeForPath(zenithImagePath);
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
                horizontalFieldOfView,
                candidate,
                detector
            );
            std::vector<std::vector<cv::DMatch>> pairMatches;
            int score = 0;
            for (const NormalizedFeatures &ring : ringFeatures) {
                pairMatches.push_back(
                    geometricMatches(ring, candidateFeatures, false)
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
                zenithSourceSize,
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

int PWSolvePoleSimilarity(
    const PWControlPoint *controlPoints,
    int controlPointCount,
    PWNadirRegistration *registration,
    double *errors,
    char **errorMessage
) {
    try {
        if (controlPoints == nullptr || controlPointCount < 4
            || registration == nullptr || errorMessage == nullptr) {
            throw std::runtime_error(
                "Minst fyra kontrollpunkter krävs för polens grovplacering."
            );
        }
        std::vector<cv::Point2f> repairPoints;
        std::vector<cv::Point2f> basePoints;
        for (int index = 0; index < controlPointCount; ++index) {
            repairPoints.emplace_back(
                controlPoints[index].firstX, controlPoints[index].firstY
            );
            basePoints.emplace_back(
                controlPoints[index].secondX, controlPoints[index].secondY
            );
        }
        cv::Mat inliers;
        cv::Mat affine = cv::estimateAffinePartial2D(
            repairPoints,
            basePoints,
            inliers,
            cv::RANSAC,
            12.0,
            5000,
            0.995,
            10
        );
        const int inlierCount = inliers.empty() ? 0 : cv::countNonZero(inliers);
        const int requiredInliers = std::max(
            6, int(std::ceil(controlPointCount * 0.30))
        );
        if (affine.empty() || inlierCount < requiredInliers) {
            throw std::runtime_error(
                "Kontrollpunkterna gav ingen stabil grov skala för polbilden."
            );
        }
        affine.convertTo(affine, CV_64F);
        const double a = affine.at<double>(0, 0);
        const double b = affine.at<double>(0, 1);
        const double scale = std::hypot(a, b);
        if (scale < 0.40 || scale > 2.50) {
            throw std::runtime_error(
                "Kontrollpunkterna gav en orimlig grov skala för polbilden."
            );
        }
        registration->h00 = a;
        registration->h01 = b;
        registration->h02 = affine.at<double>(0, 2);
        registration->h10 = affine.at<double>(1, 0);
        registration->h11 = affine.at<double>(1, 1);
        registration->h12 = affine.at<double>(1, 2);
        registration->h20 = 0;
        registration->h21 = 0;
        registration->h22 = 1;
        registration->matchedFeatureCount = inlierCount;
        registration->localViewFieldOfView = repairLocalViewFieldOfView;
        if (errors != nullptr) {
            cv::Mat homography = cv::Mat::eye(3, 3, CV_64F);
            affine.copyTo(homography(cv::Rect(0, 0, 3, 2)));
            std::vector<cv::Point2f> projected;
            cv::perspectiveTransform(repairPoints, projected, homography);
            for (int index = 0; index < controlPointCount; ++index) {
                errors[index] = cv::norm(projected[index] - basePoints[index]);
            }
        }
        *errorMessage = nullptr;
        return 1;
    } catch (const std::exception &error) {
        if (errorMessage != nullptr) *errorMessage = copiedString(error.what());
        return 0;
    }
}

int PWRegisterNadirRepair(
    const char *panoramaPath,
    const char *repairImagePath,
    const char *repairExclusionMaskPath,
    double horizontalFieldOfView,
    double polePitchDegrees,
    const char *overlayOutputPath,
    PWNadirRegistration *registration,
    char **errorMessage
) {
    try {
        if (
            panoramaPath == nullptr
            || repairImagePath == nullptr
            || overlayOutputPath == nullptr
            || registration == nullptr
            || errorMessage == nullptr
        ) {
            throw std::runtime_error(
                "Underlaget för nadirregistreringen är ofullständigt."
            );
        }
        cv::setNumThreads(1);
        cv::setRNGSeed(0);

        const cv::Mat panorama = cv::imread(
            panoramaPath,
            cv::IMREAD_COLOR
        );
        const cv::Mat repairSource = cv::imread(
            repairImagePath,
            cv::IMREAD_COLOR
        );
        if (panorama.empty()) {
            throw std::runtime_error(
                "Det färdiga panoramat kunde inte läsas."
            );
        }
        if (repairSource.empty()) {
            throw std::runtime_error(
                "Nadirbilden kunde inte läsas."
            );
        }

        cv::Mat panoramaMapX;
        cv::Mat panoramaMapY;
        makeNadirLocalPanoramaMap(
            panorama.size(),
            polePitchDegrees,
            panoramaMapX,
            panoramaMapY
        );
        cv::Mat baseLocal;
        cv::remap(
            panorama,
            baseLocal,
            panoramaMapX,
            panoramaMapY,
            cv::INTER_LINEAR,
            cv::BORDER_WRAP
        );
        cv::Mat baseMask(
            repairLocalViewSize,
            repairLocalViewSize,
            CV_8U,
            cv::Scalar(255)
        );

        cv::Mat repairMapX;
        cv::Mat repairMapY;
        cv::Mat repairMask;
        makeRepairLocalMap(
            repairSource.size(),
            horizontalFieldOfView,
            repairMapX,
            repairMapY,
            repairMask
        );
        cv::Mat repairLocal;
        cv::remap(
            repairSource,
            repairLocal,
            repairMapX,
            repairMapY,
            cv::INTER_LINEAR,
            cv::BORDER_CONSTANT,
            cv::Scalar(0, 0, 0)
        );

        int inlierCount = 0;
        const cv::Mat homography = registerRepairHomography(
            baseLocal,
            baseMask,
            repairLocal,
            repairMask,
            inlierCount
        );
        const cv::Mat outputMask = repairOutputMask(
            repairMask,
            repairMapX,
            repairMapY,
            repairSource.size(),
            repairExclusionMaskPath
        );
        writeNadirOverlay(
            repairLocal,
            outputMask,
            homography,
            overlayOutputPath
        );

        registration->h00 = homography.at<double>(0, 0);
        registration->h01 = homography.at<double>(0, 1);
        registration->h02 = homography.at<double>(0, 2);
        registration->h10 = homography.at<double>(1, 0);
        registration->h11 = homography.at<double>(1, 1);
        registration->h12 = homography.at<double>(1, 2);
        registration->h20 = homography.at<double>(2, 0);
        registration->h21 = homography.at<double>(2, 1);
        registration->h22 = homography.at<double>(2, 2);
        registration->matchedFeatureCount = inlierCount;
        registration->localViewFieldOfView =
            repairLocalViewFieldOfView;
        *errorMessage = nullptr;
        return 1;
    } catch (const std::exception &error) {
        if (errorMessage != nullptr) {
            *errorMessage = copiedString(error.what());
        }
        return 0;
    }
}

int PWAlignNadirRepairToProjectedOverlay(
    const char *projectedOverlayPath,
    const char *repairImagePath,
    const char *repairExclusionMaskPath,
    double horizontalFieldOfView,
    PWNadirRegistration *registration,
    char **errorMessage
) {
    try {
        if (projectedOverlayPath == nullptr
            || repairImagePath == nullptr
            || registration == nullptr
            || errorMessage == nullptr) {
            throw std::runtime_error(
                "Underlaget för den sfäriska polregistreringen är ofullständigt."
            );
        }
        cv::setNumThreads(1);
        cv::setRNGSeed(0);

        const cv::Mat projected = cv::imread(
            projectedOverlayPath,
            cv::IMREAD_UNCHANGED
        );
        const cv::Mat repairSource = cv::imread(
            repairImagePath,
            cv::IMREAD_COLOR
        );
        if (projected.empty()
            || projected.cols != repairLocalViewSize
            || projected.rows != repairLocalViewSize) {
            throw std::runtime_error(
                "Hugins sfäriska pollager kunde inte läsas."
            );
        }
        if (repairSource.empty()) {
            throw std::runtime_error("Polbilden kunde inte läsas.");
        }

        cv::Mat projectedColor;
        cv::Mat projectedMask(
            projected.size(),
            CV_8U,
            cv::Scalar(255)
        );
        if (projected.channels() == 4) {
            std::vector<cv::Mat> channels;
            cv::split(projected, channels);
            cv::cvtColor(projected, projectedColor, cv::COLOR_BGRA2BGR);
            cv::compare(channels[3], 8, projectedMask, cv::CMP_GT);
        } else if (projected.channels() == 3) {
            projectedColor = projected;
        } else {
            throw std::runtime_error(
                "Hugins sfäriska pollager har okänt pixelformat."
            );
        }

        cv::Mat repairMapX;
        cv::Mat repairMapY;
        cv::Mat repairProjectionMask;
        makeRepairLocalMap(
            repairSource.size(),
            horizontalFieldOfView,
            repairMapX,
            repairMapY,
            repairProjectionMask
        );
        cv::Mat repairLocal;
        cv::remap(
            repairSource,
            repairLocal,
            repairMapX,
            repairMapY,
            cv::INTER_LINEAR,
            cv::BORDER_CONSTANT,
            cv::Scalar(0, 0, 0)
        );
        const cv::Mat repairMask = repairOutputMask(
            repairProjectionMask,
            repairMapX,
            repairMapY,
            repairSource.size(),
            repairExclusionMaskPath
        );

        int inlierCount = 0;
        const cv::Mat homography = registerRepairHomography(
            projectedColor,
            projectedMask,
            repairLocal,
            repairMask,
            inlierCount
        );
        registration->h00 = homography.at<double>(0, 0);
        registration->h01 = homography.at<double>(0, 1);
        registration->h02 = homography.at<double>(0, 2);
        registration->h10 = homography.at<double>(1, 0);
        registration->h11 = homography.at<double>(1, 1);
        registration->h12 = homography.at<double>(1, 2);
        registration->h20 = homography.at<double>(2, 0);
        registration->h21 = homography.at<double>(2, 1);
        registration->h22 = homography.at<double>(2, 2);
        registration->matchedFeatureCount = inlierCount;
        registration->localViewFieldOfView = repairLocalViewFieldOfView;
        *errorMessage = nullptr;
        return 1;
    } catch (const std::exception &error) {
        if (errorMessage != nullptr) {
            *errorMessage = copiedString(error.what());
        }
        return 0;
    }
}

int PWExtractPoleOverlay(
    const char *equirectangularLayerPath,
    double polePitchDegrees,
    const char *overlayOutputPath,
    char **errorMessage
) {
    try {
        if (equirectangularLayerPath == nullptr || overlayOutputPath == nullptr
            || errorMessage == nullptr) {
            throw std::runtime_error("Underlaget för polprojektionen saknas.");
        }
        const cv::Mat layer = cv::imread(
            equirectangularLayerPath, cv::IMREAD_UNCHANGED
        );
        if (layer.empty()) {
            throw std::runtime_error("Hugins polbildlager kunde inte läsas.");
        }
        cv::Mat mapX, mapY;
        makeNadirLocalPanoramaMap(
            layer.size(), polePitchDegrees, mapX, mapY
        );
        cv::Mat local;
        cv::remap(
            layer, local, mapX, mapY,
            cv::INTER_LINEAR, cv::BORDER_WRAP
        );
        if (!cv::imwrite(overlayOutputPath, local)) {
            throw std::runtime_error("Det sfäriska pollagret kunde inte sparas.");
        }
        *errorMessage = nullptr;
        return 1;
    } catch (const std::exception &error) {
        if (errorMessage != nullptr) *errorMessage = copiedString(error.what());
        return 0;
    }
}

int PWWarpPoleOverlay(
    const char *sourceOverlayPath,
    const PWNadirRegistration *registration,
    const char *outputOverlayPath,
    char **errorMessage
) {
    try {
        if (sourceOverlayPath == nullptr || registration == nullptr
            || outputOverlayPath == nullptr || errorMessage == nullptr) {
            throw std::runtime_error("Underlaget för perspektivjusteringen saknas.");
        }
        const cv::Mat source = cv::imread(
            sourceOverlayPath,
            cv::IMREAD_UNCHANGED
        );
        if (source.empty()) {
            throw std::runtime_error("Polbildens sfäriska lager kunde inte läsas.");
        }
        cv::Mat transformed;
        cv::warpPerspective(
            source,
            transformed,
            registrationHomography(*registration),
            source.size(),
            cv::INTER_LINEAR,
            cv::BORDER_CONSTANT,
            cv::Scalar(0, 0, 0, 0)
        );
        if (!cv::imwrite(outputOverlayPath, transformed)) {
            throw std::runtime_error("Den perspektivjusterade polbilden kunde inte sparas.");
        }
        *errorMessage = nullptr;
        return 1;
    } catch (const std::exception &error) {
        if (errorMessage != nullptr) *errorMessage = copiedString(error.what());
        return 0;
    }
}

int PWRenderNadirRepairOverlay(
    const char *repairImagePath,
    const char *repairExclusionMaskPath,
    double horizontalFieldOfView,
    const PWNadirRegistration *registration,
    const char *overlayOutputPath,
    char **errorMessage
) {
    try {
        if (
            repairImagePath == nullptr
            || registration == nullptr
            || overlayOutputPath == nullptr
            || errorMessage == nullptr
        ) {
            throw std::runtime_error(
                "Underlaget för nadirlagret är ofullständigt."
            );
        }

        const cv::Mat repairSource = cv::imread(
            repairImagePath,
            cv::IMREAD_COLOR
        );
        if (repairSource.empty()) {
            throw std::runtime_error(
                "Nadirbilden kunde inte läsas."
            );
        }

        cv::Mat repairMapX;
        cv::Mat repairMapY;
        cv::Mat repairMask;
        makeRepairLocalMap(
            repairSource.size(),
            horizontalFieldOfView,
            repairMapX,
            repairMapY,
            repairMask
        );
        cv::Mat repairLocal;
        cv::remap(
            repairSource,
            repairLocal,
            repairMapX,
            repairMapY,
            cv::INTER_LINEAR,
            cv::BORDER_CONSTANT,
            cv::Scalar(0, 0, 0)
        );
        const cv::Mat outputMask = repairOutputMask(
            repairMask,
            repairMapX,
            repairMapY,
            repairSource.size(),
            repairExclusionMaskPath
        );
        const double homographyValues[] = {
            registration->h00,
            registration->h01,
            registration->h02,
            registration->h10,
            registration->h11,
            registration->h12,
            registration->h20,
            registration->h21,
            registration->h22
        };
        cv::Mat homography(3, 3, CV_64F);
        std::memcpy(
            homography.ptr<double>(),
            homographyValues,
            sizeof(homographyValues)
        );
        writeNadirOverlay(
            repairLocal,
            outputMask,
            homography,
            overlayOutputPath
        );
        *errorMessage = nullptr;
        return 1;
    } catch (const std::exception &error) {
        if (errorMessage != nullptr) {
            *errorMessage = copiedString(error.what());
        }
        return 0;
    }
}

int PWPrepareNadirRepairBlend(
    const char *panoramaPath,
    const char *repairImagePath,
    const char *repairExclusionMaskPath,
    const char *projectedRepairPath,
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
) {
    try {
        if (
            panoramaPath == nullptr
            || repairImagePath == nullptr
            || registration == nullptr
            || baseOutputPath == nullptr
            || repairOutputPath == nullptr
            || errorMessage == nullptr
        ) {
            throw std::runtime_error(
                "Underlaget för lokal Enblend-blandning är ofullständigt."
            );
        }
        if (scale <= 0.0) {
            throw std::runtime_error(
                "Nadirreparationens skala måste vara större än noll."
            );
        }

        const cv::Mat panorama = cv::imread(
            panoramaPath,
            cv::IMREAD_COLOR
        );
        if (panorama.empty()) {
            throw std::runtime_error(
                "Det färdiga panoramat kunde inte läsas."
            );
        }
        cv::Mat panoramaMapX;
        cv::Mat panoramaMapY;
        makeNadirLocalPanoramaMap(
            panorama.size(),
            polePitchDegrees,
            panoramaMapX,
            panoramaMapY
        );
        cv::Mat baseLocal;
        cv::remap(
            panorama,
            baseLocal,
            panoramaMapX,
            panoramaMapY,
            cv::INTER_LINEAR,
            cv::BORDER_WRAP
        );

        cv::Mat repairLocal;
        cv::Mat repairMask;
        cv::Mat repairHomography;
        if (projectedRepairPath != nullptr
            && std::strlen(projectedRepairPath) > 0) {
            const cv::Mat projectedRepair = cv::imread(
                projectedRepairPath,
                cv::IMREAD_UNCHANGED
            );
            if (projectedRepair.empty()
                || projectedRepair.cols != repairLocalViewSize
                || projectedRepair.rows != repairLocalViewSize) {
                throw std::runtime_error(
                    "Hugins sfäriska pollager kunde inte läsas."
                );
            }
            if (projectedRepair.channels() == 4) {
                std::vector<cv::Mat> channels;
                cv::split(projectedRepair, channels);
                repairMask = channels[3];
                cv::cvtColor(
                    projectedRepair,
                    repairLocal,
                    cv::COLOR_BGRA2BGR
                );
            } else if (projectedRepair.channels() == 3) {
                repairLocal = projectedRepair;
                repairMask = cv::Mat(
                    projectedRepair.size(),
                    CV_8U,
                    cv::Scalar(255)
                );
            } else {
                throw std::runtime_error(
                    "Hugins sfäriska pollager har ett okänt pixelformat."
                );
            }
            repairHomography = cv::Mat::eye(3, 3, CV_64F);
        } else {
            const cv::Mat repairSource = cv::imread(
                repairImagePath,
                cv::IMREAD_COLOR
            );
            if (repairSource.empty()) {
                throw std::runtime_error(
                    "Nadirbilden kunde inte läsas."
                );
            }
            cv::Mat repairMapX;
            cv::Mat repairMapY;
            makeRepairLocalMap(
                repairSource.size(),
                horizontalFieldOfView,
                repairMapX,
                repairMapY,
                repairMask
            );
            cv::remap(
                repairSource,
                repairLocal,
                repairMapX,
                repairMapY,
                cv::INTER_LINEAR,
                cv::BORDER_CONSTANT,
                cv::Scalar(0, 0, 0)
            );
            repairMask = repairOutputMask(
                repairMask,
                repairMapX,
                repairMapY,
                repairSource.size(),
                repairExclusionMaskPath
            );
            repairHomography = registrationHomography(*registration);
        }
        bool hasManualGeometry = std::abs(translationX) > 1e-6
            || std::abs(translationY) > 1e-6
            || std::abs(rotationDegrees) > 1e-6
            || std::abs(scale - 1.0) > 1e-6;
        if (cornerOffsets != nullptr) {
            for (int index = 0; index < 8; ++index) {
                hasManualGeometry = hasManualGeometry
                    || std::abs(cornerOffsets[index]) > 1e-6;
            }
        }
        writeNadirBlendInputs(
            baseLocal,
            repairLocal,
            repairMask,
            repairHomography,
            !hasManualGeometry,
            translationX,
            translationY,
            rotationDegrees,
            scale,
            cornerOffsets,
            contentBounds,
            baseOutputPath,
            repairOutputPath
        );

        *errorMessage = nullptr;
        return 1;
    } catch (const std::exception &error) {
        if (errorMessage != nullptr) {
            *errorMessage = copiedString(error.what());
        }
        return 0;
    }
}

int PWFinishNadirRepairBlend(
    const char *blendedLocalPath,
    const char *repairLayerPath,
    const char *repairSeamMaskPath,
    const char *overlayOutputPath,
    char **errorMessage
) {
    try {
        if (
            blendedLocalPath == nullptr
            || repairLayerPath == nullptr
            || repairSeamMaskPath == nullptr
            || overlayOutputPath == nullptr
            || errorMessage == nullptr
        ) {
            throw std::runtime_error(
                "Enblends lokala nadirresultat är ofullständigt."
            );
        }
        const cv::Mat blendedLocal = cv::imread(
            blendedLocalPath,
            cv::IMREAD_UNCHANGED
        );
        if (blendedLocal.empty()) {
            throw std::runtime_error(
                "Enblends lokala nadirresultat kunde inte läsas."
            );
        }
        const cv::Mat repairLayer = cv::imread(
            repairLayerPath,
            cv::IMREAD_UNCHANGED
        );
        if (repairLayer.empty()) {
            throw std::runtime_error(
                "Enblends reparationslager kunde inte läsas."
            );
        }
        const cv::Mat repairSeamMask = cv::imread(
            repairSeamMaskPath,
            cv::IMREAD_UNCHANGED
        );
        if (repairSeamMask.empty()) {
            throw std::runtime_error(
                "Enblends sömmask för reparationsbilden kunde inte läsas."
            );
        }
        writeBlendedNadirOverlay(
            blendedLocal,
            repairLayer,
            repairSeamMask,
            overlayOutputPath
        );
        *errorMessage = nullptr;
        return 1;
    } catch (const std::exception &error) {
        if (errorMessage != nullptr) {
            *errorMessage = copiedString(error.what());
        }
        return 0;
    }
}

int PWWarpFisheyeFactor(
    const char *sourcePath,
    const char *destinationPath,
    double sourceFactor,
    double destinationFactor,
    char **errorMessage
) {
    try {
        if (sourcePath == nullptr || destinationPath == nullptr
            || errorMessage == nullptr || sourceFactor >= 0
            || destinationFactor >= 0) {
            throw std::runtime_error("Ogiltig fisheye-faktor.");
        }
        const cv::Mat source = cv::imread(sourcePath, cv::IMREAD_UNCHANGED);
        if (source.empty()) {
            throw std::runtime_error("Fisheye-bilden kunde inte läsas.");
        }
        cv::Mat mapX(source.rows, source.cols, CV_32F);
        cv::Mat mapY(source.rows, source.cols, CV_32F);
        const double cx = (source.cols - 1) * 0.5;
        const double cy = (source.rows - 1) * 0.5;
        const double radius = std::max(source.cols, source.rows) * 0.4787;
        const double sourceEdge = std::sin(sourceFactor * M_PI_2);
        const double destinationEdge = std::sin(destinationFactor * M_PI_2);
        for (int y = 0; y < source.rows; ++y) {
            float *mx = mapX.ptr<float>(y);
            float *my = mapY.ptr<float>(y);
            for (int x = 0; x < source.cols; ++x) {
                const double dx = x - cx;
                const double dy = y - cy;
                const double destinationRadius = std::hypot(dx, dy);
                const double q = destinationRadius / radius;
                if (q > 1.0) {
                    mx[x] = -1;
                    my[x] = -1;
                    continue;
                }
                const double theta = std::asin(
                    std::clamp(q * destinationEdge, -1.0, 1.0)
                ) / destinationFactor;
                const double sourceRadius = radius
                    * std::sin(sourceFactor * theta) / sourceEdge;
                const double scale = destinationRadius > 1e-9
                    ? sourceRadius / destinationRadius : 1.0;
                mx[x] = static_cast<float>(cx + dx * scale);
                my[x] = static_cast<float>(cy + dy * scale);
            }
        }
        cv::Mat result;
        cv::remap(
            source, result, mapX, mapY, cv::INTER_LANCZOS4,
            cv::BORDER_CONSTANT, cv::Scalar::all(0)
        );
        if (!cv::imwrite(destinationPath, result)) {
            throw std::runtime_error("Fisheye-bilden kunde inte sparas.");
        }
        *errorMessage = nullptr;
        return 1;
    } catch (const std::exception &error) {
        if (errorMessage != nullptr) {
            *errorMessage = copiedString(error.what());
        }
        return 0;
    }
}

void PWFreeControlPoints(PWControlPoint *controlPoints) {
    std::free(controlPoints);
}

void PWFreeControlPointPairDiagnostics(
    PWControlPointPairDiagnostic *diagnostics
) {
    std::free(diagnostics);
}

void PWFreeString(char *string) {
    std::free(string);
}
