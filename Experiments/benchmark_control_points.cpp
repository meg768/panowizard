#include "OpenCVBridge.h"

#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <vector>

int main(int argc, char **argv) {
    if (argc < 4) {
        std::cerr << "usage: cp-benchmark HFOV image image [...]\n";
        return 2;
    }
    const double fieldOfView = std::strtod(argv[1], nullptr);
    std::vector<const char *> paths;
    for (int index = 2; index < argc; ++index) paths.push_back(argv[index]);
    PWControlPoint *points = nullptr;
    int pointCount = 0;
    char *error = nullptr;
    const int succeeded = PWGenerateRingControlPoints(
        paths.data(), nullptr, int(paths.size()), fieldOfView,
        &points, &pointCount, &error
    );
    if (!succeeded) {
        std::cerr << (error == nullptr ? "unknown error" : error) << '\n';
        PWFreeString(error);
        return 1;
    }
    #ifdef PW_BENCHMARK_LEGACY
    std::cout << "total\t" << pointCount << "\n";
    PWFreeControlPoints(points);
    return 0;
    #else
    PWControlPointPairDiagnostic *diagnostics = nullptr;
    int diagnosticCount = 0;
    PWCopyLastControlPointPairDiagnostics(&diagnostics, &diagnosticCount);
    std::cout << "pair\tfeatures\tratio\tmutual\tgeometric\tselected"
                 "\tmean_error\tcoverage\n";
    for (int index = 0; index < diagnosticCount; ++index) {
        const auto &item = diagnostics[index];
        std::cout << item.firstImage << '-' << item.secondImage << '\t'
                  << item.firstFeatureCount << '/' << item.secondFeatureCount
                  << '\t' << item.ratioMatchCount
                  << '\t' << item.mutualMatchCount
                  << '\t' << item.geometricMatchCount
                  << '\t' << item.selectedControlPointCount
                  << '\t' << std::fixed << std::setprecision(3)
                  << item.meanReprojectionError
                  << '\t' << item.spatialCoverage << '\n';
    }
    std::cout << "total\t" << pointCount << "\n";
    PWFreeControlPointPairDiagnostics(diagnostics);
    PWFreeControlPoints(points);
    return 0;
    #endif
}
