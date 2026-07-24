#!/usr/bin/env python3

import argparse
from pathlib import Path

import cv2
import numpy as np


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-directory", required=True, type=Path)
    parser.add_argument("images", nargs="+", type=Path)
    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()
    arguments.output_directory.mkdir(parents=True, exist_ok=True)

    for index, image_path in enumerate(arguments.images):
        image = cv2.imread(str(image_path), cv2.IMREAD_COLOR)
        if image is None:
            raise RuntimeError(f"Could not read {image_path}")

        height, width = image.shape[:2]
        center = (width // 2, height // 2)
        radius = int(round(height * 0.504))
        alpha = np.zeros((height, width), dtype=np.uint8)
        cv2.circle(alpha, center, radius, 255, thickness=-1, lineType=cv2.LINE_AA)
        output = np.dstack((image, alpha))
        destination = arguments.output_directory / f"source{index:04d}.tif"
        if not cv2.imwrite(str(destination), output):
            raise RuntimeError(f"Could not write {destination}")
        print(destination)


if __name__ == "__main__":
    main()
