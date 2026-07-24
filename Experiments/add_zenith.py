#!/usr/bin/env python3

import argparse
import re
from pathlib import Path

import cv2

from generate_control_points import (
    MAX_POSITION_ERROR,
    mutual_ratio_matches,
    source_map,
    source_point_for_panorama_point,
    wrapped_distance,
)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ring-project", required=True, type=Path)
    parser.add_argument("--output-project", required=True, type=Path)
    parser.add_argument("ring_images", nargs=4, type=Path)
    parser.add_argument("--zenith-image", required=True, type=Path)
    return parser.parse_args()


def parameter(line: str, name: str) -> float:
    match = re.search(
        rf"(?:^| ){re.escape(name)}(-?[0-9]+(?:\.[0-9]+)?)"
        rf"(?= |$)",
        line,
    )
    if match is None:
        raise RuntimeError(f"Missing {name} in image line")
    return float(match.group(1))


def replacing_parameter(line: str, name: str, value: float) -> str:
    pattern = (
        rf"((?:^| ){re.escape(name)})"
        rf"-?[0-9]+(?:\.[0-9]+)?(?= |$)"
    )
    return re.sub(pattern, rf"\g<1>{value:.8f}", line, count=1)


def replacing_filename(line: str, filename: Path) -> str:
    escaped = str(filename).replace("\\", "\\\\").replace('"', '\\"')
    return re.sub(r' n"[^"]*"', f' n"{escaped}"', line, count=1)


def normalized_features(
    image_path: Path,
    image_size: tuple[int, int],
    horizontal_fov: float,
    orientation: tuple[float, float, float],
    detector: cv2.SIFT,
) -> tuple[list[cv2.KeyPoint], cv2.typing.MatLike]:
    image = cv2.imread(str(image_path), cv2.IMREAD_GRAYSCALE)
    if image is None:
        raise RuntimeError(f"Could not read {image_path}")
    if (image.shape[1], image.shape[0]) != image_size:
        raise RuntimeError("All images must have the same dimensions")

    yaw, pitch, roll = orientation
    map_x, map_y, valid_mask = source_map(
        image_size,
        horizontal_fov,
        yaw,
        pitch,
        roll,
    )
    normalized = cv2.remap(
        image,
        map_x,
        map_y,
        cv2.INTER_LINEAR,
        borderMode=cv2.BORDER_CONSTANT,
        borderValue=0,
    )
    valid_mask[normalized < 3] = 0
    return detector.detectAndCompute(normalized, valid_mask)


def geometric_matches(
    keypoints_a: list[cv2.KeyPoint],
    descriptors_a: cv2.typing.MatLike,
    keypoints_b: list[cv2.KeyPoint],
    descriptors_b: cv2.typing.MatLike,
) -> list[cv2.DMatch]:
    matches = mutual_ratio_matches(descriptors_a, descriptors_b)
    matches = [
        match
        for match in matches
        if wrapped_distance(
            keypoints_a[match.queryIdx].pt,
            keypoints_b[match.trainIdx].pt,
        )
        < MAX_POSITION_ERROR
    ]
    matches.sort(
        key=lambda match: (
            wrapped_distance(
                keypoints_a[match.queryIdx].pt,
                keypoints_b[match.trainIdx].pt,
            ),
            match.distance,
        )
    )

    selected: list[cv2.DMatch] = []
    for match in matches:
        point_a = keypoints_a[match.queryIdx].pt
        point_b = keypoints_b[match.trainIdx].pt
        if any(
            abs(point_a[0] - keypoints_a[item.queryIdx].pt[0]) < 4.0
            and abs(point_a[1] - keypoints_a[item.queryIdx].pt[1]) < 4.0
            and abs(point_b[0] - keypoints_b[item.trainIdx].pt[0]) < 4.0
            and abs(point_b[1] - keypoints_b[item.trainIdx].pt[1]) < 4.0
            for item in selected
        ):
            continue
        selected.append(match)
        if len(selected) == 60:
            break
    return selected


