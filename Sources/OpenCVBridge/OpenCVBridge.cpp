#include "OpenCVBridge.h"

#include <cstdlib>
#include <cstring>
#include <exception>
#include <limits>
#include <string>
#include <vector>

#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/features2d.hpp>
#include <opencv2/calib3d.hpp>
#include <opencv2/stitching.hpp>
#include <opencv2/stitching/detail/matchers.hpp>

namespace {

void setError(char **errorMessage, const std::string &message) {
    if (errorMessage == nullptr) {
        return;
    }
    *errorMessage = static_cast<char *>(std::malloc(message.size() + 1));
    if (*errorMessage != nullptr) {
        std::memcpy(*errorMessage, message.c_str(), message.size() + 1);
    }
}

std::string statusMessage(cv::Stitcher::Status status) {
    switch (status) {
        case cv::Stitcher::ERR_NEED_MORE_IMGS:
            return "OpenCV behöver fler överlappande bilder.";
        case cv::Stitcher::ERR_HOMOGRAPHY_EST_FAIL:
            return "OpenCV kunde inte passa ihop bildernas kontrollpunkter.";
        case cv::Stitcher::ERR_CAMERA_PARAMS_ADJUST_FAIL:
            return "OpenCV kunde inte beräkna kamerornas positioner.";
        case cv::Stitcher::OK:
            return "";
    }
    return "OpenCV misslyckades med ett okänt fel.";
}

std::string filename(const char *path) {
    const std::string value(path);
    const std::size_t separator = value.find_last_of('/');
    return separator == std::string::npos ? value : value.substr(separator + 1);
}

cv::Mat fisheyeToRectilinear(const cv::Mat &source) {
    constexpr int outputWidth = 1'000;
    constexpr int outputHeight = 1'400;
    constexpr double horizontalFieldOfView = 105.0 * CV_PI / 180.0;

    const double sourceCenterX = (source.cols - 1) * 0.5;
    const double sourceCenterY = (source.rows - 1) * 0.5;
    const double sourceDiagonalRadius = std::hypot(source.cols, source.rows) * 0.5;
    const double focal = outputWidth / (2.0 * std::tan(horizontalFieldOfView * 0.5));
    const double outputCenterX = (outputWidth - 1) * 0.5;
    const double outputCenterY = (outputHeight - 1) * 0.5;
    const double equisolidScale = sourceDiagonalRadius / std::sin(CV_PI * 0.25);

    cv::Mat mapX(outputHeight, outputWidth, CV_32F);
    cv::Mat mapY(outputHeight, outputWidth, CV_32F);

    for (int y = 0; y < outputHeight; ++y) {
        float *mapXRow = mapX.ptr<float>(y);
        float *mapYRow = mapY.ptr<float>(y);
        const double rayY = (y - outputCenterY) / focal;

        for (int x = 0; x < outputWidth; ++x) {
            const double rayX = (x - outputCenterX) / focal;
            const double radial = std::hypot(rayX, rayY);
            if (radial < 1e-9) {
                mapXRow[x] = static_cast<float>(sourceCenterX);
                mapYRow[x] = static_cast<float>(sourceCenterY);
                continue;
            }

            const double theta = std::atan(radial);
            const double sourceRadius = equisolidScale * std::sin(theta * 0.5);
            mapXRow[x] = static_cast<float>(
                sourceCenterX + sourceRadius * rayX / radial
            );
            mapYRow[x] = static_cast<float>(
                sourceCenterY + sourceRadius * rayY / radial
            );
        }
    }

    cv::Mat result;
    cv::remap(
        source,
        result,
        mapX,
        mapY,
        cv::INTER_LANCZOS4,
        cv::BORDER_CONSTANT
    );
    return result;
}

bool writeJPEG(
    const cv::Mat &image,
    const char *outputPath,
    char **errorMessage
) {
    const std::vector<int> parameters = {
        cv::IMWRITE_JPEG_QUALITY,
        92
    };
    if (!cv::imwrite(outputPath, image, parameters)) {
        setError(errorMessage, "Kunde inte skriva det reparerade panoramat.");
        return false;
    }
    return true;
}

bool repairFromNearbyTexture(
    const cv::Mat &view,
    const cv::Mat &holeMask,
    cv::Mat &result
) {
    std::vector<cv::Point> holePoints;
    cv::findNonZero(holeMask, holePoints);
    if (holePoints.empty()) {
        result = view.clone();
        return true;
    }

    int minimumX = view.cols;
    int minimumY = view.rows;
    int maximumX = 0;
    int maximumY = 0;
    for (const cv::Point &point : holePoints) {
        minimumX = std::min(minimumX, point.x);
        minimumY = std::min(minimumY, point.y);
        maximumX = std::max(maximumX, point.x);
        maximumY = std::max(maximumY, point.y);
    }
    cv::Rect bounds(
        minimumX,
        minimumY,
        maximumX - minimumX + 1,
        maximumY - minimumY + 1
    );
    constexpr int margin = 16;
    bounds.x = std::max(bounds.x - margin, 0);
    bounds.y = std::max(bounds.y - margin, 0);
    bounds.width = std::min(bounds.width + margin * 2, view.cols - bounds.x);
    bounds.height = std::min(bounds.height + margin * 2, view.rows - bounds.y);

    if (bounds.width > view.cols * 0.45 || bounds.height > view.rows * 0.45) {
        return false;
    }

    cv::Mat widerMask;
    cv::dilate(
        holeMask,
        widerMask,
        cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(41, 41))
    );
    cv::Mat boundaryMask;
    cv::subtract(widerMask, holeMask, boundaryMask);
    const cv::Mat targetPatch = view(bounds);
    const cv::Mat targetBoundary = boundaryMask(bounds);

