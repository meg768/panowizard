#include "OpenCVBridge.h"

#include <opencv2/calib3d.hpp>
#include <opencv2/features2d.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/stitching/detail/seam_finders.hpp>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <limits>
#include <numeric>
#include <random>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace {

constexpr double trialPi = 3.14159265358979323846;
constexpr int trialCacheVersion = 4;

struct TrialLens {
    double k1 = trialPi / 2.0;
    double k3 = 0.0;
    double k5 = 0.0;
    double cx = 0.0;
    double cy = 0.0;
    double aspect = 0.0;
};

struct TrialSource {
    cv::Mat image;
    cv::Mat userMask;
    cv::Mat protectedMask;
};

struct TrialFeatures {
    std::vector<cv::Point2d> points;
    cv::Mat descriptors;
    std::vector<float> distantDuplicateDistance;
};

struct TrialEdge {
    int first = 0;
    int second = 0;
    cv::Matx33d relative = cv::Matx33d::eye();
    std::vector<cv::Point2d> firstPoints;
    std::vector<cv::Point2d> secondPoints;
};

struct TrialEdgeSets {
    std::vector<TrialEdge> strong;
    std::vector<TrialEdge> weak;
};

struct TrialGeometryStats {
    int observations = 0;
    double medianDegrees = 0.0;
    double rmsDegrees = 0.0;
};

struct TrialAlignment {
    std::vector<cv::Matx33d> rotations;
    TrialLens lens;
    cv::Mat gains;
    TrialGeometryStats stats;
};

struct TrialWarp {
    cv::Mat image;
    cv::Mat mask;
    cv::Mat protectedMask;
    cv::Mat score;
    bool fillOnly = false;
};

struct TrialCallbacks {
    void *context = nullptr;
    PWTrialProgressCallback progress = nullptr;
    PWTrialCancellationCallback cancellation = nullptr;
};

thread_local TrialCallbacks trialCallbacks;

void trialCheckCancellation() {
    if (trialCallbacks.cancellation != nullptr
        && trialCallbacks.cancellation(trialCallbacks.context) != 0) {
        throw std::runtime_error("Panoramabygget avbröts.");
    }
}

void trialReport(const char *stage, double fraction) {
    trialCheckCancellation();
    if (trialCallbacks.progress != nullptr) {
        trialCallbacks.progress(
            trialCallbacks.context,
            stage,
            std::clamp(fraction, 0.0, 1.0)
        );
    }
}

double trialRadians(double degrees) {
    return degrees * trialPi / 180.0;
}

void trialSetError(char **errorMessage, const std::string &message) {
    if (errorMessage == nullptr) {
        return;
    }
    *errorMessage = static_cast<char *>(std::malloc(message.size() + 1));
    if (*errorMessage != nullptr) {
        std::memcpy(*errorMessage, message.c_str(), message.size() + 1);
    }
}

cv::Vec3d trialRay(
    const cv::Point2d &point,
    const cv::Size &size,
    const TrialLens &lens
) {
    const double scale = std::hypot(size.width, size.height) / 2.0;
    const double x = (point.x - lens.cx) / scale;
    const double y = (point.y - lens.cy) / scale * (1.0 + lens.aspect);
    const double radius = std::hypot(x, y);
    const double theta =
        lens.k1 * radius
        + lens.k3 * radius * radius * radius
        + lens.k5 * std::pow(radius, 5.0);
    const double factor = radius > 1e-10 ? std::sin(theta) / radius : 1.0;
    cv::Vec3d result(x * factor, y * factor, std::cos(theta));
    return result / cv::norm(result);
}

cv::Matx33d trialKabsch(
    const std::vector<cv::Vec3d> &source,
    const std::vector<cv::Vec3d> &target,
    const std::vector<int> &indices
) {
    cv::Matx33d covariance = cv::Matx33d::zeros();
    for (const int index : indices) {
        const cv::Vec3d &a = source[index];
        const cv::Vec3d &b = target[index];
        for (int row = 0; row < 3; ++row) {
            for (int column = 0; column < 3; ++column) {
                covariance(row, column) += a[row] * b[column];
            }
        }
    }
    cv::SVD decomposition(cv::Mat(covariance), cv::SVD::FULL_UV);
    cv::Mat rotation = decomposition.vt.t() * decomposition.u.t();
    if (cv::determinant(rotation) < 0.0) {
        decomposition.vt.row(2) *= -1.0;
        rotation = decomposition.vt.t() * decomposition.u.t();
    }
    cv::Matx33d result;
    for (int row = 0; row < 3; ++row) {
        for (int column = 0; column < 3; ++column) {
            result(row, column) = rotation.at<double>(row, column);
        }
    }
    return result;
}

std::pair<cv::Matx33d, std::vector<unsigned char>> trialRansacRotation(
    const std::vector<cv::Vec3d> &source,
    const std::vector<cv::Vec3d> &target
) {
    if (source.size() < 3 || source.size() != target.size()) {
        return {cv::Matx33d::eye(), {}};
    }
    std::mt19937 generator(20260902u + static_cast<unsigned>(source.size()));
    std::uniform_int_distribution<int> distribution(0, int(source.size()) - 1);
    std::vector<unsigned char> best(source.size(), 0);
    const int iterations = std::min(1800, std::max(500, int(source.size()) * 3));
    for (int iteration = 0; iteration < iterations; ++iteration) {
        if (iteration % 64 == 0) trialCheckCancellation();
        std::vector<int> selected;
        while (selected.size() < 3) {
            const int index = distribution(generator);
            if (std::find(selected.begin(), selected.end(), index) == selected.end()) {
                selected.push_back(index);
            }
        }
        const cv::Matx33d matrix = trialKabsch(source, target, selected);
        std::vector<unsigned char> hit(source.size(), 0);
        int hitCount = 0;
        for (size_t index = 0; index < source.size(); ++index) {
            const double cosine = std::clamp(
                (matrix * source[index]).dot(target[index]), -1.0, 1.0
            );
            if (std::acos(cosine) < trialRadians(1.4)) {
                hit[index] = 1;
                ++hitCount;
            }
        }
        if (hitCount > std::accumulate(best.begin(), best.end(), 0)) {
            best = std::move(hit);
        }
    }
    cv::Matx33d matrix = cv::Matx33d::eye();
    for (const double degrees : {1.15, 0.85, 0.62}) {
        std::vector<int> selected;
        for (size_t index = 0; index < best.size(); ++index) {
            if (best[index]) selected.push_back(int(index));
        }
        matrix = trialKabsch(source, target, selected);
        std::vector<unsigned char> hit(source.size(), 0);
        int hitCount = 0;
        for (size_t index = 0; index < source.size(); ++index) {
            const double cosine = std::clamp(
                (matrix * source[index]).dot(target[index]), -1.0, 1.0
            );
            if (std::acos(cosine) < trialRadians(degrees)) {
                hit[index] = 1;
                ++hitCount;
            }
        }
        if (hitCount >= 20) best = std::move(hit);
    }
    std::vector<int> selected;
    for (size_t index = 0; index < best.size(); ++index) {
        if (best[index]) selected.push_back(int(index));
    }
    return {trialKabsch(source, target, selected), best};
}

TrialSource trialReadSource(const char *imagePath, const char *protectedPath) {
    cv::Mat raw = cv::imread(imagePath, cv::IMREAD_UNCHANGED);
    if (raw.empty()) {
        throw std::runtime_error("Källbilden kunde inte läsas: " + std::string(imagePath));
    }
    TrialSource result;
    if (raw.channels() == 4) {
        std::vector<cv::Mat> channels;
        cv::split(raw, channels);
        result.userMask = channels[3] > 0;
        cv::cvtColor(raw, result.image, cv::COLOR_BGRA2BGR);
    } else if (raw.channels() == 3) {
        result.image = raw;
        result.userMask = cv::Mat(raw.size(), CV_8U, cv::Scalar(255));
    } else {
        cv::cvtColor(raw, result.image, cv::COLOR_GRAY2BGR);
        result.userMask = cv::Mat(raw.size(), CV_8U, cv::Scalar(255));
    }
    result.protectedMask = cv::Mat(raw.size(), CV_8U, cv::Scalar(0));
    if (protectedPath != nullptr && protectedPath[0] != '\0') {
        cv::Mat protectedImage = cv::imread(protectedPath, cv::IMREAD_UNCHANGED);
        if (protectedImage.empty()) {
            throw std::runtime_error("En skyddsmask kunde inte läsas.");
        }
        if (protectedImage.size() != raw.size()) {
            cv::resize(
                protectedImage, protectedImage, raw.size(), 0.0, 0.0,
                cv::INTER_NEAREST
            );
        }
        if (protectedImage.channels() == 4) {
            std::vector<cv::Mat> channels;
            cv::split(protectedImage, channels);
            result.protectedMask = channels[3] > 0;
        } else if (protectedImage.channels() == 3) {
            cv::cvtColor(protectedImage, result.protectedMask, cv::COLOR_BGR2GRAY);
            result.protectedMask = result.protectedMask > 0;
        } else {
            result.protectedMask = protectedImage > 0;
        }
        cv::bitwise_and(result.protectedMask, result.userMask, result.protectedMask);
    }
    return result;
}

struct TrialOpticalSupport {
    cv::Mat mask;
    bool circular = false;
    double radius = 0.0;
};