def main() -> None:
    arguments = parse_arguments()
    cv2.setNumThreads(1)
    cv2.setRNGSeed(0)

    project_text = arguments.ring_project.read_text(encoding="utf-8")
    image_lines = [
        line for line in project_text.splitlines() if line.startswith("i ")
    ]
    if len(image_lines) != 4:
        raise RuntimeError("Ring project must contain exactly four images")

    horizontal_fov = parameter(image_lines[0], "v")
    orientations = [
        (
            parameter(line, "y"),
            parameter(line, "p"),
            parameter(line, "r"),
        )
        for line in image_lines
    ]

    first_image = cv2.imread(
        str(arguments.ring_images[0]),
        cv2.IMREAD_GRAYSCALE,
    )
    if first_image is None:
        raise RuntimeError(f"Could not read {arguments.ring_images[0]}")
    image_size = (first_image.shape[1], first_image.shape[0])
    detector = cv2.SIFT.create(
        nfeatures=16_000,
        contrastThreshold=0.012,
        edgeThreshold=12,
    )

    ring_features = [
        normalized_features(
            image_path,
            image_size,
            horizontal_fov,
            orientation,
            detector,
        )
        for image_path, orientation in zip(
            arguments.ring_images,
            orientations,
        )
    ]

    candidates = [
        (0.0, pitch, roll)
        for pitch in (90.0, -90.0)
        for roll in (0.0, 90.0, 180.0, 270.0)
    ]
    candidate_results = []
    for candidate in candidates:
        zenith_features = normalized_features(
            arguments.zenith_image,
            image_size,
            horizontal_fov,
            candidate,
            detector,
        )
        pair_matches = [
            geometric_matches(
                ring_keypoints,
                ring_descriptors,
                zenith_features[0],
                zenith_features[1],
            )
            for ring_keypoints, ring_descriptors in ring_features
        ]
        score = sum(len(matches) for matches in pair_matches)
        print(f"Zenith {candidate}: {score} matches")
        candidate_results.append(
            (score, candidate, zenith_features, pair_matches)
        )

    score, zenith_orientation, zenith_features, pair_matches = max(
        candidate_results,
        key=lambda item: item[0],
    )
    if score < 12:
        raise RuntimeError("Could not place the zenith image reliably")
    print(f"Selected zenith orientation {zenith_orientation}")

    control_point_lines: list[str] = []
    connected_ring_images = 0
    for ring_index, matches in enumerate(pair_matches):
        print(f"{ring_index + 1}-5: {len(matches)} control points")
        if len(matches) < 4:
            continue
        connected_ring_images += 1
        for match in matches:
            ring_panorama_point = ring_features[ring_index][0][
                match.queryIdx
            ].pt
            zenith_panorama_point = zenith_features[0][match.trainIdx].pt
            ring_source_point = source_point_for_panorama_point(
                ring_panorama_point,
                image_size,
                horizontal_fov,
                *orientations[ring_index],
            )
            zenith_source_point = source_point_for_panorama_point(
                zenith_panorama_point,
                image_size,
                horizontal_fov,
                *zenith_orientation,
            )
            control_point_lines.append(
                f"c n{ring_index} N4 "
                f"x{ring_source_point[0]:.6f} "
                f"y{ring_source_point[1]:.6f} "
                f"X{zenith_source_point[0]:.6f} "
                f"Y{zenith_source_point[1]:.6f} t0"
            )

    if connected_ring_images < 2:
        raise RuntimeError("Zenith does not connect to enough ring images")

    zenith_line = image_lines[1]
    zenith_line = replacing_parameter(
        zenith_line,
        "y",
        zenith_orientation[0],
    )
    zenith_line = replacing_parameter(
        zenith_line,
        "p",
        zenith_orientation[1],
    )
    zenith_line = replacing_parameter(
        zenith_line,
        "r",
        zenith_orientation[2],
    )
    zenith_line = replacing_filename(zenith_line, arguments.zenith_image)

    lines = project_text.splitlines()
    last_image_line = max(
        index for index, line in enumerate(lines) if line.startswith("i ")
    )
    lines.insert(last_image_line + 1, "#-hugin  cropFactor=1.5")
    lines.insert(last_image_line + 2, zenith_line)
    lines = [
        line
        for line in lines
        if not line.startswith("v ") and line != "v"
    ]
    control_point_heading = lines.index("# control points")
    lines[control_point_heading:control_point_heading] = [
        "v y4",
        "v p4",
        "v r4",
        "v",
        "",
    ]
    lines.extend(control_point_lines)
    arguments.output_project.write_text(
        "\n".join(lines) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {len(control_point_lines)} zenith control points")


if __name__ == "__main__":
    main()