    double bestScore = std::numeric_limits<double>::max();
    cv::Rect bestCandidate;
    constexpr int searchStep = 8;

    for (int y = 0; y + bounds.height <= view.rows; y += searchStep) {
        for (int x = 0; x + bounds.width <= view.cols; x += searchStep) {
            const cv::Rect candidate(x, y, bounds.width, bounds.height);
            if ((candidate & bounds).area() > 0
                || cv::countNonZero(holeMask(candidate)) > 0) {
                continue;
            }

            const double score = cv::norm(
                targetPatch,
                view(candidate),
                cv::NORM_L1,
                targetBoundary
            );
            if (score < bestScore) {
                bestScore = score;
                bestCandidate = candidate;
            }
        }
    }

    if (bestCandidate.area() == 0) {
        return false;
    }

    result = view.clone();
    view(bestCandidate).copyTo(result(bounds), holeMask(bounds));
    return true;
}

} // namespace

bool PWStitchImages(
    const char * const *inputPaths,
    int inputCount,
    bool fisheyeInput,
    const char *outputPath,
    char **errorMessage
) {
    if (errorMessage != nullptr) {
        *errorMessage = nullptr;
    }
    if (inputPaths == nullptr || inputCount < 2 || outputPath == nullptr) {
        setError(errorMessage, "Minst två bilder krävs för sammanfogning.");
        return false;
    }

    try {
        std::vector<cv::Mat> images;
        images.reserve(static_cast<std::size_t>(inputCount));
        for (int index = 0; index < inputCount; ++index) {
            cv::Mat image = cv::imread(inputPaths[index], cv::IMREAD_COLOR);
            if (image.empty()) {
                setError(
                    errorMessage,
                    std::string("Kunde inte läsa bild: ") + inputPaths[index]
                );
                return false;
            }
            images.push_back(
                fisheyeInput ? fisheyeToRectilinear(image) : std::move(image)
            );
        }

        cv::Mat panorama;
        cv::Ptr<cv::Stitcher> stitcher = cv::Stitcher::create(cv::Stitcher::PANORAMA);
        stitcher->setRegistrationResol(1.5);
        stitcher->setFeaturesFinder(cv::SIFT::create(8'000));
        stitcher->setFeaturesMatcher(
            cv::makePtr<cv::detail::BestOf2NearestMatcher>(
                false,
                0.3f,
                6,
                6,
                10.0
            )
        );
        stitcher->setPanoConfidenceThresh(0.3);
        stitcher->setWaveCorrection(true);
        stitcher->setWaveCorrectKind(cv::detail::WAVE_CORRECT_HORIZ);

        cv::Stitcher::Status status = stitcher->estimateTransform(images);
        if (status != cv::Stitcher::OK) {
            setError(errorMessage, statusMessage(status));
            return false;
        }

        const std::vector<int> component = stitcher->component();
        if (component.size() != images.size()) {
            std::vector<bool> included(images.size(), false);
            for (int index : component) {
                if (index >= 0 && index < inputCount) {
                    included[static_cast<std::size_t>(index)] = true;
                }
            }

            std::string message = "Kunde inte matcha följande bilder med panoramat: ";
            bool needsSeparator = false;
            for (int index = 0; index < inputCount; ++index) {
                if (!included[static_cast<std::size_t>(index)]) {
                    if (needsSeparator) {
                        message += ", ";
                    }
                    message += filename(inputPaths[index]);
                    needsSeparator = true;
                }
            }
            message += ". Kontrollera att bilderna överlappar angränsande bilder.";
            setError(errorMessage, message);
            return false;
        }

        status = stitcher->composePanorama(panorama);
        if (status != cv::Stitcher::OK) {
            setError(errorMessage, statusMessage(status));
            return false;
        }

        const int canvasWidth = std::max(panorama.cols, panorama.rows * 2);
        const int canvasHeight = canvasWidth / 2;
        cv::Mat equirectangular(
            canvasHeight,
            canvasWidth,
            panorama.type(),
            cv::Scalar::all(0)
        );

        cv::Mat fittedPanorama = panorama;
        if (panorama.rows > canvasHeight) {
            const double scale = static_cast<double>(canvasHeight) / panorama.rows;
            cv::resize(
                panorama,
                fittedPanorama,
                cv::Size(),
                scale,
                scale,
                cv::INTER_AREA
            );
        }

        const int x = (canvasWidth - fittedPanorama.cols) / 2;
        const int y = (canvasHeight - fittedPanorama.rows) / 2;
        fittedPanorama.copyTo(
            equirectangular(
                cv::Rect(x, y, fittedPanorama.cols, fittedPanorama.rows)
            )
        );

        if (!cv::imwrite(outputPath, equirectangular)) {
            setError(errorMessage, "Kunde inte skriva panoramabilden.");
            return false;
        }
        return true;
    } catch (const cv::Exception &exception) {
        setError(errorMessage, exception.what());
        return false;
    } catch (const std::exception &exception) {
        setError(errorMessage, exception.what());
        return false;
    }
}

bool PWRepairNadir(
    const char *inputPath,
    const char *outputPath,
    char **errorMessage
) {
    if (errorMessage != nullptr) {
        *errorMessage = nullptr;
    }
    if (inputPath == nullptr || outputPath == nullptr) {
        setError(errorMessage, "Sökväg saknas för nadirreparation.");
        return false;
    }

    try {
        cv::Mat source = cv::imread(inputPath, cv::IMREAD_UNCHANGED);
        if (source.empty()) {
            setError(errorMessage, "Kunde inte läsa panoramat för nadirreparation.");
            return false;
        }

        cv::Mat color;
        cv::Mat alpha;
        if (source.channels() == 4) {
            cv::cvtColor(source, color, cv::COLOR_BGRA2BGR);
            std::vector<cv::Mat> channels;
            cv::split(source, channels);
            alpha = channels[3];
        } else if (source.channels() == 3) {
            color = source;
            alpha = cv::Mat(source.rows, source.cols, CV_8U, cv::Scalar(255));
        } else {
            setError(errorMessage, "Panoramat har ett okänt pixelformat.");
            return false;
        }

        constexpr int viewSize = 1'200;
        constexpr double fieldOfView = 110.0 * CV_PI / 180.0;
        const double tangentLimit = std::tan(fieldOfView * 0.5);
        const double viewCenter = (viewSize - 1) * 0.5;

        cv::Mat mapX(viewSize, viewSize, CV_32F);
        cv::Mat mapY(viewSize, viewSize, CV_32F);
        for (int y = 0; y < viewSize; ++y) {
            float *mapXRow = mapX.ptr<float>(y);
            float *mapYRow = mapY.ptr<float>(y);
            const double planeY = (y - viewCenter) / viewCenter * tangentLimit;

            for (int x = 0; x < viewSize; ++x) {
                const double planeX = (x - viewCenter) / viewCenter * tangentLimit;
                const double length = std::sqrt(
                    planeX * planeX + planeY * planeY + 1.0
                );
                const double worldX = planeX / length;
                const double worldY = planeY / length;
                const double worldZ = -1.0 / length;
                const double longitude = std::atan2(worldX, worldY);
                const double latitude = std::asin(worldZ);

                mapXRow[x] = static_cast<float>(
                    (longitude / (2.0 * CV_PI) + 0.5) * color.cols
                );
                mapYRow[x] = static_cast<float>(
                    std::min(
                        (0.5 - latitude / CV_PI) * color.rows,
                        static_cast<double>(color.rows - 1)
                    )
                );
            }
        }

        cv::Mat nadirView;
        cv::Mat nadirAlpha;
        cv::remap(
            color,
            nadirView,
            mapX,
            mapY,
            cv::INTER_LANCZOS4,
            cv::BORDER_WRAP
        );
        cv::remap(
            alpha,
            nadirAlpha,
            mapX,
            mapY,
            cv::INTER_LINEAR,
            cv::BORDER_WRAP
        );

        cv::Mat holeMask;
        cv::threshold(nadirAlpha, holeMask, 250, 255, cv::THRESH_BINARY_INV);
        const int holePixels = cv::countNonZero(holeMask);
        if (holePixels == 0) {
            return writeJPEG(color, outputPath, errorMessage);
        }
        if (holePixels > viewSize * viewSize / 5) {
            setError(
                errorMessage,
                "Nadirfläcken är för stor för en säker automatisk reparation."
            );
            return false;
        }

        cv::Mat expandedMask;
        cv::dilate(
            holeMask,
            expandedMask,
            cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(15, 15))
        );

        cv::Mat repairedView;
        if (!repairFromNearbyTexture(nadirView, expandedMask, repairedView)) {
            setError(
                errorMessage,
                "Ingen tillförlitlig markyta hittades för nadirreparation."
            );
            return false;
        }

        cv::Mat featherMask;
        cv::dilate(
            expandedMask,
            featherMask,
            cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(21, 21))
        );
        cv::GaussianBlur(
            featherMask,
            featherMask,
            cv::Size(0, 0),
            8.0
        );

        const int repairTop = color.rows / 2;
        const int repairHeight = color.rows - repairTop;
        cv::Mat inverseMapX(repairHeight, color.cols, CV_32F);
        cv::Mat inverseMapY(repairHeight, color.cols, CV_32F);

        for (int row = 0; row < repairHeight; ++row) {
            float *inverseXRow = inverseMapX.ptr<float>(row);
            float *inverseYRow = inverseMapY.ptr<float>(row);
            const int panoramaY = repairTop + row;
            const double latitude = CV_PI * (
                0.5 - (panoramaY + 0.5) / color.rows
            );
            const double horizontal = std::cos(latitude);
            const double worldZ = std::sin(latitude);

            for (int x = 0; x < color.cols; ++x) {
                const double longitude = 2.0 * CV_PI * (
                    (x + 0.5) / color.cols - 0.5
                );
                const double worldX = horizontal * std::sin(longitude);
                const double worldY = horizontal * std::cos(longitude);
                const double denominator = -worldZ;
                const double planeX = worldX / denominator;
                const double planeY = worldY / denominator;

                inverseXRow[x] = static_cast<float>(
                    planeX / tangentLimit * viewCenter + viewCenter
                );
                inverseYRow[x] = static_cast<float>(
                    planeY / tangentLimit * viewCenter + viewCenter
                );
            }
        }

        cv::Mat repairedStrip;
        cv::Mat weightStrip;
        cv::remap(
            repairedView,
            repairedStrip,
            inverseMapX,
            inverseMapY,
            cv::INTER_LANCZOS4,
            cv::BORDER_CONSTANT
        );
        cv::remap(
            featherMask,
            weightStrip,
            inverseMapX,
            inverseMapY,
            cv::INTER_LINEAR,
            cv::BORDER_CONSTANT
        );

        cv::Mat destination = color.clone();
        cv::Mat destinationStrip = destination.rowRange(repairTop, color.rows);
        for (int y = 0; y < repairHeight; ++y) {
            const cv::Vec3b *repairRow = repairedStrip.ptr<cv::Vec3b>(y);
            const uchar *weightRow = weightStrip.ptr<uchar>(y);
            cv::Vec3b *destinationRow = destinationStrip.ptr<cv::Vec3b>(y);

            for (int x = 0; x < color.cols; ++x) {
                const double weight = weightRow[x] / 255.0;
                if (weight <= 0.0) {
                    continue;
                }
                for (int channel = 0; channel < 3; ++channel) {
                    destinationRow[x][channel] = cv::saturate_cast<uchar>(
                        destinationRow[x][channel] * (1.0 - weight)
                            + repairRow[x][channel] * weight
                    );
                }
            }
        }

        return writeJPEG(destination, outputPath, errorMessage);
    } catch (const cv::Exception &exception) {
        setError(errorMessage, exception.what());
        return false;
    } catch (const std::exception &exception) {
        setError(errorMessage, exception.what());
        return false;
    }
}

