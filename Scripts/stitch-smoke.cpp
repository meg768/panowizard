#include "OpenCVBridge.h"

#include <cstdlib>
#include <iostream>
#include <vector>

int main(int argc, char **argv) {
    if (argc < 4) {
        std::cerr << "usage: stitch-smoke output.jpg input1.jpg input2.jpg ...\n";
        return EXIT_FAILURE;
    }

    std::vector<const char *> inputs;
    for (int index = 2; index < argc; ++index) {
        inputs.push_back(argv[index]);
    }

    char *errorMessage = nullptr;
    const bool succeeded = PWStitchImages(
        inputs.data(),
        static_cast<int>(inputs.size()),
        std::getenv("PW_RAW") == nullptr,
        argv[1],
        &errorMessage
    );

    if (!succeeded) {
        std::cerr << (errorMessage == nullptr ? "Okänt fel" : errorMessage) << '\n';
        PWFreeString(errorMessage);
        return EXIT_FAILURE;
    }

    return EXIT_SUCCESS;
}