TrialOpticalSupport trialCommonValidMask(const std::vector<TrialSource> &sources) {
    const cv::Size size = sources.front().image.size();
    cv::Mat maximum(size, CV_8U, cv::Scalar(0));
    for (const TrialSource &source : sources) {
        cv::Mat channelMaximum;
        std::vector<cv::Mat> channels;
        cv::split(source.image, channels);
        cv::max(channels[0], channels[1], channelMaximum);
        cv::max(channelMaximum, channels[2], channelMaximum);
        cv::max(maximum, channelMaximum, maximum);
    }
    cv::Mat candidate = maximum > 7;
    int kernelSize = std::max(7, std::min(size.width, size.height) / 180);
    if (kernelSize % 2 == 0) ++kernelSize;
    cv::morphologyEx(
        candidate, candidate, cv::MORPH_CLOSE,
        cv::Mat::ones(kernelSize, kernelSize, CV_8U)
    );
    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(candidate, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
    if (contours.empty()) {
        return {
            cv::Mat(size, CV_8U, cv::Scalar(255)), false,
            std::hypot(size.width, size.height) / 2.0
        };
    }
    const auto contour = std::max_element(
        contours.begin(), contours.end(),
        [](const auto &left, const auto &right) {
            return cv::contourArea(left) < cv::contourArea(right);
        }
    );
    const double areaRatio = cv::contourArea(*contour) / double(size.area());
    const cv::Rect bounds = cv::boundingRect(*contour);
    const bool circleLike = areaRatio < 0.86
        && bounds.width > 0.78 * size.width
        && bounds.height > 0.45 * size.width;
    if (!circleLike) {
        return {
            cv::Mat(size, CV_8U, cv::Scalar(255)), false,
            std::hypot(size.width, size.height) / 2.0
        };
    }
    cv::Point2f center;
    float radius = 0.0f;
    cv::minEnclosingCircle(*contour, center, radius);
    cv::Mat mask(size, CV_8U, cv::Scalar(0));
    cv::circle(mask, center, std::max(1, int(std::round(radius - 3))), 255, -1);
    return {mask, true, radius};
}

std::vector<TrialFeatures> trialExtractFeatures(
    const std::vector<TrialSource> &sources,
    const cv::Mat &opticalMask
) {
    const cv::Size size = sources.front().image.size();
    const double factor = std::min(1.0, 1450.0 / std::max(size.width, size.height));
    cv::Ptr<cv::SIFT> sift = cv::SIFT::create(16000, 3, 0.016, 14);
    std::vector<TrialFeatures> result;
    for (const TrialSource &source : sources) {
        cv::Mat small;
        cv::resize(source.image, small, cv::Size(), factor, factor, cv::INTER_AREA);
        cv::Mat gray;
        cv::cvtColor(small, gray, cv::COLOR_BGR2GRAY);
        cv::Mat usable;
        cv::bitwise_and(opticalMask, source.userMask, usable);
        cv::resize(usable, usable, gray.size(), 0.0, 0.0, cv::INTER_NEAREST);
        std::vector<cv::KeyPoint> keypoints;
        cv::Mat descriptors;
        sift->detectAndCompute(gray, usable, keypoints, descriptors);
        if (descriptors.empty() || keypoints.size() < 20) {
            throw std::runtime_error("För få användbara bilddetaljer i en källbild.");
        }
        TrialFeatures features;
        features.descriptors = descriptors;
        features.points.reserve(keypoints.size());
        for (const cv::KeyPoint &keypoint : keypoints) {
            features.points.emplace_back(
                keypoint.pt.x / factor, keypoint.pt.y / factor
            );
        }
        // Lowe's ratio only measures ambiguity in the other image. A logo or
        // parasol repeated inside the same photograph can still look unique
        // across the pair and create a geometrically coherent false cluster.
        // Record the closest descriptor at a different physical location so
        // those self-ambiguous features can be rejected during cross-match.
        features.distantDuplicateDistance.assign(
            keypoints.size(), std::numeric_limits<float>::infinity()
        );
        cv::FlannBasedMatcher selfMatcher;
        std::vector<std::vector<cv::DMatch>> selfMatches;
        selfMatcher.knnMatch(descriptors, descriptors, selfMatches, 12);
        const double minimumSeparation = 0.08 * std::min(size.width, size.height);
        for (const auto &matches : selfMatches) {
            if (matches.empty()) continue;
            const int query = matches.front().queryIdx;
            for (const cv::DMatch &match : matches) {
                if (match.trainIdx == query) continue;
                if (cv::norm(
                        features.points[query] - features.points[match.trainIdx]
                    ) < minimumSeparation) {
                    continue;
                }
                features.distantDuplicateDistance[query] = match.distance;
                break;
            }
        }
        result.push_back(std::move(features));
    }
    return result;
}

std::vector<std::pair<int, int>> trialMutualMatches(
    const TrialFeatures &first,
    const TrialFeatures &second
) {
    cv::BFMatcher matcher(cv::NORM_L2);
    std::vector<std::vector<cv::DMatch>> forward;
    std::vector<std::vector<cv::DMatch>> reverse;
    matcher.knnMatch(first.descriptors, second.descriptors, forward, 2);
    matcher.knnMatch(second.descriptors, first.descriptors, reverse, 2);
    std::vector<int> one(first.descriptors.rows, -1);
    std::vector<int> two(second.descriptors.rows, -1);
    for (const auto &matches : forward) {
        if (matches.size() >= 2
            && matches[0].distance < 0.75f * matches[1].distance
            && matches[0].distance < 0.85f
                * first.distantDuplicateDistance[matches[0].queryIdx]
            && matches[0].distance < 0.85f
                * second.distantDuplicateDistance[matches[0].trainIdx]) {
            one[matches[0].queryIdx] = matches[0].trainIdx;
        }
    }
    for (const auto &matches : reverse) {
        if (matches.size() >= 2
            && matches[0].distance < 0.75f * matches[1].distance
            && matches[0].distance < 0.85f
                * second.distantDuplicateDistance[matches[0].queryIdx]
            && matches[0].distance < 0.85f
                * first.distantDuplicateDistance[matches[0].trainIdx]) {
            two[matches[0].queryIdx] = matches[0].trainIdx;
        }
    }
    std::vector<std::pair<int, int>> result;
    for (int index = 0; index < int(one.size()); ++index) {
        if (one[index] >= 0 && two[one[index]] == index) {
            result.emplace_back(index, one[index]);
        }
    }
    return result;
}

TrialEdgeSets trialBuildEdges(
    const std::vector<TrialSource> &sources,
    const std::vector<TrialFeatures> &features,
    const TrialLens &lens
) {
    TrialEdgeSets edges;
    for (int first = 0; first < int(sources.size()); ++first) {
        for (int second = first + 1; second < int(sources.size()); ++second) {
            const auto matches = trialMutualMatches(
                features[first], features[second]
            );
            if (matches.size() < 3) continue;
            std::vector<cv::Vec3d> firstRays;
            std::vector<cv::Vec3d> secondRays;
            firstRays.reserve(matches.size());
            secondRays.reserve(matches.size());
            for (const auto &[firstIndex, secondIndex] : matches) {
                firstRays.push_back(trialRay(
                    features[first].points[firstIndex], sources[first].image.size(), lens
                ));
                secondRays.push_back(trialRay(
                    features[second].points[secondIndex], sources[second].image.size(), lens
                ));
            }
            auto [rotation, hit] = trialRansacRotation(firstRays, secondRays);
            const int support = std::accumulate(hit.begin(), hit.end(), 0);
            if (support < 3) continue;
            TrialEdge edge;
            edge.first = first;
            edge.second = second;
            edge.relative = rotation;
            for (size_t index = 0; index < matches.size(); ++index) {
                if (!hit[index]) continue;
                edge.firstPoints.push_back(features[first].points[matches[index].first]);
                edge.secondPoints.push_back(features[second].points[matches[index].second]);
            }
            if (support >= 20 && matches.size() >= 25) {
                edges.strong.push_back(std::move(edge));
            } else if (support < 20) {
                edges.weak.push_back(std::move(edge));
            }
        }
    }
    return edges;
}

bool trialConnected(int count, const std::vector<TrialEdge> &edges) {
    std::vector<unsigned char> seen(count, 0);
    seen[0] = 1;
    bool changed = true;
    while (changed) {
        changed = false;
        for (const TrialEdge &edge : edges) {
            if (seen[edge.first] && !seen[edge.second]) {
                seen[edge.second] = 1;
                changed = true;
            }
            if (seen[edge.second] && !seen[edge.first]) {
                seen[edge.first] = 1;
                changed = true;
            }
        }
    }
    return std::all_of(seen.begin(), seen.end(), [](unsigned char value) {
        return value != 0;
    });
}

std::vector<TrialEdge> trialSubsetEdges(
    const std::vector<TrialEdge> &edges,
    const std::vector<int> &sourceIndices,
    int sourceCount
) {
    std::vector<int> subsetIndex(sourceCount, -1);
    for (int index = 0; index < int(sourceIndices.size()); ++index) {
        subsetIndex[sourceIndices[index]] = index;
    }
    std::vector<TrialEdge> result;
    for (const TrialEdge &edge : edges) {
        const int first = subsetIndex[edge.first];
        const int second = subsetIndex[edge.second];
        if (first < 0 || second < 0) continue;
        TrialEdge subset = edge;
        subset.first = first;
        subset.second = second;
        result.push_back(std::move(subset));
    }
    return result;
}

std::vector<cv::Matx33d> trialInitialRotations(
    int count,
    const std::vector<TrialEdge> &edges
) {
    std::vector<cv::Matx33d> matrices(count, cv::Matx33d::eye());
    std::vector<unsigned char> assigned(count, 0);
    assigned[0] = 1;
    int remaining = count - 1;
    while (remaining > 0) {
        int bestWeight = -1;
        int bestNode = -1;
        cv::Matx33d bestMatrix;
        for (const TrialEdge &edge : edges) {
            const int weight = int(edge.firstPoints.size());
            if (assigned[edge.first] && !assigned[edge.second] && weight > bestWeight) {
                bestWeight = weight;
                bestNode = edge.second;
                bestMatrix = matrices[edge.first] * edge.relative.t();
            }
            if (assigned[edge.second] && !assigned[edge.first] && weight > bestWeight) {
                bestWeight = weight;
                bestNode = edge.first;
                bestMatrix = matrices[edge.second] * edge.relative;
            }
        }
        if (bestNode < 0) {
            throw std::runtime_error("Bildgrafen är inte sammanhängande.");
        }
        matrices[bestNode] = bestMatrix;
        assigned[bestNode] = 1;
        --remaining;
    }
    return matrices;
}

cv::Vec3d trialRotationVector(const cv::Matx33d &matrix) {
    cv::Mat vector;
    cv::Rodrigues(cv::Mat(matrix), vector);
    return cv::Vec3d(vector.at<double>(0), vector.at<double>(1), vector.at<double>(2));
}

cv::Matx33d trialRotationMatrix(const cv::Vec3d &vector) {
    cv::Mat matrix;
    cv::Rodrigues(vector, matrix);
    cv::Matx33d result;
    for (int row = 0; row < 3; ++row) {
        for (int column = 0; column < 3; ++column) {
            result(row, column) = matrix.at<double>(row, column);
        }
    }
    return result;
}

struct TrialOptimizationSample {
    int first = 0;
    int second = 0;
    int rawRansacSupport = 0;
    std::vector<cv::Point2d> firstPoints;
    std::vector<cv::Point2d> secondPoints;
};

struct TrialStrongCycle {
    std::vector<int> nodes;
    std::vector<int> edges;
};

int trialMinimumEdgeSupport(int observationCount) {
    return std::min(18, std::max(10, (observationCount + 3) / 4));
}

int trialRequiredSampleSupport(int sampleCount) {
    if (sampleCount < 3) return 3;
    if (sampleCount < 10) return sampleCount;
    return trialMinimumEdgeSupport(sampleCount);
}

TrialOptimizationSample trialSpatialSample(
    const TrialEdge &edge,
    const cv::Size &size,
    std::mt19937 &generator
) {
    std::vector<int> indices(edge.firstPoints.size());
    std::iota(indices.begin(), indices.end(), 0);
    std::shuffle(indices.begin(), indices.end(), generator);
    // Optimisation support is spatial support, not raw detector density.
    // Without thinning, hundreds of SIFT points from one flower bed,
    // railing or repeated logo can outweigh an entire neighbouring image
    // pair and pull a steep view away from valid nearby structure.
    constexpr int gridColumns = 8;
    constexpr int gridRows = 12;
    constexpr int maximumPerEdge = 80;
    std::vector<int> firstUse(gridColumns * gridRows, 0);
    std::vector<int> secondUse(gridColumns * gridRows, 0);
    std::vector<unsigned char> chosen(indices.size(), 0);
    std::vector<int> distributed;
    distributed.reserve(std::min<int>(maximumPerEdge, int(indices.size())));
    for (int allowance = 1;
         allowance <= 3 && int(distributed.size()) < maximumPerEdge;
         ++allowance) {
        for (int shuffled = 0;
             shuffled < int(indices.size())
                && int(distributed.size()) < maximumPerEdge;
             ++shuffled) {
            if (chosen[shuffled]) continue;
            const int point = indices[shuffled];
            const cv::Point2d &firstPoint = edge.firstPoints[point];
            const cv::Point2d &secondPoint = edge.secondPoints[point];
            const int firstCell = std::clamp(
                int(firstPoint.y * gridRows / size.height), 0, gridRows - 1
            ) * gridColumns + std::clamp(
                int(firstPoint.x * gridColumns / size.width), 0, gridColumns - 1
            );
            const int secondCell = std::clamp(
                int(secondPoint.y * gridRows / size.height), 0, gridRows - 1
            ) * gridColumns + std::clamp(
                int(secondPoint.x * gridColumns / size.width), 0, gridColumns - 1
            );
            if (firstUse[firstCell] >= allowance
                || secondUse[secondCell] >= allowance) {
                continue;
            }
            ++firstUse[firstCell];
            ++secondUse[secondCell];
            chosen[shuffled] = 1;
            distributed.push_back(point);
        }
    }
    TrialOptimizationSample sample;
    sample.first = edge.first;
    sample.second = edge.second;
    sample.rawRansacSupport = int(edge.firstPoints.size());
    for (const int index : distributed) {
        sample.firstPoints.push_back(edge.firstPoints[index]);
        sample.secondPoints.push_back(edge.secondPoints[index]);
    }
    return sample;
}

bool trialHasRawRansacSupport(const TrialEdge &edge) {
    // Only the strong graph path uses this unchanged cutoff.
    return int(edge.firstPoints.size()) >= 20;
}

std::vector<int> trialInitialTreeEdges(
    int count,
    const std::vector<TrialEdge> &edges
) {
    std::vector<int> result;
    std::vector<unsigned char> assigned(count, 0);
    assigned[0] = 1;
    int remaining = count - 1;
    while (remaining > 0) {
        int bestWeight = -1;
        int bestNode = -1;
        int bestEdge = -1;
        for (int index = 0; index < int(edges.size()); ++index) {
            const TrialEdge &edge = edges[index];
            const int weight = int(edge.firstPoints.size());
            if (assigned[edge.first] && !assigned[edge.second]
                && weight > bestWeight) {
                bestWeight = weight;
                bestNode = edge.second;
                bestEdge = index;
            }
            if (assigned[edge.second] && !assigned[edge.first]
                && weight > bestWeight) {
                bestWeight = weight;
                bestNode = edge.first;
                bestEdge = index;
            }
        }
        if (bestNode < 0) {
            throw std::runtime_error("Bildgrafen är inte sammanhängande.");
        }
        assigned[bestNode] = 1;
        result.push_back(bestEdge);
        --remaining;
    }
    return result;
}

bool trialFindBrokenStrongCycle(
    int count,
    const std::vector<TrialEdge> &edges,
    const std::vector<TrialOptimizationSample> &samples,
    const std::vector<std::vector<unsigned char>> &keep,
    TrialStrongCycle &result
) {
    const std::vector<int> treeEdges = trialInitialTreeEdges(count, edges);
    std::vector<unsigned char> isTree(edges.size(), 0);
    std::vector<std::vector<std::pair<int, int>>> adjacency(count);
    for (const int edgeIndex : treeEdges) {
        isTree[edgeIndex] = 1;
        const TrialEdge &edge = edges[edgeIndex];
        if (!trialHasRawRansacSupport(edge)) continue;
        adjacency[edge.first].push_back({edge.second, edgeIndex});
        adjacency[edge.second].push_back({edge.first, edgeIndex});
    }

    for (int closingEdge = 0; closingEdge < int(edges.size()); ++closingEdge) {
        if (isTree[closingEdge]) continue;
        const TrialEdge &closing = edges[closingEdge];
        if (!trialHasRawRansacSupport(closing)) continue;
        std::vector<int> parent(count, -1);
        std::vector<int> parentEdge(count, -1);
        std::vector<int> pending = {closing.first};
        parent[closing.first] = closing.first;
        for (size_t offset = 0;
             offset < pending.size() && parent[closing.second] < 0;
             ++offset) {
            const int node = pending[offset];
            for (const auto &[neighbor, edgeIndex] : adjacency[node]) {
                if (parent[neighbor] >= 0) continue;
                parent[neighbor] = node;
                parentEdge[neighbor] = edgeIndex;
                pending.push_back(neighbor);
            }
        }
        if (parent[closing.second] < 0) continue;

        std::vector<int> reverseNodes = {closing.second};
        std::vector<int> reverseEdges;
        for (int node = closing.second; node != closing.first; node = parent[node]) {
            reverseEdges.push_back(parentEdge[node]);
            reverseNodes.push_back(parent[node]);
        }
        std::reverse(reverseNodes.begin(), reverseNodes.end());
        std::reverse(reverseEdges.begin(), reverseEdges.end());
        reverseEdges.push_back(closingEdge);

        bool survives = true;
        for (const int edgeIndex : reverseEdges) {
            const int kept = std::accumulate(
                keep[edgeIndex].begin(), keep[edgeIndex].end(), 0
            );
            const int sampleCount = int(samples[edgeIndex].firstPoints.size());
            if (kept < trialRequiredSampleSupport(sampleCount)) {
                survives = false;
                break;
            }
        }
        if (!survives) {
            result.nodes = std::move(reverseNodes);
            result.edges = std::move(reverseEdges);
            return true;
        }
    }
    return false;
}

std::vector<cv::Matx33d> trialClosedCycleRotations(
    const std::vector<cv::Matx33d> &treeRotations,
    const std::vector<TrialEdge> &edges,
    const TrialStrongCycle &cycle
) {
    std::vector<cv::Matx33d> result = treeRotations;
    const TrialEdge &closing = edges[cycle.edges.back()];
    const cv::Matx33d desiredEnd = result[closing.first] * closing.relative.t();
    const cv::Matx33d correction = desiredEnd * result[closing.second].t();
    const cv::Vec3d correctionVector = trialRotationVector(correction);
    for (int index = 0; index < int(cycle.nodes.size()); ++index) {
        const double fraction = double(index)
            / double(std::max(1, int(cycle.nodes.size()) - 1));
        result[cycle.nodes[index]] = trialRotationMatrix(
            correctionVector * fraction
        ) * treeRotations[cycle.nodes[index]];
    }

    std::vector<unsigned char> assigned(result.size(), 0);
    for (const int node : cycle.nodes) assigned[node] = 1;
    const std::vector<int> treeEdges = trialInitialTreeEdges(
        int(result.size()), edges
    );
    bool changed = true;
    while (changed) {
        changed = false;
        for (const int edgeIndex : treeEdges) {
            const TrialEdge &edge = edges[edgeIndex];
            if (assigned[edge.first] && !assigned[edge.second]) {
                result[edge.second] = result[edge.first] * edge.relative.t();
                assigned[edge.second] = 1;
                changed = true;
            } else if (assigned[edge.second] && !assigned[edge.first]) {
                result[edge.first] = result[edge.second] * edge.relative;
                assigned[edge.first] = 1;
                changed = true;
            }
        }
    }

    const cv::Matx33d gauge = result[0].t();
    for (cv::Matx33d &rotation : result) rotation = gauge * rotation;
    return result;
}

std::vector<double> trialPack(
    const std::vector<cv::Matx33d> &rotations,
    const TrialLens &lens
) {
    std::vector<double> values;
    for (size_t index = 1; index < rotations.size(); ++index) {
        const cv::Vec3d vector = trialRotationVector(rotations[index]);
        values.insert(values.end(), {vector[0], vector[1], vector[2]});
    }
    values.insert(values.end(), {
        lens.k1, lens.k3, lens.k5, lens.cx, lens.cy, lens.aspect
    });
    return values;
}

void trialUnpack(
    const std::vector<double> &values,
    int count,
    std::vector<cv::Matx33d> &rotations,
    TrialLens &lens
) {
    rotations.assign(count, cv::Matx33d::eye());
    for (int index = 1; index < count; ++index) {
        const int offset = 3 * (index - 1);
        rotations[index] = trialRotationMatrix(cv::Vec3d(
            values[offset], values[offset + 1], values[offset + 2]
        ));
    }
    const int offset = 3 * (count - 1);
    lens = {
        values[offset], values[offset + 1], values[offset + 2],
        values[offset + 3], values[offset + 4], values[offset + 5]
    };
}

std::vector<double> trialGeometryResiduals(
    const std::vector<double> &values,
    int count,
    const cv::Size &size,
    const std::vector<TrialOptimizationSample> &samples,
    const std::vector<std::vector<unsigned char>> *keep,
    double radialLimit
) {
    std::vector<cv::Matx33d> rotations;
    TrialLens lens;
    trialUnpack(values, count, rotations, lens);
    std::vector<double> result;
    for (size_t sampleIndex = 0; sampleIndex < samples.size(); ++sampleIndex) {
        const TrialOptimizationSample &sample = samples[sampleIndex];
        for (size_t pointIndex = 0; pointIndex < sample.firstPoints.size(); ++pointIndex) {
            if (keep != nullptr && !(*keep)[sampleIndex][pointIndex]) continue;
            const cv::Vec3d first = rotations[sample.first]
                * trialRay(sample.firstPoints[pointIndex], size, lens);
            const cv::Vec3d second = rotations[sample.second]
                * trialRay(sample.secondPoints[pointIndex], size, lens);
            const cv::Vec3d difference = first - second;
            result.insert(result.end(), {difference[0], difference[1], difference[2]});
        }
    }
    for (int index = 0; index < 12; ++index) {
        const double radius = radialLimit * index / 11.0;
        const double derivative = lens.k1
            + 3.0 * lens.k3 * radius * radius
            + 5.0 * lens.k5 * std::pow(radius, 4.0);
        result.push_back(std::min(derivative - 0.04, 0.0) * 2.0);
    }
    return result;
}

double trialRobustObjective(const std::vector<double> &residuals, double scale) {
    double result = 0.0;
    for (const double residual : residuals) {
        const double normalized = residual / scale;
        result += scale * scale * std::log1p(normalized * normalized);
    }
    return result;
}

std::vector<double> trialLeastSquares(
    std::vector<double> values,
    const std::vector<double> &lower,
    const std::vector<double> &upper,
    int count,
    const cv::Size &size,
    const std::vector<TrialOptimizationSample> &samples,
    const std::vector<std::vector<unsigned char>> *keep,
    double radialLimit,
    double robustScale,
    int iterations
) {
    double lambda = 1e-3;
    std::vector<double> residuals = trialGeometryResiduals(
        values, count, size, samples, keep, radialLimit
    );
    double objective = trialRobustObjective(residuals, robustScale);
    for (int iteration = 0; iteration < iterations; ++iteration) {
        trialCheckCancellation();
        const int rows = int(residuals.size());
        const int columns = int(values.size());
        cv::Mat jacobian(rows, columns, CV_64F);
        for (int column = 0; column < columns; ++column) {
            std::vector<double> shifted = values;
            const int lensOffset = 3 * (count - 1);
            const double epsilon = column >= lensOffset + 3 ? 0.05 : 1e-5;
            shifted[column] = shifted[column] + epsilon <= upper[column]
                ? shifted[column] + epsilon
                : std::max(lower[column], shifted[column] - epsilon);
            const double actualStep = shifted[column] - values[column];
            const std::vector<double> candidate = trialGeometryResiduals(
                shifted, count, size, samples, keep, radialLimit
            );
            for (int row = 0; row < rows; ++row) {
                jacobian.at<double>(row, column) =
                    (candidate[row] - residuals[row]) / actualStep;
            }
        }
        cv::Mat weightedResidual(rows, 1, CV_64F);
        cv::Mat weightedJacobian = jacobian.clone();
        for (int row = 0; row < rows; ++row) {
            const double normalized = residuals[row] / robustScale;
            const double weight = 1.0 / std::sqrt(1.0 + normalized * normalized);
            weightedResidual.at<double>(row) = residuals[row] * weight;
            weightedJacobian.row(row) *= weight;
        }
        cv::Mat normal = weightedJacobian.t() * weightedJacobian;
        cv::Mat gradient = weightedJacobian.t() * weightedResidual;
        for (int index = 0; index < columns; ++index) {
            normal.at<double>(index, index) += lambda
                * std::max(1e-8, normal.at<double>(index, index));
        }
        cv::Mat delta;
        if (!cv::solve(normal, -gradient, delta, cv::DECOMP_SVD)) break;
        std::vector<double> candidateValues = values;
        double stepNorm = 0.0;
        for (int index = 0; index < columns; ++index) {
            const double step = delta.at<double>(index);
            candidateValues[index] = std::clamp(
                values[index] + step, lower[index], upper[index]
            );
            stepNorm += step * step;
        }
        const std::vector<double> candidateResiduals = trialGeometryResiduals(
            candidateValues, count, size, samples, keep, radialLimit
        );
        const double candidateObjective = trialRobustObjective(
            candidateResiduals, robustScale
        );
        if (candidateObjective < objective) {
            values = std::move(candidateValues);
            residuals = candidateResiduals;
            objective = candidateObjective;
            lambda = std::max(1e-9, lambda * 0.35);
            if (stepNorm < 1e-14) break;
        } else {
            lambda = std::min(1e12, lambda * 8.0);
        }
    }
    return values;
}

double trialMedian(std::vector<double> values) {
    if (values.empty()) return 0.0;
    const size_t middle = values.size() / 2;
    std::nth_element(values.begin(), values.begin() + middle, values.end());
    if (values.size() % 2 == 1) return values[middle];
    const double high = values[middle];
    std::nth_element(values.begin(), values.begin() + middle - 1, values.end());
    return (values[middle - 1] + high) / 2.0;
}

std::vector<std::vector<unsigned char>> trialGeometryKeep(
    const std::vector<double> &values,
    int count,
    const cv::Size &size,
    const std::vector<TrialOptimizationSample> &samples
) {
    std::vector<cv::Matx33d> rotations;
    TrialLens lens;
    trialUnpack(values, count, rotations, lens);
    std::vector<std::vector<unsigned char>> keep;
    for (const TrialOptimizationSample &sample : samples) {
        std::vector<unsigned char> selected(sample.firstPoints.size(), 0);
        int selectedCount = 0;
        for (size_t index = 0; index < sample.firstPoints.size(); ++index) {
            const cv::Vec3d first = rotations[sample.first]
                * trialRay(sample.firstPoints[index], size, lens);
            const cv::Vec3d second = rotations[sample.second]
                * trialRay(sample.secondPoints[index], size, lens);
            if (std::acos(std::clamp(first.dot(second), -1.0, 1.0))
                    < trialRadians(1.20)) {
                selected[index] = 1;
                ++selectedCount;
            }
        }
        // An edge with too little support after the global fit is not rescued
        // by restoring all of its rejected matches. That previously allowed
        // a coherent false cluster on repeated subjects (logos, identical
        // parasols, windows) to re-enter the final optimization and steer an
        // entire source to the wrong physical instance.
        if (sample.rawRansacSupport < 20
            || selectedCount < trialRequiredSampleSupport(int(selected.size()))) {
            std::fill(selected.begin(), selected.end(), 0);
        }
        keep.push_back(std::move(selected));
    }
    return keep;
}

std::pair<int, double> trialValidationScore(
    const std::vector<double> &values,
    int count,
    const cv::Size &size,
    const std::vector<TrialOptimizationSample> &samples,
    double radialLimit
) {
    std::vector<cv::Matx33d> rotations;
    TrialLens lens;
    trialUnpack(values, count, rotations, lens);
    int explained = 0;
    for (const TrialOptimizationSample &sample : samples) {
        for (size_t index = 0; index < sample.firstPoints.size(); ++index) {
            const cv::Vec3d first = rotations[sample.first]
                * trialRay(sample.firstPoints[index], size, lens);
            const cv::Vec3d second = rotations[sample.second]
                * trialRay(sample.secondPoints[index], size, lens);
            if (std::acos(std::clamp(first.dot(second), -1.0, 1.0))
                    < trialRadians(1.20)) {
                ++explained;
            }
        }
    }
    const std::vector<double> residuals = trialGeometryResiduals(
        values, count, size, samples, nullptr, radialLimit
    );
    return {
        explained,
        trialRobustObjective(residuals, trialRadians(0.20))
    };
}

TrialAlignment trialOptimizeGeometry(
    const std::vector<TrialSource> &sources,
    const std::vector<TrialEdge> &edges,
    const std::vector<TrialEdge> &weakEdges,
    const std::vector<cv::Matx33d> &initialRotations,
    const TrialLens &initialLens,
    bool circular,
    double validRadius
) {
    const int count = int(sources.size());
    const cv::Size size = sources.front().image.size();
    std::mt19937 generator(20260902u);
    std::vector<TrialOptimizationSample> samples;
    for (const TrialEdge &edge : edges) {
        samples.push_back(trialSpatialSample(edge, size, generator));
    }
    std::vector<double> values = trialPack(initialRotations, initialLens);
    std::vector<double> lower = values;
    std::vector<double> upper = values;
    const int lensOffset = 3 * (count - 1);
    for (int index = 0; index < lensOffset; ++index) {
        lower[index] -= 0.55;
        upper[index] += 0.55;
    }
    const double centerRange = 0.035 * std::min(size.width, size.height);
    lower[lensOffset] = std::max(0.8, initialLens.k1 * 0.62);
    upper[lensOffset] = std::min(4.2, initialLens.k1 * 1.55);
    lower[lensOffset + 1] = lower[lensOffset + 2] = -2.0;
    upper[lensOffset + 1] = upper[lensOffset + 2] = 2.0;
    lower[lensOffset + 3] = initialLens.cx - centerRange;
    upper[lensOffset + 3] = initialLens.cx + centerRange;
    lower[lensOffset + 4] = initialLens.cy - centerRange;
    upper[lensOffset + 4] = initialLens.cy + centerRange;
    lower[lensOffset + 5] = -0.05;
    upper[lensOffset + 5] = 0.05;
    const double sourceScale = std::hypot(size.width, size.height) / 2.0;
    const double radialLimit = circular
        ? validRadius / sourceScale
        : std::max({
            std::hypot(initialLens.cx, initialLens.cy),
            std::hypot(size.width - initialLens.cx, initialLens.cy),
            std::hypot(initialLens.cx, size.height - initialLens.cy),
            std::hypot(size.width - initialLens.cx, size.height - initialLens.cy)
        }) / sourceScale;
    values = trialLeastSquares(
        values, lower, upper, count, size, samples, nullptr, radialLimit,
        trialRadians(0.20), 36
    );
    std::vector<std::vector<unsigned char>> keep = trialGeometryKeep(
        values, count, size, samples
    );
    TrialStrongCycle brokenCycle;
    const bool needsCycleRecovery = trialFindBrokenStrongCycle(
        count, edges, samples, keep, brokenCycle
    );
    values = trialLeastSquares(
        values, lower, upper, count, size, samples, &keep, radialLimit,
        trialRadians(0.25), 30
    );

    if (needsCycleRecovery) {
        const std::vector<cv::Matx33d> closedRotations =
            trialClosedCycleRotations(initialRotations, edges, brokenCycle);
        std::vector<double> closedValues = trialPack(
            closedRotations, initialLens
        );
        std::vector<double> closedLower = closedValues;
        std::vector<double> closedUpper = closedValues;
        for (int index = 0; index < lensOffset; ++index) {
            closedLower[index] -= 0.55;
            closedUpper[index] += 0.55;
        }
        closedLower[lensOffset] = std::max(0.8, initialLens.k1 * 0.62);
        closedUpper[lensOffset] = std::min(4.2, initialLens.k1 * 1.55);
        closedLower[lensOffset + 1] = closedLower[lensOffset + 2] = -2.0;
        closedUpper[lensOffset + 1] = closedUpper[lensOffset + 2] = 2.0;
        closedLower[lensOffset + 3] = initialLens.cx - centerRange;
        closedUpper[lensOffset + 3] = initialLens.cx + centerRange;
        closedLower[lensOffset + 4] = initialLens.cy - centerRange;
        closedUpper[lensOffset + 4] = initialLens.cy + centerRange;
        closedLower[lensOffset + 5] = -0.05;
        closedUpper[lensOffset + 5] = 0.05;
        closedValues = trialLeastSquares(
            closedValues, closedLower, closedUpper, count, size, samples,
            nullptr, radialLimit, trialRadians(0.20), 36
        );
        std::vector<std::vector<unsigned char>> closedKeep = trialGeometryKeep(
            closedValues, count, size, samples
        );
        closedValues = trialLeastSquares(
            closedValues, closedLower, closedUpper, count, size, samples,
            &closedKeep, radialLimit, trialRadians(0.25), 30
        );

        const auto treeScore = trialValidationScore(
            values, count, size, samples, radialLimit
        );
        const auto closedScore = trialValidationScore(
            closedValues, count, size, samples, radialLimit
        );
        const bool selectsClosed = closedScore.first > treeScore.first
            || (closedScore.first == treeScore.first
                && closedScore.second < treeScore.second);
        std::fprintf(
            stderr,
            "[PanoWizard] Cycle recovery: A=%d/%.9g B=%d/%.9g selected=%c\n",
            treeScore.first,
            treeScore.second,
            closedScore.first,
            closedScore.second,
            selectsClosed ? 'B' : 'A'
        );
        if (selectsClosed) {
            values = std::move(closedValues);
            keep = std::move(closedKeep);
        }
    }

    // Sub-threshold RANSAC clusters never participate in graph construction,
    // MST initialization or cycle recovery. Once those strong constraints have
    // independently established the geometry, a sparse cluster may contribute
    // only when its spatial sample agrees with that solution.
    std::mt19937 weakGenerator(20260903u);
    std::vector<int> acceptedWeakSamples;
    for (const TrialEdge &edge : weakEdges) {
        TrialOptimizationSample sample = trialSpatialSample(
            edge, size, weakGenerator
        );
        std::vector<cv::Matx33d> rotations;
        TrialLens lens;
        trialUnpack(values, count, rotations, lens);
        std::vector<unsigned char> selected(sample.firstPoints.size(), 0);
        std::vector<double> selectedErrors;
        for (size_t index = 0; index < sample.firstPoints.size(); ++index) {
            const cv::Vec3d first = rotations[sample.first]
                * trialRay(sample.firstPoints[index], size, lens);
            const cv::Vec3d second = rotations[sample.second]
                * trialRay(sample.secondPoints[index], size, lens);
            const double error = std::acos(std::clamp(
                first.dot(second), -1.0, 1.0
            ));
            if (error < trialRadians(1.20)) {
                selected[index] = 1;
                selectedErrors.push_back(error);
            }
        }
        const int required = trialRequiredSampleSupport(
            int(sample.firstPoints.size())
        );
        const bool accepted = int(selectedErrors.size()) >= required;
        const double medianBefore = selectedErrors.empty()
            ? 0.0 : trialMedian(selectedErrors) * 180.0 / trialPi;
        std::fprintf(
            stderr,
            "[PanoWizard] Weak cross-link %d-%d: raw=%d samples=%zu "
            "residual-inliers=%zu required=%d accepted=%s "
            "median-before=%.6f deg\n",
            sample.first,
            sample.second,
            sample.rawRansacSupport,
            sample.firstPoints.size(),
            selectedErrors.size(),
            required,
            accepted ? "yes" : "no",
            medianBefore
        );
        if (!accepted) continue;
        acceptedWeakSamples.push_back(int(samples.size()));
        samples.push_back(std::move(sample));
        keep.push_back(std::move(selected));
    }
    if (!acceptedWeakSamples.empty()) {
        values = trialLeastSquares(
            values, lower, upper, count, size, samples, &keep, radialLimit,
            trialRadians(0.25), 30
        );
        std::vector<cv::Matx33d> rotations;
        TrialLens lens;
        trialUnpack(values, count, rotations, lens);
        for (const int sampleIndex : acceptedWeakSamples) {
            const TrialOptimizationSample &sample = samples[sampleIndex];
            std::vector<double> errors;
            for (size_t index = 0; index < sample.firstPoints.size(); ++index) {
                if (!keep[sampleIndex][index]) continue;
                const cv::Vec3d first = rotations[sample.first]
                    * trialRay(sample.firstPoints[index], size, lens);
                const cv::Vec3d second = rotations[sample.second]
                    * trialRay(sample.secondPoints[index], size, lens);
                errors.push_back(std::acos(std::clamp(
                    first.dot(second), -1.0, 1.0
                )));
            }
            std::fprintf(
                stderr,
                "[PanoWizard] Weak cross-link %d-%d: observations=%zu "
                "median-after=%.6f deg\n",
                sample.first,
                sample.second,
                errors.size(),
                errors.empty()
                    ? 0.0 : trialMedian(errors) * 180.0 / trialPi
            );
        }
    }

    std::vector<cv::Matx33d> rotations;
    TrialLens lens;
    trialUnpack(values, count, rotations, lens);
    std::vector<double> errors;
    for (size_t sampleIndex = 0; sampleIndex < samples.size(); ++sampleIndex) {
        const TrialOptimizationSample &sample = samples[sampleIndex];
        for (size_t index = 0; index < sample.firstPoints.size(); ++index) {
            if (!keep[sampleIndex][index]) continue;
            const cv::Vec3d first = rotations[sample.first]
                * trialRay(sample.firstPoints[index], size, lens);
            const cv::Vec3d second = rotations[sample.second]
                * trialRay(sample.secondPoints[index], size, lens);
            const double error = std::acos(std::clamp(first.dot(second), -1.0, 1.0));
            if (error < trialRadians(0.75)) errors.push_back(error);
        }
    }
    double squared = 0.0;
    for (double error : errors) squared += error * error;
    TrialAlignment result;
    result.rotations = std::move(rotations);
    result.lens = lens;
    result.gains = cv::Mat::ones(count, 3, CV_64F);
    result.stats = {
        int(errors.size()),
        trialMedian(errors) * 180.0 / trialPi,
        errors.empty() ? 0.0 : std::sqrt(squared / errors.size()) * 180.0 / trialPi
    };
    return result;
}

std::vector<cv::Matx33d> trialLevelRotations(
    const std::vector<cv::Matx33d> &rotations
) {
    std::vector<cv::Vec3d> right;
    std::vector<double> weights(rotations.size(), 1.0);
    for (const auto &rotation : rotations) {
        right.push_back(rotation * cv::Vec3d(1.0, 0.0, 0.0));
    }
    cv::Vec3d up(0.0, 1.0, 0.0);
    for (int iteration = 0; iteration < 8; ++iteration) {
        cv::Matx33d covariance = cv::Matx33d::zeros();
        for (size_t index = 0; index < right.size(); ++index) {
            for (int row = 0; row < 3; ++row) {
                for (int column = 0; column < 3; ++column) {
                    covariance(row, column) +=
                        right[index][row] * right[index][column] * weights[index];
                }
            }
        }
        cv::Mat eigenvalues;
        cv::Mat eigenvectors;
        cv::eigen(cv::Mat(covariance), eigenvalues, eigenvectors);
        up = cv::Vec3d(
            eigenvectors.at<double>(2, 0),
            eigenvectors.at<double>(2, 1),
            eigenvectors.at<double>(2, 2)
        );
        for (size_t index = 0; index < right.size(); ++index) {
            weights[index] = 1.0 / std::max(0.08, std::abs(right[index].dot(up)));
        }
    }
    double orientation = 0.0;
    for (const auto &rotation : rotations) {
        orientation += (rotation * cv::Vec3d(0.0, -1.0, 0.0)).dot(up);
    }
    if (orientation < 0.0) up = -up;
    const cv::Vec3d target(0.0, 1.0, 0.0);
    const cv::Vec3d axis = up.cross(target);
    const double norm = cv::norm(axis);
    cv::Matx33d leveling = cv::Matx33d::eye();
    if (norm >= 1e-10) {
        leveling = trialRotationMatrix(
            axis / norm * std::atan2(norm, up.dot(target))
        );
    }
    std::vector<cv::Matx33d> result;
    for (const auto &rotation : rotations) result.push_back(leveling * rotation);
    return result;
}

void trialDetectSupplementalViews(
    std::vector<unsigned char> &roles,
    const std::vector<cv::Matx33d> &initialRotations
) {
    if (initialRotations.size() < 4) return;
    const std::vector<cv::Matx33d> leveled = trialLevelRotations(
        initialRotations
    );
    int horizontalCount = 0;
    int automaticNadirCount = 0;
    for (int index = 0; index < int(leveled.size()); ++index) {
        if (roles[index] == 2) continue;
        const cv::Vec3d axis = leveled[index] * cv::Vec3d(0.0, 0.0, 1.0);
        if (std::abs(axis[1]) < 0.65) ++horizontalCount;
        if (roles[index] == 0 && axis[1] < -0.80) {
            ++automaticNadirCount;
        }
    }
    if (horizontalCount < 3) return;

    // A lone automatic nadir frame is normally a hand-held repair shot and
    // must not steer the ring geometry. Two such frames, however, provide a
    // mutually verified monopod sequence with useful control-point support.
    if (automaticNadirCount >= 2) return;

    for (int index = 0; index < int(leveled.size()); ++index) {
        if (roles[index] != 0) continue;
        const cv::Vec3d axis = leveled[index] * cv::Vec3d(0.0, 0.0, 1.0);
        if (axis[1] < -0.80) roles[index] = 2;
    }
}

cv::Matx33d trialRegisterSupplementalView(
    int sourceIndex,
    const std::vector<int> &ringIndices,
    const std::vector<cv::Matx33d> &ringRotations,
    const std::vector<TrialEdge> &edges,
    const cv::Size &sourceSize,
    const TrialLens &lens
) {
    std::vector<cv::Vec3d> sourceRays;
    std::vector<cv::Vec3d> targetRays;
    for (const TrialEdge &edge : edges) {
        const auto ring = std::find(
            ringIndices.begin(), ringIndices.end(),
            edge.first == sourceIndex ? edge.second : edge.first
        );
        if (ring == ringIndices.end()) continue;
        const bool sourceIsFirst = edge.first == sourceIndex;
        const bool sourceIsSecond = edge.second == sourceIndex;
        if (!sourceIsFirst && !sourceIsSecond) continue;
        const int ringIndex = int(std::distance(ringIndices.begin(), ring));
        for (size_t point = 0; point < edge.firstPoints.size(); ++point) {
            const cv::Point2d sourcePoint = sourceIsFirst
                ? edge.firstPoints[point] : edge.secondPoints[point];
            const cv::Point2d ringPoint = sourceIsFirst
                ? edge.secondPoints[point] : edge.firstPoints[point];
            sourceRays.push_back(trialRay(sourcePoint, sourceSize, lens));
            targetRays.push_back(
                ringRotations[ringIndex] * trialRay(ringPoint, sourceSize, lens)
            );
        }
    }
    if (sourceRays.size() < 20) {
        throw std::runtime_error(
            "En reparationsbild kunde inte registreras mot panoramaringen."
        );
    }
    auto [rotation, selected] = trialRansacRotation(sourceRays, targetRays);
    if (selected.empty()
        || std::accumulate(selected.begin(), selected.end(), 0) < 20) {
        throw std::runtime_error(
            "En reparationsbild ligger för långt från panoramaringen för automatisk registrering."
        );
    }
    return rotation;
}

cv::Mat trialExposureGains(
    const std::vector<TrialSource> &sources,
    const std::vector<TrialEdge> &edges
) {
    const int count = int(sources.size());
    cv::Mat result = cv::Mat::ones(count, 3, CV_64F);
    for (int channel = 0; channel < 3; ++channel) {
        std::vector<std::vector<double>> rows;
        std::vector<double> values;
        for (const TrialEdge &edge : edges) {
            std::vector<double> differences;
            for (size_t index = 0; index < edge.firstPoints.size(); ++index) {
                const cv::Point first(
                    int(std::round(edge.firstPoints[index].x)),
                    int(std::round(edge.firstPoints[index].y))
                );
                const cv::Point second(
                    int(std::round(edge.secondPoints[index].x)),
                    int(std::round(edge.secondPoints[index].y))
                );
                const double one = sources[edge.first].image.at<cv::Vec3b>(first)[channel];
                const double two = sources[edge.second].image.at<cv::Vec3b>(second)[channel];
                if (one > 15 && one < 240 && two > 15 && two < 240) {
                    differences.push_back(std::log(two) - std::log(one));
                }
            }
            if (differences.size() < 18) continue;
            std::vector<double> row(std::max(0, count - 1), 0.0);
            if (edge.first > 0) row[edge.first - 1] += 1.0;
            if (edge.second > 0) row[edge.second - 1] -= 1.0;
            rows.push_back(std::move(row));
            values.push_back(trialMedian(std::move(differences)));
        }
        if (!rows.empty() && count > 1) {
            cv::Mat design(int(rows.size()), count - 1, CV_64F);
            cv::Mat target(int(rows.size()), 1, CV_64F);
            for (int row = 0; row < int(rows.size()); ++row) {
                target.at<double>(row) = values[row];
                for (int column = 0; column < count - 1; ++column) {
                    design.at<double>(row, column) = rows[row][column];
                }
            }
            cv::Mat solution;
            cv::solve(design, target, solution, cv::DECOMP_SVD);
            for (int index = 1; index < count; ++index) {
                result.at<double>(index, channel) = std::clamp(
                    std::exp(solution.at<double>(index - 1)), 0.65, 1.55
                );
            }
        }
    }
    return result;
}

bool trialLoadCache(
    const std::string &path,
    int imageCount,
    const cv::Size &sourceSize,
    TrialAlignment &alignment
) {
    if (path.empty() || !std::filesystem::exists(path)) return false;
    cv::FileStorage storage(path, cv::FileStorage::READ);
    if (!storage.isOpened()) return false;
    int version = 0;
    int storedCount = 0;
    int width = 0;
    int height = 0;
    storage["version"] >> version;
    storage["imageCount"] >> storedCount;
    storage["width"] >> width;
    storage["height"] >> height;
    if (version != trialCacheVersion || storedCount != imageCount
        || width != sourceSize.width || height != sourceSize.height) return false;
    cv::Mat rotations;
    cv::Mat lens;
    storage["rotations"] >> rotations;
    storage["lens"] >> lens;
    storage["gains"] >> alignment.gains;
    if (rotations.rows != imageCount || rotations.cols != 9
        || lens.total() != 6 || alignment.gains.rows != imageCount
        || alignment.gains.cols != 3) return false;
    alignment.rotations.clear();
    for (int index = 0; index < imageCount; ++index) {
        cv::Matx33d rotation;
        for (int row = 0; row < 3; ++row) {
            for (int column = 0; column < 3; ++column) {
                rotation(row, column) = rotations.at<double>(index, row * 3 + column);
            }
        }
        alignment.rotations.push_back(rotation);
    }
    const cv::Mat flattenedLens = lens.reshape(1, 1);
    alignment.lens = {
        flattenedLens.at<double>(0, 0), flattenedLens.at<double>(0, 1),
        flattenedLens.at<double>(0, 2), flattenedLens.at<double>(0, 3),
        flattenedLens.at<double>(0, 4), flattenedLens.at<double>(0, 5)
    };
    storage["observations"] >> alignment.stats.observations;
    storage["medianDegrees"] >> alignment.stats.medianDegrees;
    storage["rmsDegrees"] >> alignment.stats.rmsDegrees;
    return true;
}

void trialSaveCache(const std::string &path, const TrialAlignment &alignment, cv::Size size) {
    if (path.empty()) return;
    std::filesystem::create_directories(std::filesystem::path(path).parent_path());
    cv::FileStorage storage(path, cv::FileStorage::WRITE);
    if (!storage.isOpened()) return;
    cv::Mat rotations(int(alignment.rotations.size()), 9, CV_64F);
    for (int index = 0; index < rotations.rows; ++index) {
        for (int row = 0; row < 3; ++row) {
            for (int column = 0; column < 3; ++column) {
                rotations.at<double>(index, row * 3 + column) =
                    alignment.rotations[index](row, column);
            }
        }
    }
    cv::Mat lens(1, 6, CV_64F);
    const std::array<double, 6> lensValues = {
        alignment.lens.k1, alignment.lens.k3, alignment.lens.k5,
        alignment.lens.cx, alignment.lens.cy, alignment.lens.aspect
    };
    for (int index = 0; index < int(lensValues.size()); ++index) {
        lens.at<double>(0, index) = lensValues[index];
    }
    storage << "version" << trialCacheVersion;
    storage << "imageCount" << int(alignment.rotations.size());
    storage << "width" << size.width;
    storage << "height" << size.height;
    storage << "rotations" << rotations;
    storage << "lens" << lens;
    storage << "gains" << alignment.gains;
    storage << "observations" << alignment.stats.observations;
    storage << "medianDegrees" << alignment.stats.medianDegrees;
    storage << "rmsDegrees" << alignment.stats.rmsDegrees;
}

cv::Mat trialFittedOpticalMask(const cv::Size &size, const TrialLens &lens) {
    cv::Mat mask(size, CV_8U, cv::Scalar(0));
    const double scale = std::hypot(size.width, size.height) / 2.0;
    int valid = 0;
    for (int y = 0; y < size.height; ++y) {
        unsigned char *row = mask.ptr<unsigned char>(y);
        for (int x = 0; x < size.width; ++x) {
            const double nx = (x - lens.cx) / scale;
            const double ny = (y - lens.cy) / scale * (1.0 + lens.aspect);
            const double radius = std::hypot(nx, ny);
            const double theta = lens.k1 * radius
                + lens.k3 * std::pow(radius, 3.0)
                + lens.k5 * std::pow(radius, 5.0);
            if (theta <= trialPi / 2.0 + trialRadians(0.4)) {
                row[x] = 255;
                ++valid;
            }
        }
    }
    const double coverage = valid / double(size.area());
    if (coverage >= 0.985) mask.setTo(255);
    return mask;
}

void trialMapping(
    int width,
    int height,
    const cv::Matx33d &rotation,
    const cv::Size &sourceSize,
    const TrialLens &lens,
    const cv::Mat &validSourceMask,
    cv::Mat &mapX,
    cv::Mat &mapY,
    cv::Mat &valid,
    cv::Mat &score
) {
    mapX.create(height, width, CV_32F);
    mapY.create(height, width, CV_32F);
    cv::Mat inside(height, width, CV_8U, cv::Scalar(0));
    score.create(height, width, CV_32F);
    const double scale = std::hypot(sourceSize.width, sourceSize.height) / 2.0;
    const double radiusMaximum = std::max({
        std::hypot(lens.cx, lens.cy),
        std::hypot(sourceSize.width - lens.cx, lens.cy),
        std::hypot(lens.cx, sourceSize.height - lens.cy),
        std::hypot(sourceSize.width - lens.cx, sourceSize.height - lens.cy)
    }) / scale;
    const cv::Matx33d inverseRotation = rotation.t();
    for (int y = 0; y < height; ++y) {
        float *xRow = mapX.ptr<float>(y);
        float *yRow = mapY.ptr<float>(y);
        float *scoreRow = score.ptr<float>(y);
        unsigned char *insideRow = inside.ptr<unsigned char>(y);
        const double latitude = (0.5 - (y + 0.5) / height) * trialPi;
        const double cosine = std::cos(latitude);
        const double worldY = std::sin(latitude);
        for (int x = 0; x < width; ++x) {
            const double longitude = ((x + 0.5) / width - 0.5) * 2.0 * trialPi;
            const cv::Vec3d world(
                std::sin(longitude) * cosine,
                worldY,
                std::cos(longitude) * cosine
            );
            const cv::Vec3d direction = inverseRotation * world;
            const double theta = std::acos(std::clamp(direction[2], -1.0, 1.0));
            double radius = theta / std::max(0.04, lens.k1);
            radius = std::clamp(radius, 0.0, radiusMaximum + 1.0);
            for (int iteration = 0; iteration < 7; ++iteration) {
                const double radius2 = radius * radius;
                const double function = lens.k1 * radius
                    + lens.k3 * radius * radius2
                    + lens.k5 * radius * radius2 * radius2 - theta;
                const double derivative = lens.k1
                    + 3.0 * lens.k3 * radius2
                    + 5.0 * lens.k5 * radius2 * radius2;
                radius = std::clamp(
                    radius - function / std::max(0.04, derivative),
                    0.0,
                    radiusMaximum + 1.0
                );
            }
            const double sine = std::sin(theta);
            const double factor = sine > 1e-7 ? radius / sine : 0.0;
            const double sourceX = lens.cx + scale * direction[0] * factor;
            const double sourceY = lens.cy
                + scale * direction[1] * factor / (1.0 + lens.aspect);
            xRow[x] = float(sourceX);
            yRow[x] = float(sourceY);
            scoreRow[x] = float(direction[2]);
            insideRow[x] = sourceX >= 1.0 && sourceX < sourceSize.width - 2.0
                && sourceY >= 1.0 && sourceY < sourceSize.height - 2.0
                ? 255 : 0;
        }
    }
    cv::Mat optical;
    cv::remap(
        validSourceMask, optical, mapX, mapY, cv::INTER_NEAREST,
        cv::BORDER_CONSTANT, cv::Scalar(0)
    );
    cv::bitwise_and(inside, optical, valid);
}

cv::Mat trialPeriodicBlur(const cv::Mat &source, double sigma) {
    const int padding = std::min(
        source.cols / 2, int(std::ceil(4.0 * sigma))
    );
    if (padding <= 0) return source.clone();
    std::vector<cv::Mat> pieces = {
        source.colRange(source.cols - padding, source.cols),
        source,
        source.colRange(0, padding)
    };
    cv::Mat extended;
    cv::hconcat(pieces, extended);
    cv::GaussianBlur(
        extended, extended, cv::Size(), sigma, sigma, cv::BORDER_REFLECT_101
    );
    return extended.colRange(padding, padding + source.cols).clone();
}

std::vector<cv::Mat> trialSuppressRedundantViews(
    const std::vector<cv::Matx33d> &rotations,
    const std::vector<TrialWarp> &warps
) {
    std::vector<cv::Vec3d> axes;
    std::vector<cv::Mat> result;
    for (size_t index = 0; index < rotations.size(); ++index) {
        axes.push_back(rotations[index] * cv::Vec3d(0.0, 0.0, 1.0));
        result.push_back(warps[index].mask.clone());
    }
    std::vector<int> claimed;
    const double cosine = std::cos(trialRadians(12.0));
    for (int index = 0; index < int(axes.size()); ++index) {
        int primary = -1;
        for (int other : claimed) {
            if (axes[index].dot(axes[other]) > cosine) {
                primary = other;
                break;
            }
        }
        if (primary < 0) {
            claimed.push_back(index);
            continue;
        }
        cv::Mat inversePrimary;
        cv::bitwise_not(warps[primary].mask, inversePrimary);
        cv::bitwise_and(result[index], inversePrimary, result[index]);
        cv::bitwise_or(result[index], warps[index].protectedMask, result[index]);
    }
    return result;
}

cv::Mat trialHighlightReliability(const cv::Mat &image) {
    std::vector<cv::Mat> channels;
    cv::split(image, channels);
    cv::Mat darkest;
    cv::min(channels[0], channels[1], darkest);
    cv::min(darkest, channels[2], darkest);
    darkest.convertTo(darkest, CV_32F);
    cv::Mat reliability = (252.0 - darkest) / 24.0;
    cv::max(reliability, 0.01, reliability);
    cv::min(reliability, 1.0, reliability);
    return reliability;
}

std::vector<cv::Mat> trialPreferCentralCoverage(
    const std::vector<TrialWarp> &warps,
    const std::vector<cv::Mat> &masks
) {
    // GraphCut only sees colour discontinuities. Without a geometric prior it
    // can therefore replace a clear, central subject with peripheral pixels
    // from another exposure of the same direction. Keep a narrow overlap band
    // for seam optimisation, but do not let it discard substantially more
    // central source coverage. Explicit protected masks always win.
    constexpr float tolerance = 0.12f;
    cv::Mat best(
        warps.front().score.size(), CV_32F,
        cv::Scalar(-std::numeric_limits<float>::max())
    );
    for (size_t index = 0; index < warps.size(); ++index) {
        cv::Mat candidate = warps[index].score.clone();
        candidate.setTo(
            -std::numeric_limits<float>::max(), masks[index] == 0
        );
        cv::max(best, candidate, best);
    }

    std::vector<cv::Mat> result;
    result.reserve(warps.size());
    for (size_t index = 0; index < warps.size(); ++index) {
        cv::Mat threshold = best - tolerance;
        cv::Mat preferred;
        cv::compare(
            warps[index].score, threshold, preferred, cv::CMP_GE
        );
        cv::bitwise_and(preferred, masks[index], preferred);
        cv::bitwise_or(
            preferred, warps[index].protectedMask, preferred
        );
        result.push_back(std::move(preferred));
    }
    return result;
}

cv::Mat trialPeriodicExpand(const cv::Mat &mask, int radius);

cv::Mat trialGraphCutLabels(
    const std::vector<TrialWarp> &warps,
    const std::vector<cv::Mat> &seamMasks,
    int width,
    int height,
    cv::Mat &conflictMask
) {
    const int seamWidth = std::min(2048, width);
    const int seamHeight = seamWidth / 2;
    std::vector<cv::Mat> smallImages;
    std::vector<cv::Mat> smallMasks;
    for (size_t index = 0; index < warps.size(); ++index) {
        cv::Mat image;
        cv::resize(
            warps[index].image, image, cv::Size(seamWidth, seamHeight),
            0.0, 0.0, cv::INTER_AREA
        );
        image.convertTo(image, CV_32F);
        smallImages.push_back(std::move(image));
        cv::Mat mask;
        cv::resize(
            seamMasks[index], mask, cv::Size(seamWidth, seamHeight),
            0.0, 0.0, cv::INTER_NEAREST
        );
        smallMasks.push_back(std::move(mask));
    }

    // PairwiseSeamFinder derives each graph ROI from the source image
    // rectangles, not from their masks. Give every source its real mask-support
    // rectangle in panorama coordinates, with enough genuine source context
    // for GraphCut's internal gap. Cropping both members of a pair to the same
    // overlap rectangle is subtly wrong: the artificial shared crop edge can
    // become a seam boundary (visible as a hard rectangle in the panorama).
    // Independent source rectangles preserve OpenCV's coordinate model and its
    // normal all-image pair order while avoiding full-panorama graph extents.
    const cv::Rect canvas(0, 0, seamWidth, seamHeight);
    constexpr int graphCutContext = 10;
    std::vector<int> graphIndices;
    std::vector<cv::Rect> graphROIs;
    std::vector<cv::Mat> graphImageStorage;
    std::vector<cv::Mat> graphMaskStorage;
    graphIndices.reserve(warps.size());
    graphROIs.reserve(warps.size());
    graphImageStorage.reserve(warps.size());
    graphMaskStorage.reserve(warps.size());
    for (int index = 0; index < int(warps.size()); ++index) {
        if (cv::countNonZero(smallMasks[index]) == 0) continue;
        const cv::Rect bounds = cv::boundingRect(smallMasks[index]);
        const cv::Rect roi = cv::Rect(
            bounds.x - graphCutContext,
            bounds.y - graphCutContext,
            bounds.width + 2 * graphCutContext,
            bounds.height + 2 * graphCutContext
        ) & canvas;
        graphIndices.push_back(index);
        graphROIs.push_back(roi);
        graphImageStorage.push_back(smallImages[index](roi).clone());
        graphMaskStorage.push_back(smallMasks[index](roi).clone());
    }

    if (graphIndices.size() > 1) {
        std::vector<cv::UMat> graphImages;
        std::vector<cv::UMat> graphMasks;
        std::vector<cv::Point> graphCorners;
        graphImages.reserve(graphIndices.size());
        graphMasks.reserve(graphIndices.size());
        graphCorners.reserve(graphIndices.size());
        for (size_t graphIndex = 0;
             graphIndex < graphIndices.size(); ++graphIndex) {
            graphImages.push_back(
                graphImageStorage[graphIndex].getUMat(cv::ACCESS_READ)
            );
            graphMasks.push_back(
                graphMaskStorage[graphIndex].getUMat(cv::ACCESS_RW)
            );
            graphCorners.push_back(graphROIs[graphIndex].tl());
        }
        cv::detail::GraphCutSeamFinder finder("COST_COLOR_GRAD");
        finder.find(graphImages, graphCorners, graphMasks);
        for (size_t graphIndex = 0;
             graphIndex < graphIndices.size(); ++graphIndex) {
            graphMasks[graphIndex].getMat(cv::ACCESS_READ).copyTo(
                smallMasks[graphIndices[graphIndex]](graphROIs[graphIndex])
            );
        }
    }

    cv::Mat labels(height, width, CV_16S, cv::Scalar(-1));
    cv::Mat best(height, width, CV_32F, cv::Scalar(-1e9f));
    for (int index = 0; index < int(warps.size()); ++index) {
        cv::Mat seamMask;
        cv::resize(
            smallMasks[index], seamMask,
            cv::Size(width, height), 0.0, 0.0, cv::INTER_NEAREST
        );
        for (int y = 0; y < height; ++y) {
            const unsigned char *maskRow = seamMask.ptr<unsigned char>(y);
            const unsigned char *protectedRow =
                warps[index].protectedMask.ptr<unsigned char>(y);
            const float *scoreRow = warps[index].score.ptr<float>(y);
            short *labelRow = labels.ptr<short>(y);
            float *bestRow = best.ptr<float>(y);
            for (int x = 0; x < width; ++x) {
                const float candidate = protectedRow[x] ? 100.0f + scoreRow[x] : scoreRow[x];
                if ((maskRow[x] || protectedRow[x]) && candidate > bestRow[x]) {
                    labelRow[x] = short(index);
                    bestRow[x] = candidate;
                }
            }
        }
    }
    for (int index = 0; index < int(warps.size()); ++index) {
        for (int y = 0; y < height; ++y) {
            const unsigned char *maskRow = warps[index].mask.ptr<unsigned char>(y);
            const float *scoreRow = warps[index].score.ptr<float>(y);
            short *labelRow = labels.ptr<short>(y);
            float *bestRow = best.ptr<float>(y);
            for (int x = 0; x < width; ++x) {
                if (labelRow[x] < 0 && maskRow[x] && scoreRow[x] > bestRow[x]) {
                    labelRow[x] = short(index);
                    bestRow[x] = scoreRow[x];
                }
            }
        }
    }

    // A close, moving or strongly parallaxed subject can disagree completely
    // between otherwise well-aligned views. GraphCut may then carve the
    // subject into unrelated pieces because either side of the object is a
    // locally cheap seam. Detect those conflicts without classifying their
    // content and keep the geometrically most central source throughout them.
    cv::Mat centralLabels(height, width, CV_16S, cv::Scalar(-1));
    cv::Mat centralBest(height, width, CV_32F, cv::Scalar(-1e9f));
    for (int index = 0; index < int(warps.size()); ++index) {
        for (int y = 0; y < height; ++y) {
            const unsigned char *maskRow = seamMasks[index].ptr<unsigned char>(y);
            const float *scoreRow = warps[index].score.ptr<float>(y);
            short *labelRow = centralLabels.ptr<short>(y);
            float *bestRow = centralBest.ptr<float>(y);
            for (int x = 0; x < width; ++x) {
                if (maskRow[x] && scoreRow[x] > bestRow[x]) {
                    labelRow[x] = short(index);
                    bestRow[x] = scoreRow[x];
                }
            }
        }
    }
    cv::Mat centralImage(height, width, CV_8UC3, cv::Scalar(0, 0, 0));
    for (int index = 0; index < int(warps.size()); ++index) {
        warps[index].image.copyTo(centralImage, centralLabels == index);
    }
    conflictMask = cv::Mat(height, width, CV_8U, cv::Scalar(0));
    for (int index = 0; index < int(warps.size()); ++index) {
        cv::Mat competing;
        cv::bitwise_and(
            seamMasks[index], centralLabels != index, competing
        );
        cv::bitwise_and(competing, centralLabels >= 0, competing);
        if (cv::countNonZero(competing) == 0) continue;
        cv::Mat difference;
        cv::absdiff(warps[index].image, centralImage, difference);
        std::vector<cv::Mat> channels;
        cv::split(difference, channels);
        cv::Mat disagreement;
        channels[0].convertTo(disagreement, CV_32F, 1.0 / 3.0);
        cv::Mat channel;
        channels[1].convertTo(channel, CV_32F, 1.0 / 3.0);
        disagreement += channel;
        channels[2].convertTo(channel, CV_32F, 1.0 / 3.0);
        disagreement += channel;
        cv::Mat conflicting = disagreement > 48.0;
        cv::bitwise_and(conflicting, competing, conflicting);
        cv::bitwise_or(conflictMask, conflicting, conflictMask);
    }
    // GraphCut owns the final seam. The conflict mask is consumed by the
    // blender so that it does not re-introduce a second exposure across the
    // coherent subject selected here.

    // Manual protection is an explicit instruction and must override every
    // automatic ownership decision, including conflict buffering.
    for (int index = 0; index < int(warps.size()); ++index) {
        labels.setTo(index, warps[index].protectedMask);
    }
    return labels;
}

cv::Mat trialFeatherComposite(
    const std::vector<TrialWarp> &warps,
    const cv::Mat &labels,
    double sigma
) {
    const int width = labels.cols;
    const int height = labels.rows;
    cv::Mat accumulator(height, width, CV_32FC3, cv::Scalar(0, 0, 0));
    cv::Mat total(height, width, CV_32F, cv::Scalar(0));
    for (int index = 0; index < int(warps.size()); ++index) {
        cv::Mat ownership = labels == index;
        if (cv::countNonZero(ownership) == 0) continue;
        ownership.convertTo(ownership, CV_32F, 1.0 / 255.0);
        std::vector<cv::Mat> tiledPieces = {
            warps[index].mask, warps[index].mask, warps[index].mask
        };
        cv::Mat tiled;
        cv::hconcat(tiledPieces, tiled);
        cv::Mat distance;
        cv::distanceTransform(tiled, distance, cv::DIST_L2, 5);
        cv::Mat edgeFade = distance.colRange(width, 2 * width).clone()
            / std::max(1.0, 1.5 * sigma);
        cv::min(edgeFade, 1.0, edgeFade);
        cv::Mat weight = trialPeriodicBlur(ownership, sigma).mul(edgeFade);
        cv::Mat floatImage;
        warps[index].image.convertTo(floatImage, CV_32FC3);
        std::vector<cv::Mat> weightChannels(3, weight);
        cv::Mat colorWeight;
        cv::merge(weightChannels, colorWeight);
        accumulator += floatImage.mul(colorWeight);
        total += weight;
    }
    cv::Mat safeTotal;
    cv::max(total, 1e-6, safeTotal);
    std::vector<cv::Mat> totalChannels(3, safeTotal);
    cv::Mat colorTotal;
    cv::merge(totalChannels, colorTotal);
    cv::Mat result = accumulator / colorTotal;
    for (int index = 0; index < int(warps.size()); ++index) {
        cv::Mat missing = total < 1e-5;
        cv::Mat owned = labels == index;
        cv::bitwise_and(missing, owned, missing);
        cv::Mat floatImage;
        warps[index].image.convertTo(floatImage, CV_32FC3);
        floatImage.copyTo(result, missing);
    }
    return result;
}

cv::Mat trialCenterWeightedComposite(
    const std::vector<TrialWarp> &warps,
    const cv::Mat &labels
) {
    const int width = labels.cols;
    const int height = labels.rows;
    cv::Mat accumulator(height, width, CV_32FC3, cv::Scalar(0, 0, 0));
    cv::Mat total(height, width, CV_32F, cv::Scalar(0));
    for (int index = 0; index < int(warps.size()); ++index) {
        const TrialWarp &warp = warps[index];
        std::vector<cv::Mat> tiledPieces = {warp.mask, warp.mask, warp.mask};
        cv::Mat tiled;
        cv::hconcat(tiledPieces, tiled);
        cv::Mat distance;
        cv::distanceTransform(tiled, distance, cv::DIST_L2, 5);
        cv::Mat edgeFade = distance.colRange(width, 2 * width).clone()
            / std::max(8.0, width / 24.0);
        cv::min(edgeFade, 1.0, edgeFade);
        cv::Mat clipped;
        cv::max(warp.score, 0.0, clipped);
        cv::min(clipped, 1.0, clipped);
        cv::Mat squared = clipped.mul(clipped);
        cv::Mat weight = squared.mul(squared).mul(edgeFade);

        // Prefer the source that still contains highlight detail. A clipped
        // sky carries no recoverable tone information and must not reveal a
        // fisheye footprint merely because that view is closest to its
        // optical axis. Keep a small floor so genuinely white subjects still
        // blend normally when every overlapping view is clipped.
        const cv::Mat highlightReliability = trialHighlightReliability(
            warp.image
        );
        weight = weight.mul(highlightReliability);
        if (warp.fillOnly) {
            weight.setTo(0, labels != index);
        }
        cv::Mat floatImage;
        warp.image.convertTo(floatImage, CV_32FC3);
        std::vector<cv::Mat> weightChannels(3, weight);
        cv::Mat colorWeight;
        cv::merge(weightChannels, colorWeight);
        accumulator += floatImage.mul(colorWeight);
        total += weight;
    }
    cv::Mat safeTotal;
    cv::max(total, 1e-6, safeTotal);
    std::vector<cv::Mat> totalChannels(3, safeTotal);
    cv::Mat colorTotal;
    cv::merge(totalChannels, colorTotal);
    cv::Mat result = accumulator / colorTotal;
    for (int index = 0; index < int(warps.size()); ++index) {
        cv::Mat missing = total < 1e-5;
        cv::Mat owned = labels == index;
        cv::bitwise_and(missing, owned, missing);
        cv::Mat floatImage;
        warps[index].image.convertTo(floatImage, CV_32FC3);
        floatImage.copyTo(result, missing);
    }
    return result;
}

cv::Mat trialPeriodicExpand(const cv::Mat &mask, int radius) {
    std::vector<cv::Mat> pieces = {mask, mask, mask};
    cv::Mat tiled;
    cv::hconcat(pieces, tiled);
    cv::Mat inverse;
    cv::bitwise_not(tiled, inverse);
    cv::Mat distance;
    cv::distanceTransform(inverse, distance, cv::DIST_L2, 5);
    return distance.colRange(mask.cols, 2 * mask.cols) <= radius;
}

cv::Mat trialContentAdaptiveBlend(
    const std::vector<TrialWarp> &warps,
    const cv::Mat &labels,
    const cv::Mat &conflictMask,
    int width,
    int height
) {
    const double detailSigma = std::max(1.0, width / 4096.0);
    cv::Mat narrow = trialFeatherComposite(warps, labels, detailSigma);
    cv::Mat broad = trialCenterWeightedComposite(warps, labels);
    const cv::Size smallSize(width / 2, height / 2);
    cv::Mat narrowSmall;
    cv::Mat broadSmall;
    cv::resize(narrow, narrowSmall, smallSize, 0.0, 0.0, cv::INTER_AREA);
    cv::resize(broad, broadSmall, smallSize, 0.0, 0.0, cv::INTER_AREA);
    const double correctionRadius = std::max(6.0, width / 512.0);
    cv::Mat correctionSmall = trialPeriodicBlur(
        broadSmall, correctionRadius / 2.0
    ) - trialPeriodicBlur(narrowSmall, correctionRadius / 2.0);
    cv::Mat correction;
    cv::resize(
        correctionSmall, correction, cv::Size(width, height),
        0.0, 0.0, cv::INTER_CUBIC
    );
    cv::Mat difference;
    cv::absdiff(broad, narrow, difference);
    std::vector<cv::Mat> differenceChannels;
    cv::split(difference, differenceChannels);
    cv::Mat disagreement =
        (differenceChannels[0] + differenceChannels[1] + differenceChannels[2]) / 3.0;
    cv::Mat consistency = (48.0 - disagreement) / 24.0;
    cv::max(consistency, 0.0, consistency);
    cv::min(consistency, 1.0, consistency);
    cv::max(correction, cv::Scalar(-24, -24, -24), correction);
    cv::min(correction, cv::Scalar(24, 24, 24), correction);
    std::vector<cv::Mat> consistencyChannels(3, consistency);
    cv::Mat colorConsistency;
    cv::merge(consistencyChannels, colorConsistency);
    correction = correction.mul(colorConsistency);
    cv::Mat detailed = narrow + correction;

    // Near the nadir, several ring views often meet at their peripheral
    // coverage. Preserve the one-pixel GraphCut detail there, but replace its
    // low-frequency exposure step with a wider seam-local transition. This
    // avoids both a visible radial wedge and the doubled grout/edge detail of
    // a conventional wide feather.
    const double seamSigma = std::max(24.0, width / 32.0);
    cv::Mat seamWide = trialFeatherComposite(warps, labels, seamSigma);
    const double seamDetailRadius = std::max(2.0, width / 1024.0);
    cv::Mat seamCorrection = trialPeriodicBlur(seamWide, seamDetailRadius)
        - trialPeriodicBlur(narrow, seamDetailRadius);
    cv::Mat seamDifference;
    cv::absdiff(seamWide, narrow, seamDifference);
    std::vector<cv::Mat> seamDifferenceChannels;
    cv::split(seamDifference, seamDifferenceChannels);
    cv::Mat seamDisagreement = (
        seamDifferenceChannels[0] + seamDifferenceChannels[1]
        + seamDifferenceChannels[2]
    ) / 3.0;
    cv::Mat seamConsistency = (48.0 - seamDisagreement) / 24.0;
    cv::max(seamConsistency, 0.0, seamConsistency);
    cv::min(seamConsistency, 1.0, seamConsistency);
    cv::max(seamCorrection, cv::Scalar(-24, -24, -24), seamCorrection);
    cv::min(seamCorrection, cv::Scalar(24, 24, 24), seamCorrection);
    std::vector<cv::Mat> seamConsistencyChannels(3, seamConsistency);
    cv::Mat colorSeamConsistency;
    cv::merge(seamConsistencyChannels, colorSeamConsistency);
    cv::Mat seamDetailed = narrow
        + seamCorrection.mul(colorSeamConsistency);

    cv::Mat texture(height, width, CV_32F, cv::Scalar(0));
    const int edgeGuard = std::max(2, int(std::round(width / 512.0)));
    cv::Mat edgeKernel = cv::Mat::ones(
        edgeGuard * 2 + 1, edgeGuard * 2 + 1, CV_8U
    );
    for (int index = 0; index < int(warps.size()); ++index) {
        cv::Mat gray;
        cv::cvtColor(warps[index].image, gray, cv::COLOR_BGR2GRAY);
        cv::Mat xGradient;
        cv::Mat yGradient;
        cv::Sobel(gray, xGradient, CV_32F, 1, 0, 3);
        cv::Sobel(gray, yGradient, CV_32F, 0, 1, 3);
        cv::Mat gradient;
        cv::magnitude(xGradient, yGradient, gradient);
        std::vector<cv::Mat> tiledPieces = {
            warps[index].mask, warps[index].mask, warps[index].mask
        };
        cv::Mat tiled;
        cv::hconcat(tiledPieces, tiled);
        cv::erode(tiled, tiled, edgeKernel);
        cv::Mat safe = tiled.colRange(width, 2 * width).clone();
        cv::Mat unsafe;
        cv::bitwise_not(safe, unsafe);
        gradient.setTo(0, unsafe);
        // A displaced edge in a non-owning view is just as important as an
        // edge in the selected view. Otherwise the broad tonal composite can
        // re-introduce a second copy of a nearby object over a smooth area in
        // the GraphCut-owned source (for example an umbrella strut displaced
        // by parallax).
        cv::max(texture, gradient, texture);
    }
    const int protectionRadius = std::max(8, int(std::round(width / 96.0)));
    cv::Mat protectedStructure;
    cv::bitwise_or(texture > 64.0, conflictMask, protectedStructure);
    cv::Mat structural = trialPeriodicExpand(
        protectedStructure, protectionRadius
    );
    cv::Mat smooth;
    cv::bitwise_not(structural, smooth);
    smooth.convertTo(smooth, CV_32F, 1.0 / 255.0);
    smooth = trialPeriodicBlur(smooth, std::max(2.0, protectionRadius / 2.0));
    cv::max(smooth, 0.0, smooth);
    cv::min(smooth, 1.0, smooth);
    smooth = smooth.mul(consistency);
    std::vector<cv::Mat> smoothChannels(3, smooth);
    cv::Mat colorSmooth;
    cv::merge(smoothChannels, colorSmooth);
    cv::Mat one(
        colorSmooth.size(),
        colorSmooth.type(),
        cv::Scalar(1.0, 1.0, 1.0)
    );
    cv::Mat result = detailed.mul(one - colorSmooth)
        + broad.mul(colorSmooth);

    // The wide exposure blend is useful in smooth sky and snow, but it must
    // never re-introduce a displaced exposure close to a photographed edge.
    // Fade all broad correction back to the narrow GraphCut composite around
    // detected structure, placing the radiometric transition in flat areas.
    cv::Mat structureAlpha;
    structural.convertTo(structureAlpha, CV_32F, 1.0 / 255.0);
    structureAlpha = trialPeriodicBlur(
        structureAlpha, std::max(2.0, protectionRadius / 3.0)
    );
    cv::max(structureAlpha, 0.0, structureAlpha);
    cv::min(structureAlpha, 1.0, structureAlpha);
    std::vector<cv::Mat> structureChannels(3, structureAlpha);
    cv::Mat colorStructureAlpha;
    cv::merge(structureChannels, colorStructureAlpha);
    // Preserve photographed edge detail without restoring a hard tonal
    // boundary. The two-scale composite feathers only low frequencies along
    // the seam, at any latitude, while detail stays in the narrow composite.
    result = narrow.mul(colorStructureAlpha)
        + result.mul(one - colorStructureAlpha);

    cv::max(result, cv::Scalar(0, 0, 0), result);
    cv::min(result, cv::Scalar(255, 255, 255), result);
    result.convertTo(result, CV_8UC3);
    return result;
}

struct TrialRadiometryObservation {
    int first = 0;
    int second = 0;
    double firstRadius = 0.0;
    double secondRadius = 0.0;
    cv::Vec3d value;
};

std::vector<TrialWarp> trialCompensateRadiometry(
    const std::vector<TrialWarp> &warps,
    int width
) {
    const int analysisWidth = std::min(1024, width);
    const int analysisHeight = analysisWidth / 2;
    const cv::Size analysisSize(analysisWidth, analysisHeight);
    std::vector<cv::Mat> images;
    std::vector<cv::Mat> masks;
    std::vector<cv::Mat> scores;
    std::vector<cv::Mat> gradients;
    for (const TrialWarp &warp : warps) {
        cv::Mat image;
        cv::Mat mask;
        cv::Mat score;
        cv::resize(warp.image, image, analysisSize, 0.0, 0.0, cv::INTER_AREA);
        cv::resize(warp.mask, mask, analysisSize, 0.0, 0.0, cv::INTER_NEAREST);
        cv::resize(warp.score, score, analysisSize, 0.0, 0.0, cv::INTER_LINEAR);
        cv::max(score, 0.0, score);
        cv::min(score, 1.0, score);
        cv::Mat gray;
        cv::cvtColor(image, gray, cv::COLOR_BGR2GRAY);
        cv::Mat xGradient;
        cv::Mat yGradient;
        cv::Sobel(gray, xGradient, CV_32F, 1, 0, 3);
        cv::Sobel(gray, yGradient, CV_32F, 0, 1, 3);
        cv::Mat gradient;
        cv::magnitude(xGradient, yGradient, gradient);
        images.push_back(image);
        masks.push_back(mask);
        scores.push_back(score);
        gradients.push_back(gradient);
    }
    const int count = int(warps.size());
    std::vector<double> overlapArea(count, 0.0);
    std::vector<TrialRadiometryObservation> observations;
    std::mt19937 generator(20260902u);
    cv::Mat kernel = cv::Mat::ones(5, 5, CV_8U);
    std::vector<cv::Mat> safeMasks;
    for (const cv::Mat &mask : masks) {
        cv::Mat safe;
        cv::erode(mask, safe, kernel);
        safeMasks.push_back(safe);
    }
    for (int first = 0; first < count; ++first) {
        for (int second = first + 1; second < count; ++second) {
            cv::Mat overlap;
            cv::bitwise_and(safeMasks[first], safeMasks[second], overlap);
            const int overlapCount = cv::countNonZero(overlap);
            if (overlapCount < 300) continue;
            overlapArea[first] += overlapCount;
            overlapArea[second] += overlapCount;
            std::vector<cv::Point> locations;
            for (int y = 0; y < analysisHeight; ++y) {
                const unsigned char *overlapRow = overlap.ptr<unsigned char>(y);
                const float *firstGradient = gradients[first].ptr<float>(y);
                const float *secondGradient = gradients[second].ptr<float>(y);
                const cv::Vec3b *one = images[first].ptr<cv::Vec3b>(y);
                const cv::Vec3b *two = images[second].ptr<cv::Vec3b>(y);
                for (int x = 0; x < analysisWidth; ++x) {
                    if (!overlapRow[x] || firstGradient[x] >= 28.0f
                        || secondGradient[x] >= 28.0f) continue;
                    bool unclipped = true;
                    double difference = 0.0;
                    for (int channel = 0; channel < 3; ++channel) {
                        unclipped = unclipped
                            && one[x][channel] > 10 && one[x][channel] < 245
                            && two[x][channel] > 10 && two[x][channel] < 245;
                        difference += std::abs(
                            int(one[x][channel]) - int(two[x][channel])
                        );
                    }
                    if (unclipped && difference / 3.0 < 55.0) {
                        locations.emplace_back(x, y);
                    }
                }
            }
            if (locations.size() < 120) continue;
            std::shuffle(locations.begin(), locations.end(), generator);
            locations.resize(std::min<size_t>(1800, locations.size()));
            for (const cv::Point &point : locations) {
                TrialRadiometryObservation observation;
                observation.first = first;
                observation.second = second;
                observation.firstRadius = 1.0 - scores[first].at<float>(point);
                observation.secondRadius = 1.0 - scores[second].at<float>(point);
                const cv::Vec3b one = images[first].at<cv::Vec3b>(point);
                const cv::Vec3b two = images[second].at<cv::Vec3b>(point);
                for (int channel = 0; channel < 3; ++channel) {
                    observation.value[channel] = std::log(
                        (double(two[channel]) + 2.0) / (double(one[channel]) + 2.0)
                    );
                }
                observations.push_back(observation);
            }
        }
    }
    if (observations.empty()) return warps;
    const int columns = count + 2;
    cv::Mat design(int(observations.size()), columns, CV_64F, cv::Scalar(0));
    for (int row = 0; row < int(observations.size()); ++row) {
        const auto &observation = observations[row];
        design.at<double>(row, observation.first) = 1.0;
        design.at<double>(row, observation.second) = -1.0;
        // Per-view colour/exposure offsets are observable directly in every
        // overlap. A shared radial curve is not: natural gradients such as a
        // sunlit snow slope can be mistaken for lens falloff and amplified
        // into a source-coloured wedge. Leave the two radial columns at zero.
    }
    const int anchor = int(std::distance(
        overlapArea.begin(),
        std::max_element(overlapArea.begin(), overlapArea.end())
    ));
    cv::Mat parameters = cv::Mat::zeros(3, columns, CV_64F);
    for (int channel = 0; channel < 3; ++channel) {
        cv::Mat target(int(observations.size()), 1, CV_64F);
        for (int row = 0; row < target.rows; ++row) {
            target.at<double>(row) = observations[row].value[channel];
        }
        cv::Mat weights = cv::Mat::ones(target.rows, 1, CV_64F);
        cv::Mat solution = cv::Mat::zeros(columns, 1, CV_64F);
        for (int iteration = 0; iteration < 6; ++iteration) {
            cv::Mat augmentedDesign(
                design.rows + count + 3, columns, CV_64F, cv::Scalar(0)
            );
            cv::Mat augmentedTarget(
                target.rows + count + 3, 1, CV_64F, cv::Scalar(0)
            );
            for (int row = 0; row < design.rows; ++row) {
                const double weight = std::sqrt(weights.at<double>(row));
                design.row(row).copyTo(augmentedDesign.row(row));
                augmentedDesign.row(row) *= weight;
                augmentedTarget.at<double>(row) = target.at<double>(row) * weight;
            }
            for (int index = 0; index < count; ++index) {
                augmentedDesign.at<double>(design.rows + index, index) = 0.35;
            }
            augmentedDesign.at<double>(design.rows + count, anchor) = 25.0;
            augmentedDesign.at<double>(design.rows + count + 1, count) = 0.8;
            augmentedDesign.at<double>(design.rows + count + 2, count + 1) = 1.2;
            cv::solve(augmentedDesign, augmentedTarget, solution, cv::DECOMP_SVD);
            cv::Mat residual = design * solution - target;
            std::vector<double> residualValues(residual.rows);
            for (int row = 0; row < residual.rows; ++row) {
                residualValues[row] = residual.at<double>(row);
            }
            const double center = trialMedian(residualValues);
            for (double &value : residualValues) value = std::abs(value - center);
            const double scale = std::max(0.012, 1.4826 * trialMedian(residualValues));
            for (int row = 0; row < residual.rows; ++row) {
                weights.at<double>(row) = std::min(
                    1.0, 2.5 * scale / std::max(std::abs(residual.at<double>(row)), 1e-8)
                );
            }
        }
        for (int index = 0; index < count; ++index) {
            parameters.at<double>(channel, index) = std::clamp(
                solution.at<double>(index), -0.35, 0.35
            );
        }
        parameters.at<double>(channel, count) = std::clamp(
            solution.at<double>(count), -0.8, 0.8
        );
        parameters.at<double>(channel, count + 1) = std::clamp(
            solution.at<double>(count + 1), -0.8, 0.8
        );
    }
    std::vector<TrialWarp> result = warps;
    for (int index = 0; index < count; ++index) {
        cv::Mat adjusted = warps[index].image.clone();
        for (int y = 0; y < adjusted.rows; ++y) {
            cv::Vec3b *pixelRow = adjusted.ptr<cv::Vec3b>(y);
            const unsigned char *maskRow = warps[index].mask.ptr<unsigned char>(y);
            const float *scoreRow = warps[index].score.ptr<float>(y);
            for (int x = 0; x < adjusted.cols; ++x) {
                if (!maskRow[x]) {
                    pixelRow[x] = cv::Vec3b(0, 0, 0);
                    continue;
                }
                const double radius = 1.0 - std::clamp(double(scoreRow[x]), 0.0, 1.0);
                std::array<double, 3> logGains;
                const double darkest = std::min({
                    double(pixelRow[x][0]),
                    double(pixelRow[x][1]),
                    double(pixelRow[x][2])
                });
                const double radialConfidence = std::clamp(
                    (248.0 - darkest) / 32.0, 0.0, 1.0
                );
                for (int channel = 0; channel < 3; ++channel) {
                    const double radialGain =
                        radius * parameters.at<double>(channel, count)
                        + radius * radius
                            * parameters.at<double>(channel, count + 1);
                    logGains[channel] = std::clamp(
                        parameters.at<double>(channel, index)
                        + radialConfidence * radialGain,
                        -0.45,
                        0.45
                    );
                }

                // The fit deliberately excludes clipped pixels. Do not then
                // extrapolate a positive exposure/vignetting gain into those
                // highlights and manufacture a white source footprint. Bound
                // each remaining positive correction by the channel's actual
                // headroom. Negative per-view matching remains useful here:
                // it can bring a clipped frame down to the tone of its
                // neighbours even though the radial fit has no evidence in
                // those pixels.
                for (int channel = 0; channel < 3; ++channel) {
                    double effectiveLogGain = logGains[channel];
                    if (effectiveLogGain > 0.0 && pixelRow[x][channel] > 0) {
                        const double original = pixelRow[x][channel];
                        const double ceiling = std::max(248.0, original);
                        effectiveLogGain = std::min(
                            effectiveLogGain, std::log(ceiling / original)
                        );
                    }
                    pixelRow[x][channel] = cv::saturate_cast<unsigned char>(
                        pixelRow[x][channel]
                            * std::exp(effectiveLogGain)
                    );
                }
            }
        }
        result[index].image = std::move(adjusted);
    }
    return result;
}

double trialPercentile(std::vector<double> values, double fraction) {
    if (values.empty()) return 0.0;
    const size_t index = std::min(
        values.size() - 1,
        size_t(std::floor(fraction * double(values.size() - 1)))
    );
    std::nth_element(values.begin(), values.begin() + index, values.end());
    return values[index];
}

struct TrialLocalRadiometryPair {
    int first = 0;
    int second = 0;
    int trainingPixels = 0;
    int validationPixels = 0;
    int trainingCells = 0;
    int validationCells = 0;
    double medianBefore = 0.0;
    double medianAfter = 0.0;
    double p90Before = 0.0;
    double p90After = 0.0;
    double maximumCorrection = 0.0;
};

cv::Mat trialSeamLocalRadiometryCorrection(
    const std::vector<TrialWarp> &warps,
    const cv::Mat &labels,
    int width
) {
    const int analysisWidth = std::min(1024, width);
    const int analysisHeight = analysisWidth / 2;
    const cv::Size analysisSize(analysisWidth, analysisHeight);
    const int count = int(warps.size());
    if (count < 2) return cv::Mat();

    std::vector<cv::Mat> images;
    std::vector<cv::Mat> masks;
    std::vector<cv::Mat> gradients;
    images.reserve(count);
    masks.reserve(count);
    gradients.reserve(count);
    for (const TrialWarp &warp : warps) {
        cv::Mat image;
        cv::Mat mask;
        cv::resize(warp.image, image, analysisSize, 0.0, 0.0, cv::INTER_AREA);
        cv::resize(warp.mask, mask, analysisSize, 0.0, 0.0, cv::INTER_NEAREST);
        cv::Mat gray;
        cv::cvtColor(image, gray, cv::COLOR_BGR2GRAY);
        cv::Mat xGradient;
        cv::Mat yGradient;
        cv::Sobel(gray, xGradient, CV_32F, 1, 0, 3);
        cv::Sobel(gray, yGradient, CV_32F, 0, 1, 3);
        cv::Mat gradient;
        cv::magnitude(xGradient, yGradient, gradient);
        images.push_back(std::move(image));
        masks.push_back(std::move(mask));
        gradients.push_back(std::move(gradient));
    }
    cv::Mat smallLabels;
    cv::resize(
        labels, smallLabels, analysisSize, 0.0, 0.0, cv::INTER_NEAREST
    );

    cv::Mat correctionSum(
        analysisSize, CV_32FC3, cv::Scalar(0, 0, 0)
    );
    cv::Mat correctionWeight(
        analysisSize, CV_32F, cv::Scalar(0)
    );
    std::vector<TrialLocalRadiometryPair> acceptedPairs;
    const int cellSize = std::max(8, analysisWidth / 64);
    const int gridColumns = (analysisWidth + cellSize - 1) / cellSize;
    const int gridRows = (analysisHeight + cellSize - 1) / cellSize;
    const double fieldSigma = std::max(6.0, analysisWidth / 42.67);
    const double corridorSigma = std::max(18.0, analysisWidth / 14.22);

    for (int first = 0; first < count; ++first) {
        for (int second = first + 1; second < count; ++second) {
            cv::Mat firstOwner = smallLabels == first;
            cv::Mat secondOwner = smallLabels == second;
            cv::Mat expandedFirst = trialPeriodicExpand(firstOwner, 1);
            cv::Mat expandedSecond = trialPeriodicExpand(secondOwner, 1);
            cv::Mat firstBoundary;
            cv::Mat secondBoundary;
            cv::bitwise_and(expandedFirst, secondOwner, firstBoundary);
            cv::bitwise_and(expandedSecond, firstOwner, secondBoundary);
            cv::Mat boundary;
            cv::bitwise_or(firstBoundary, secondBoundary, boundary);
            if (cv::countNonZero(boundary) < 8) continue;

            cv::Mat overlap;
            cv::bitwise_and(masks[first], masks[second], overlap);
            if (cv::countNonZero(overlap) < 300) continue;

            std::vector<cv::Mat> boundaryPieces = {boundary, boundary, boundary};
            cv::Mat tiledBoundary;
            cv::hconcat(boundaryPieces, tiledBoundary);
            cv::Mat inverseBoundary;
            cv::bitwise_not(tiledBoundary, inverseBoundary);
            cv::Mat tiledDistance;
            cv::distanceTransform(
                inverseBoundary, tiledDistance, cv::DIST_L2, 5
            );
            cv::Mat distance = tiledDistance.colRange(
                analysisWidth, 2 * analysisWidth
            ).clone();
            cv::Mat squaredDistance = distance.mul(distance);
            cv::Mat seamWeight;
            squaredDistance.convertTo(
                seamWeight, CV_32F,
                -0.5 / (corridorSigma * corridorSigma)
            );
            cv::exp(seamWeight, seamWeight);
            seamWeight.setTo(0.0f, overlap == 0);
            // Do not end a correction abruptly at a source/overlap boundary:
            // the unchanged broad blender can still sample that source there.
            // A low-frequency field must itself fade out at low frequency.
            std::vector<cv::Mat> overlapPieces = {overlap, overlap, overlap};
            cv::Mat tiledOverlap;
            cv::hconcat(overlapPieces, tiledOverlap);
            cv::Mat tiledOverlapDistance;
            cv::distanceTransform(
                tiledOverlap, tiledOverlapDistance, cv::DIST_L2, 5
            );
            cv::Mat overlapFade = tiledOverlapDistance.colRange(
                analysisWidth, 2 * analysisWidth
            ).clone() / std::max(4.0, fieldSigma);
            cv::min(overlapFade, 1.0, overlapFade);
            seamWeight = seamWeight.mul(overlapFade);

            cv::Mat training(
                analysisSize, CV_8U, cv::Scalar(0)
            );
            cv::Mat validation(
                analysisSize, CV_8U, cv::Scalar(0)
            );
            std::vector<unsigned char> trainingCellUsed(
                gridColumns * gridRows, 0
            );
            std::vector<unsigned char> validationCellUsed(
                gridColumns * gridRows, 0
            );
            int trainingPixels = 0;
            int validationPixels = 0;
            for (int y = 0; y < analysisHeight; ++y) {
                const unsigned char *overlapRow = overlap.ptr<unsigned char>(y);
                const float *firstGradient = gradients[first].ptr<float>(y);
                const float *secondGradient = gradients[second].ptr<float>(y);
                const float *weightRow = seamWeight.ptr<float>(y);
                const cv::Vec3b *one = images[first].ptr<cv::Vec3b>(y);
                const cv::Vec3b *two = images[second].ptr<cv::Vec3b>(y);
                unsigned char *trainingRow = training.ptr<unsigned char>(y);
                unsigned char *validationRow = validation.ptr<unsigned char>(y);
                for (int x = 0; x < analysisWidth; ++x) {
                    if (!overlapRow[x] || weightRow[x] <= 0.03f
                        || firstGradient[x] >= 28.0f
                        || secondGradient[x] >= 28.0f) continue;
                    bool unclipped = true;
                    double difference = 0.0;
                    for (int channel = 0; channel < 3; ++channel) {
                        unclipped = unclipped
                            && one[x][channel] > 10 && one[x][channel] < 245
                            && two[x][channel] > 10 && two[x][channel] < 245;
                        difference += std::abs(
                            int(one[x][channel]) - int(two[x][channel])
                        );
                    }
                    if (!unclipped || difference / 3.0 >= 55.0) continue;
                    const int cellX = x / cellSize;
                    const int cellY = y / cellSize;
                    const int cell = cellY * gridColumns + cellX;
                    const bool heldOut = (
                        cellX + 2 * cellY + 3 * first + second
                    ) % 5 == 0;
                    if (heldOut && weightRow[x] > 0.12f) {
                        validationRow[x] = 255;
                        validationCellUsed[cell] = 1;
                        ++validationPixels;
                    } else {
                        trainingRow[x] = 255;
                        trainingCellUsed[cell] = 1;
                        ++trainingPixels;
                    }
                }
            }
            const int trainingCells = std::accumulate(
                trainingCellUsed.begin(), trainingCellUsed.end(), 0
            );
            const int validationCells = std::accumulate(
                validationCellUsed.begin(), validationCellUsed.end(), 0
            );
            if (trainingPixels < 240 || validationPixels < 60
                || trainingCells < 12 || validationCells < 4) {
                std::fprintf(
                    stderr,
                    "[PanoWizard] Local radiometry %d-%d: rejected support "
                    "train=%d/%d-cells validation=%d/%d-cells\n",
                    first, second, trainingPixels, trainingCells,
                    validationPixels, validationCells
                );
                continue;
            }

            cv::Mat firstFloat;
            cv::Mat secondFloat;
            images[first].convertTo(firstFloat, CV_32FC3);
            images[second].convertTo(secondFloat, CV_32FC3);
            cv::Mat rawDifference = secondFloat - firstFloat;
            cv::max(
                rawDifference, cv::Scalar(-40, -40, -40), rawDifference
            );
            cv::min(
                rawDifference, cv::Scalar(40, 40, 40), rawDifference
            );
            cv::Mat trainingWeight;
            training.convertTo(trainingWeight, CV_32F, 1.0 / 255.0);
            cv::Mat denominator = trialPeriodicBlur(
                trainingWeight, fieldSigma
            );
            cv::Mat confidence = denominator / 0.06;
            cv::max(confidence, 0.0, confidence);
            cv::min(confidence, 1.0, confidence);
            cv::Mat safeDenominator;
            cv::max(denominator, 1e-4, safeDenominator);
            std::vector<cv::Mat> differenceChannels;
            cv::split(rawDifference, differenceChannels);
            std::vector<cv::Mat> fieldChannels;
            for (int channel = 0; channel < 3; ++channel) {
                cv::Mat numerator = trialPeriodicBlur(
                    differenceChannels[channel].mul(trainingWeight), fieldSigma
                );
                cv::Mat field = numerator / safeDenominator;
                cv::max(field, -24.0, field);
                cv::min(field, 24.0, field);
                fieldChannels.push_back(std::move(field));
            }
            cv::Mat field;
            cv::merge(fieldChannels, field);
            cv::Mat active = seamWeight.mul(confidence);
            std::vector<cv::Mat> activeChannels(3, active);
            cv::Mat colorActive;
            cv::merge(activeChannels, colorActive);
            cv::Mat firstCorrection = 0.5 * field.mul(colorActive);
            cv::max(
                firstCorrection, cv::Scalar(-12, -12, -12), firstCorrection
            );
            cv::min(
                firstCorrection, cv::Scalar(12, 12, 12), firstCorrection
            );

            std::vector<double> beforeValues;
            std::vector<double> afterValues;
            beforeValues.reserve(size_t(validationPixels) * 3);
            afterValues.reserve(size_t(validationPixels) * 3);
            double maximumCorrection = 0.0;
            for (int y = 0; y < analysisHeight; ++y) {
                const unsigned char *validationRow =
                    validation.ptr<unsigned char>(y);
                const cv::Vec3f *differenceRow =
                    rawDifference.ptr<cv::Vec3f>(y);
                const cv::Vec3f *correctionRow =
                    firstCorrection.ptr<cv::Vec3f>(y);
                for (int x = 0; x < analysisWidth; ++x) {
                    for (int channel = 0; channel < 3; ++channel) {
                        maximumCorrection = std::max(
                            maximumCorrection,
                            std::abs(double(correctionRow[x][channel]))
                        );
                        if (!validationRow[x]) continue;
                        beforeValues.push_back(std::abs(
                            double(differenceRow[x][channel])
                        ));
                        afterValues.push_back(std::abs(
                            double(differenceRow[x][channel]
                                - 2.0f * correctionRow[x][channel])
                        ));
                    }
                }
            }
            const double medianBefore = trialMedian(beforeValues);
            const double medianAfter = trialMedian(afterValues);
            const double p90Before = trialPercentile(beforeValues, 0.90);
            const double p90After = trialPercentile(afterValues, 0.90);
            const double meanBefore = std::accumulate(
                beforeValues.begin(), beforeValues.end(), 0.0
            ) / beforeValues.size();
            const double meanAfter = std::accumulate(
                afterValues.begin(), afterValues.end(), 0.0
            ) / afterValues.size();
            const bool improved = medianBefore >= 1.0
                && medianAfter <= medianBefore - 0.75
                && medianAfter <= 0.85 * medianBefore
                && p90After <= 0.95 * p90Before
                && p90After <= 12.0
                && meanAfter <= 0.85 * meanBefore
                && maximumCorrection < 10.0;
            if (!improved) {
                std::fprintf(
                    stderr,
                    "[PanoWizard] Local radiometry %d-%d: rejected validation "
                    "median=%.3f->%.3f p90=%.3f->%.3f mean=%.3f->%.3f "
                    "max-source=%.3f\n",
                    first, second, medianBefore, medianAfter,
                    p90Before, p90After, meanBefore, meanAfter,
                    maximumCorrection
                );
                continue;
            }

            cv::Mat firstOwnership;
            cv::Mat secondOwnership;
            firstOwner.convertTo(firstOwnership, CV_32F, 1.0 / 255.0);
            secondOwner.convertTo(secondOwnership, CV_32F, 1.0 / 255.0);
            const double ownershipSigma = std::max(
                6.0, analysisWidth / 32.0
            );
            firstOwnership = trialPeriodicBlur(
                firstOwnership, ownershipSigma
            );
            secondOwnership = trialPeriodicBlur(
                secondOwnership, ownershipSigma
            );
            cv::Mat ownershipTotal = firstOwnership + secondOwnership;
            cv::Mat safeOwnershipTotal;
            cv::max(ownershipTotal, 1e-4, safeOwnershipTotal);
            cv::Mat secondFraction = secondOwnership / safeOwnershipTotal;
            cv::Mat ownershipFactor = 1.0 - 2.0 * secondFraction;
            std::vector<cv::Mat> ownershipChannels(3, ownershipFactor);
            cv::Mat colorOwnership;
            cv::merge(ownershipChannels, colorOwnership);
            cv::Mat pairCorrection = firstCorrection.mul(colorOwnership);
            pairCorrection.setTo(
                cv::Scalar(0, 0, 0), ownershipTotal < 0.02
            );
            correctionSum += pairCorrection;
            correctionWeight += active;
            double maximumApplied = 0.0;
            for (int y = 0; y < analysisHeight; ++y) {
                const cv::Vec3f *row = pairCorrection.ptr<cv::Vec3f>(y);
                for (int x = 0; x < analysisWidth; ++x) {
                    for (int channel = 0; channel < 3; ++channel) {
                        maximumApplied = std::max(
                            maximumApplied,
                            std::abs(double(row[x][channel]))
                        );
                    }
                }
            }
            acceptedPairs.push_back({
                first, second, trainingPixels, validationPixels,
                trainingCells, validationCells,
                medianBefore, medianAfter, p90Before, p90After,
                maximumApplied
            });
            std::fprintf(
                stderr,
                "[PanoWizard] Local radiometry %d-%d: accepted "
                "train=%d/%d-cells validation=%d/%d-cells "
                "median=%.3f->%.3f p90=%.3f->%.3f max=%.3f\n",
                first, second, trainingPixels, trainingCells,
                validationPixels, validationCells,
                medianBefore, medianAfter, p90Before, p90After,
                maximumApplied
            );
        }
    }
    if (acceptedPairs.empty()) return cv::Mat();

    cv::Mat normalization;
    cv::max(correctionWeight, 1.0, normalization);
    std::vector<cv::Mat> normalizationChannels(3, normalization);
    cv::Mat colorNormalization;
    cv::merge(normalizationChannels, colorNormalization);
    cv::Mat correction = correctionSum / colorNormalization;
    cv::max(correction, cv::Scalar(-12, -12, -12), correction);
    cv::min(correction, cv::Scalar(12, 12, 12), correction);
    cv::resize(
        correction, correction, labels.size(), 0.0, 0.0, cv::INTER_CUBIC
    );
    double maximumApplied = 0.0;
    for (int y = 0; y < correction.rows; ++y) {
        const cv::Vec3f *row = correction.ptr<cv::Vec3f>(y);
        for (int x = 0; x < correction.cols; ++x) {
            for (int channel = 0; channel < 3; ++channel) {
                maximumApplied = std::max(
                    maximumApplied, std::abs(double(row[x][channel]))
                );
            }
        }
    }
    std::fprintf(
        stderr,
        "[PanoWizard] Local radiometry applied pairs=%zu max=%.3f\n",
        acceptedPairs.size(), maximumApplied
    );
    return correction;
}

std::pair<double, int> trialRender(
    const std::vector<TrialSource> &sources,
    const std::vector<unsigned char> &compositionRoles,
    const TrialAlignment &alignment,
    const cv::Mat &detectedOpticalMask,
    const std::string &outputPath,
    int width
) {
    const int height = width / 2;
    cv::Mat fittedMask = trialFittedOpticalMask(
        sources.front().image.size(), alignment.lens
    );
    cv::Mat opticalMask;
    cv::bitwise_and(detectedOpticalMask, fittedMask, opticalMask);
    const int horizontalViews = int(std::count_if(
        alignment.rotations.begin(), alignment.rotations.end(),
        [](const cv::Matx33d &rotation) {
            const cv::Vec3d axis = rotation * cv::Vec3d(0.0, 0.0, 1.0);
            return std::abs(axis[1]) < 0.65;
        }
    ));
    std::vector<TrialWarp> warps;
    for (int index = 0; index < int(sources.size()); ++index) {
        trialCheckCancellation();
        trialReport(
            "Projicerar källbilder…",
            0.62 + 0.14 * double(index) / double(sources.size())
        );
        cv::Mat validSource;
        cv::bitwise_and(opticalMask, sources[index].userMask, validSource);
        cv::Mat mapX;
        cv::Mat mapY;
        TrialWarp warp;
        const cv::Vec3d opticalAxis =
            alignment.rotations[index] * cv::Vec3d(0.0, 0.0, 1.0);
        const bool automaticNadirFill = compositionRoles[index] == 0
            && horizontalViews >= 3 && opticalAxis[1] < -0.8;
        warp.fillOnly = compositionRoles[index] == 2 || automaticNadirFill;
        trialMapping(
            width, height, alignment.rotations[index], sources[index].image.size(),
            alignment.lens, validSource, mapX, mapY, warp.mask, warp.score
        );
        cv::Mat gained = sources[index].image.clone();
        for (int y = 0; y < gained.rows; ++y) {
            cv::Vec3b *row = gained.ptr<cv::Vec3b>(y);
            for (int x = 0; x < gained.cols; ++x) {
                for (int channel = 0; channel < 3; ++channel) {
                    row[x][channel] = cv::saturate_cast<unsigned char>(
                        row[x][channel] * alignment.gains.at<double>(index, channel)
                    );
                }
            }
        }
        cv::remap(
            gained, warp.image, mapX, mapY, cv::INTER_LANCZOS4,
            cv::BORDER_CONSTANT, cv::Scalar(0, 0, 0)
        );
        cv::remap(
            sources[index].protectedMask, warp.protectedMask, mapX, mapY,
            cv::INTER_NEAREST, cv::BORDER_CONSTANT, cv::Scalar(0)
        );
        cv::bitwise_and(warp.protectedMask, warp.mask, warp.protectedMask);
        warps.push_back(std::move(warp));
    }
    trialReport("Matchar exponering och färg…", 0.78);
    warps = trialCompensateRadiometry(warps, width);
    std::vector<cv::Mat> redundantMasks = trialSuppressRedundantViews(
        alignment.rotations, warps
    );
    for (int index = 0; index < int(warps.size()); ++index) {
        if (warps[index].fillOnly) {
            redundantMasks[index] = warps[index].protectedMask.clone();
        }
    }
    const std::vector<cv::Mat> seamMasks = trialPreferCentralCoverage(
        warps, redundantMasks
    );
    trialReport("Beräknar sömmar…", 0.87);
    cv::Mat conflictMask;
    cv::Mat labels = trialGraphCutLabels(
        warps, seamMasks, width, height, conflictMask
    );
    const int holes = cv::countNonZero(labels < 0);
    const double coverage = 100.0 * (1.0 - holes / double(width * height));
    const cv::Mat localRadiometryCorrection =
        trialSeamLocalRadiometryCorrection(warps, labels, width);
    trialReport("Blandar originalpixlar…", 0.94);
    cv::Mat result = trialContentAdaptiveBlend(
        warps, labels, conflictMask, width, height
    );
    if (!localRadiometryCorrection.empty()) {
        cv::Mat floatResult;
        result.convertTo(floatResult, CV_32FC3);
        floatResult += localRadiometryCorrection;
        cv::max(floatResult, cv::Scalar(0, 0, 0), floatResult);
        cv::min(floatResult, cv::Scalar(255, 255, 255), floatResult);
        floatResult.convertTo(result, CV_8UC3);
    }
    cv::flip(result, result, 1);
    const std::vector<int> parameters = {
        cv::IMWRITE_JPEG_QUALITY, 96,
        cv::IMWRITE_JPEG_OPTIMIZE, 1
    };
    if (!cv::imwrite(outputPath, result, parameters)) {
        throw std::runtime_error("Trial-motorn kunde inte skriva panoramabilden.");
    }
    return {coverage, holes};
}

} // namespace

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
) {
    trialCallbacks = {callbackContext, progressCallback, cancellationCallback};
    struct CallbackReset {
        ~CallbackReset() { trialCallbacks = {}; }
    } callbackReset;
    try {
        if (imagePaths == nullptr || outputPath == nullptr || imageCount < 2) {
            throw std::runtime_error("Trial-motorn kräver minst två källbilder.");
        }
        if (outputWidth < 512 || outputWidth % 2 != 0) {
            throw std::runtime_error("Panoramabredden måste vara ett jämnt tal på minst 512 pixlar.");
        }
        std::vector<TrialSource> sources;
        std::vector<unsigned char> resolvedRoles(imageCount, 0);
        for (int index = 0; index < imageCount; ++index) {
            trialReport(
                "Läser källbilder…",
                0.08 + 0.08 * double(index) / double(imageCount)
            );
            if (imagePaths[index] == nullptr) {
                throw std::runtime_error("En källbild saknar sökväg.");
            }
            sources.push_back(trialReadSource(
                imagePaths[index],
                protectedMaskPaths == nullptr ? nullptr : protectedMaskPaths[index]
            ));
            if (compositionRoles != nullptr) {
                resolvedRoles[index] = std::min<unsigned char>(
                    compositionRoles[index], 2
                );
            }
            if (index > 0 && sources[index].image.size() != sources[0].image.size()) {
                throw std::runtime_error("Trial-motorn kräver källbilder med samma pixelmått.");
            }
        }
        trialReport("Analyserar objektivets bildcirkel…", 0.17);
        const TrialOpticalSupport optical = trialCommonValidMask(sources);
        TrialAlignment alignment;
        const std::string cachePath = alignmentCachePath == nullptr
            ? std::string() : std::string(alignmentCachePath);
        const bool usedCache = trialLoadCache(
            cachePath, imageCount, sources.front().image.size(), alignment
        );
        if (!usedCache) {
            const double scale = std::hypot(
                sources.front().image.cols, sources.front().image.rows
            ) / 2.0;
            const double initialK1 = optical.circular
                ? (trialPi / 2.0) / (optical.radius / scale)
                : trialPi / 2.0;
            TrialLens initialLens;
            initialLens.k1 = initialK1;
            initialLens.cx = sources.front().image.cols / 2.0;
            initialLens.cy = sources.front().image.rows / 2.0;
            trialReport("Detekterar bildfeatures…", 0.23);
            const std::vector<TrialFeatures> features = trialExtractFeatures(
                sources, optical.mask
            );
            trialReport("Matchar överlappande bilder…", 0.35);
            const TrialEdgeSets edgeSets = trialBuildEdges(
                sources, features, initialLens
            );
            const std::vector<TrialEdge> &edges = edgeSets.strong;
            if (trialConnected(imageCount, edges)) {
                trialDetectSupplementalViews(
                    resolvedRoles,
                    trialInitialRotations(imageCount, edges)
                );
            }

            std::vector<int> ringIndices;
            std::vector<TrialSource> ringSources;
            for (int index = 0; index < imageCount; ++index) {
                if (resolvedRoles[index] == 2) continue;
                ringIndices.push_back(index);
                ringSources.push_back(sources[index]);
            }
            if (ringIndices.size() < 2) {
                throw std::runtime_error(
                    "Panoramaringen kräver minst två bilder."
                );
            }
            const std::vector<TrialEdge> ringEdges = trialSubsetEdges(
                edges, ringIndices, imageCount
            );
            const std::vector<TrialEdge> weakRingEdges = trialSubsetEdges(
                edgeSets.weak, ringIndices, imageCount
            );
            if (!trialConnected(int(ringIndices.size()), ringEdges)) {
                throw std::runtime_error(
                    "Panoramaringen är inte sammanhängande. Reparationsbilder används inte för att överbrygga saknat ringöverlapp."
                );
            }
            const std::vector<cv::Matx33d> initialRotations =
                trialInitialRotations(int(ringIndices.size()), ringEdges);
            trialReport("Optimerar kameror och linsmodell…", 0.46);
            TrialAlignment ringAlignment = trialOptimizeGeometry(
                ringSources, ringEdges, weakRingEdges,
                initialRotations, initialLens,
                optical.circular, optical.radius
            );

            alignment = ringAlignment;
            alignment.rotations.assign(imageCount, cv::Matx33d::eye());
            for (int index = 0; index < int(ringIndices.size()); ++index) {
                alignment.rotations[ringIndices[index]] =
                    ringAlignment.rotations[index];
            }
            for (int index = 0; index < imageCount; ++index) {
                if (resolvedRoles[index] != 2) continue;
                alignment.rotations[index] = trialRegisterSupplementalView(
                    index, ringIndices, ringAlignment.rotations, edges,
                    sources.front().image.size(), ringAlignment.lens
                );
            }
            trialReport("Rätar upp horisonten…", 0.56);
            const std::vector<cv::Matx33d> leveledRing = trialLevelRotations(
                ringAlignment.rotations
            );
            const cv::Matx33d leveling =
                leveledRing.front() * ringAlignment.rotations.front().t();
            for (cv::Matx33d &rotation : alignment.rotations) {
                rotation = leveling * rotation;
            }
            alignment.gains = trialExposureGains(sources, edges);
            trialSaveCache(cachePath, alignment, sources.front().image.size());
        } else {
            trialReport("Använder sparad bildjustering…", 0.58);
        }
        trialDetectSupplementalViews(resolvedRoles, alignment.rotations);
        const auto [coverage, holes] = trialRender(
            sources, resolvedRoles, alignment, optical.mask,
            outputPath, outputWidth
        );
        if (report != nullptr) {
            report->coveragePercent = coverage;
            report->holeCount = holes;
            report->usedAlignmentCache = usedCache ? 1 : 0;
        }
        if (errorMessage != nullptr) *errorMessage = nullptr;
        trialReport("Panoramat är klart", 1.0);
        return 1;
    } catch (const cv::Exception &error) {
        trialSetError(errorMessage, "OpenCV: " + std::string(error.what()));
    } catch (const std::exception &error) {
        trialSetError(errorMessage, error.what());
    } catch (...) {
        trialSetError(errorMessage, "Trial-motorn misslyckades av okänd orsak.");
    }
    return 0;
}

void PWFreeString(char *string) {
    std::free(string);
}