void PWFreeString(char *string) {
    std::free(string);
}

bool PWApplyPanoramaRepair(
    const char *panoramaPath,
    const char *repairImagePath,
    const char *maskPath,
    const char *outputPath,
    char **errorMessage
) {
    if (errorMessage != nullptr) {
        *errorMessage = nullptr;
    }
    try {
        cv::Mat panorama = cv::imread(panoramaPath, cv::IMREAD_COLOR);
        cv::Mat repair = cv::imread(repairImagePath, cv::IMREAD_COLOR);
        cv::Mat paintedMask = cv::imread(maskPath, cv::IMREAD_UNCHANGED);
        if (panorama.empty() || repair.empty() || paintedMask.empty()) {
            setError(errorMessage, "Kunde inte läsa panorama, reparationsbild eller mask.");
            return false;
        }

        constexpr int viewSize = 1400;
        constexpr double fieldOfView = 120.0 * CV_PI / 180.0;
        const double tangentLimit = std::tan(fieldOfView * 0.5);
        const double center = (viewSize - 1) * 0.5;
        cv::Mat panoMapX(viewSize, viewSize, CV_32F);
        cv::Mat panoMapY(viewSize, viewSize, CV_32F);
        for (int y = 0; y < viewSize; ++y) {
            float *mx = panoMapX.ptr<float>(y);
            float *my = panoMapY.ptr<float>(y);
            const double py = (y - center) / center * tangentLimit;
            for (int x = 0; x < viewSize; ++x) {
                const double px = (x - center) / center * tangentLimit;
                const double length = std::sqrt(px * px + py * py + 1.0);
                const double wx = px / length;
                const double wy = py / length;
                const double wz = -1.0 / length;
                const double longitude = std::atan2(wx, wy);
                const double latitude = std::asin(wz);
                mx[x] = static_cast<float>(
                    (longitude / (2.0 * CV_PI) + 0.5) * panorama.cols
                );
                my[x] = static_cast<float>(
                    (0.5 - latitude / CV_PI) * panorama.rows
                );
            }
        }
        cv::Mat nadirView;
        cv::remap(
            panorama, nadirView, panoMapX, panoMapY,
            cv::INTER_LANCZOS4, cv::BORDER_WRAP
        );

        const double sourceCenterX = (repair.cols - 1) * 0.5;
        const double sourceCenterY = (repair.rows - 1) * 0.5;
        const double diagonalRadius = std::hypot(repair.cols, repair.rows) * 0.5;
        const double equisolidScale = diagonalRadius / std::sin(CV_PI * 0.25);
        cv::Mat repairMapX(viewSize, viewSize, CV_32F);
        cv::Mat repairMapY(viewSize, viewSize, CV_32F);
        for (int y = 0; y < viewSize; ++y) {
            float *mx = repairMapX.ptr<float>(y);
            float *my = repairMapY.ptr<float>(y);
            const double ry = (y - center) / center * tangentLimit;
            for (int x = 0; x < viewSize; ++x) {
                const double rx = (x - center) / center * tangentLimit;
                const double radial = std::hypot(rx, ry);
                if (radial < 1e-9) {
                    mx[x] = static_cast<float>(sourceCenterX);
                    my[x] = static_cast<float>(sourceCenterY);
                } else {
                    const double theta = std::atan(radial);
                    const double radius = equisolidScale * std::sin(theta * 0.5);
                    mx[x] = static_cast<float>(sourceCenterX + radius * rx / radial);
                    my[x] = static_cast<float>(sourceCenterY + radius * ry / radial);
                }
            }
        }
        cv::Mat repairView;
        cv::remap(
            repair, repairView, repairMapX, repairMapY,
            cv::INTER_LANCZOS4, cv::BORDER_CONSTANT
        );
        cv::Mat exclusion;
        if (paintedMask.channels() == 4) {
            cv::Mat colorMask;
            cv::cvtColor(paintedMask, colorMask, cv::COLOR_BGRA2BGR);
            cv::cvtColor(colorMask, exclusion, cv::COLOR_BGR2GRAY);
        } else {
            cv::cvtColor(paintedMask, exclusion, cv::COLOR_BGR2GRAY);
        }
        cv::threshold(exclusion, exclusion, 1, 255, cv::THRESH_BINARY);
        cv::Mat exclusionView;
        cv::remap(
            exclusion, exclusionView, repairMapX, repairMapY,
            cv::INTER_LINEAR, cv::BORDER_CONSTANT, cv::Scalar(255)
        );
        cv::Mat keepMask;
        cv::bitwise_not(exclusionView, keepMask);

        auto sift = cv::SIFT::create(6000);
        std::vector<cv::KeyPoint> repairPoints;
        std::vector<cv::KeyPoint> panoPoints;
        cv::Mat repairDescriptors;
        cv::Mat panoDescriptors;
        // Registration deliberately sees the complete repair photograph.
        // The painted mask controls compositing only; it must not weaken geometry.
        sift->detectAndCompute(repairView, cv::noArray(), repairPoints, repairDescriptors);
        sift->detectAndCompute(nadirView, cv::noArray(), panoPoints, panoDescriptors);
        if (repairDescriptors.empty() || panoDescriptors.empty()) {
            setError(errorMessage, "Hittade inte tillräckligt med detaljer för nadirregistrering.");
            return false;
        }
        cv::BFMatcher matcher(cv::NORM_L2, true);
        std::vector<cv::DMatch> matches;
        matcher.match(repairDescriptors, panoDescriptors, matches);
        std::sort(matches.begin(), matches.end(), [](const auto &left, const auto &right) {
            return left.distance < right.distance;
        });
        if (matches.size() > 300) {
            matches.resize(300);
        }
        std::vector<cv::Point2f> from;
        std::vector<cv::Point2f> to;
        for (const auto &match : matches) {
            from.push_back(repairPoints[match.queryIdx].pt);
            to.push_back(panoPoints[match.trainIdx].pt);
        }
        if (from.size() < 8) {
            setError(errorMessage, "För få säkra matchningar för nadirbilden.");
            return false;
        }
        cv::Mat inliers;
        cv::Mat transform = cv::estimateAffinePartial2D(
            from, to, inliers, cv::RANSAC, 4.0, 4000, 0.995, 10
        );
        if (transform.empty() || cv::countNonZero(inliers) < 4) {
            setError(errorMessage, "Kunde inte registrera nadirbilden lokalt.");
            return false;
        }
        const double scale = std::hypot(
            transform.at<double>(0, 0),
            transform.at<double>(1, 0)
        );
        const cv::Point2d transformedCenter(
            transform.at<double>(0, 0) * center
                + transform.at<double>(0, 1) * center
                + transform.at<double>(0, 2),
            transform.at<double>(1, 0) * center
                + transform.at<double>(1, 1) * center
                + transform.at<double>(1, 2)
        );
        if (scale < 0.5 || scale > 2.0
            || transformedCenter.x < viewSize * 0.2
            || transformedCenter.x > viewSize * 0.8
            || transformedCenter.y < viewSize * 0.2
            || transformedCenter.y > viewSize * 0.8) {
            constexpr int searchSize = 350;
            cv::Mat repairGray;
            cv::Mat panoGray;
            cv::cvtColor(repairView, repairGray, cv::COLOR_BGR2GRAY);
            cv::cvtColor(nadirView, panoGray, cv::COLOR_BGR2GRAY);
            cv::resize(repairGray, repairGray, cv::Size(searchSize, searchSize));
            cv::resize(panoGray, panoGray, cv::Size(searchSize, searchSize));
            repairGray.convertTo(repairGray, CV_32F);
            panoGray.convertTo(panoGray, CV_32F);
            cv::Mat window;
            cv::createHanningWindow(window, repairGray.size(), CV_32F);

            double bestResponse = -1.0;
            double bestAngle = 0.0;
            double bestScale = 1.0;
            cv::Point2d bestShift;
            const cv::Point2f searchCenter(
                (searchSize - 1) * 0.5f,
                (searchSize - 1) * 0.5f
            );
            for (double candidateScale = 0.7; candidateScale <= 1.31;
                 candidateScale += 0.1) {
                for (double angle = -180.0; angle < 180.0; angle += 5.0) {
                    cv::Mat candidateTransform = cv::getRotationMatrix2D(
                        searchCenter, angle, candidateScale
                    );
                    cv::Mat candidate;
                    cv::warpAffine(
                        repairGray, candidate, candidateTransform,
                        repairGray.size(), cv::INTER_LINEAR, cv::BORDER_CONSTANT
                    );
                    double response = 0.0;
                    cv::Point2d shift = cv::phaseCorrelate(
                        candidate, panoGray, window, &response
                    );
                    if (response > bestResponse) {
                        bestResponse = response;
                        bestAngle = angle;
                        bestScale = candidateScale;
                        bestShift = shift;
                    }
                }
            }
            if (bestResponse < 0.02) {
                setError(errorMessage, "Kunde inte registrera nadirbilden lokalt.");
                return false;
            }
            transform = cv::getRotationMatrix2D(
                cv::Point2f(static_cast<float>(center), static_cast<float>(center)),
                bestAngle,
                bestScale
            );
            transform.at<double>(0, 2) += bestShift.x * viewSize / searchSize;
            transform.at<double>(1, 2) += bestShift.y * viewSize / searchSize;
        }
        cv::Mat warpedRepair;
        cv::Mat warpedKeep;
        cv::warpAffine(
            repairView, warpedRepair, transform, nadirView.size(),
            cv::INTER_LANCZOS4, cv::BORDER_CONSTANT
        );
        cv::warpAffine(
            keepMask, warpedKeep, transform, nadirView.size(),
            cv::INTER_LINEAR, cv::BORDER_CONSTANT
        );
        cv::GaussianBlur(warpedKeep, warpedKeep, cv::Size(0, 0), 3.0);
        cv::Mat repairedView = nadirView.clone();
        for (int y = 0; y < viewSize; ++y) {
            const cv::Vec3b *patch = warpedRepair.ptr<cv::Vec3b>(y);
            const uchar *alpha = warpedKeep.ptr<uchar>(y);
            cv::Vec3b *destination = repairedView.ptr<cv::Vec3b>(y);
            for (int x = 0; x < viewSize; ++x) {
                const double weight = alpha[x] / 255.0;
                for (int c = 0; c < 3; ++c) {
                    destination[x][c] = cv::saturate_cast<uchar>(
                        destination[x][c] * (1.0 - weight) + patch[x][c] * weight
                    );
                }
            }
        }
        const int top = panorama.rows / 2;
        cv::Mat inverseX(panorama.rows - top, panorama.cols, CV_32F);
        cv::Mat inverseY(panorama.rows - top, panorama.cols, CV_32F);
        for (int row = 0; row < inverseX.rows; ++row) {
            float *mx = inverseX.ptr<float>(row);
            float *my = inverseY.ptr<float>(row);
            const int panoramaY = top + row;
            const double latitude = CV_PI * (0.5 - (panoramaY + 0.5) / panorama.rows);
            const double horizontal = std::cos(latitude);
            const double wz = std::sin(latitude);
            for (int x = 0; x < panorama.cols; ++x) {
                const double longitude = 2.0 * CV_PI * ((x + 0.5) / panorama.cols - 0.5);
                const double denominator = -wz;
                const double px = horizontal * std::sin(longitude) / denominator;
                const double py = horizontal * std::cos(longitude) / denominator;
                mx[x] = static_cast<float>(px / tangentLimit * center + center);
                my[x] = static_cast<float>(py / tangentLimit * center + center);
            }
        }
        cv::Mat repairedStrip;
        cv::Mat weightStrip;
        cv::remap(
            repairedView, repairedStrip, inverseX, inverseY,
            cv::INTER_LANCZOS4, cv::BORDER_CONSTANT
        );
        cv::remap(
            warpedKeep, weightStrip, inverseX, inverseY,
            cv::INTER_LINEAR, cv::BORDER_CONSTANT
        );
        cv::Mat output = panorama.clone();
        cv::Mat outputStrip = output.rowRange(top, output.rows);
        for (int y = 0; y < outputStrip.rows; ++y) {
            const cv::Vec3b *patch = repairedStrip.ptr<cv::Vec3b>(y);
            const uchar *alpha = weightStrip.ptr<uchar>(y);
            cv::Vec3b *destination = outputStrip.ptr<cv::Vec3b>(y);
            for (int x = 0; x < output.cols; ++x) {
                const double weight = alpha[x] / 255.0;
                for (int c = 0; c < 3; ++c) {
                    destination[x][c] = cv::saturate_cast<uchar>(
                        destination[x][c] * (1.0 - weight) + patch[x][c] * weight
                    );
                }
            }
        }
        return writeJPEG(output, outputPath, errorMessage);
    } catch (const cv::Exception &exception) {
        setError(errorMessage, exception.what());
        return false;
    } catch (const std::exception &exception) {
        setError(errorMessage, exception.what());
        return false;
    }
}
