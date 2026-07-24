#include "OpenCVBridge.h"

#include <cstdlib>
#include <iostream>

int main(int argc, char **argv) {
    if (argc != 3) {
        std::cerr << "usage: nadir-smoke input.tif output.jpg\n";
        return EXIT_FAILURE;
    }

    char *errorMessage = nullptr;
    const bool succeeded = PWRepairNadir(argv[1], argv[2], &errorMessage);
    if (!succeeded) {
        std::cerr << (
            errorMessage == nullptr ? "Okänt fel" : errorMessage
        ) << '\n';
        PWFreeString(errorMessage);
        return EXIT_FAILURE;
    }
    return EXIT_SUCCESS;
}
