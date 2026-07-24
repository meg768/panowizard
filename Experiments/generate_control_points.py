#!/usr/bin/env python3

import argparse
import math
from pathlib import Path

import cv2
import numpy as np


PANORAMA_WIDTH = 2400
PANORAMA_HEIGHT = PANORAMA_WIDTH // 2
MAX_POSITION_ERROR = 120.0


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-project", required=True, type=Path)
    parser.add_argument("--output-project", required=True, type=Path)
    parser.add_argument("--horizontal-fov", required=True, type=float)
    parser.add_argument("images", nargs="+", type=Path)
    return parser.parse_args()


def camera_to_world_rotation(
    yaw_degrees: float,
    pitch_degrees: float,
    roll_degrees: float,
) -> np.ndarray:
    yaw = math.radians(yaw_degrees)
    pitch = math.radians(pitch_degrees)
    roll = math.radians(roll_degrees)
    yaw_rotation = np.array(
        [
            [math.cos(yaw), 0.0, math.sin(yaw)],
            [0.0, 1.0, 0.0],
            [-math.sin(yaw), 0.0, math.cos(yaw)],
        ],
        dtype=np.float64,
    )
    pitch_rotation = np.array(
        [
            [1.0, 0.0, 0.0],
            [0.0, math.cos(pitch), -math.sin(pitch)],
            [0.0, math.sin(pitch), math.cos(pitch)],
        ],
        dtype=np.float64,
    )
    roll_rotation = np.array(
        [
            [math.cos(roll), -math.sin(roll), 0.0],
            [math.sin(roll), math.cos(roll), 0.0],
            [0.0, 0.0, 1.0],
        ],
        dtype=np.float64,
    )
    return yaw_rotation @ pitch_rotation @ roll_rotation


def camera_ray_for_world_ray(
    world_x: np.ndarray,
    world_y: np.ndarray,
    world_z: np.ndarray,
    yaw_degrees: float,
    pitch_degrees: float,
    roll_degrees: float,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    rotation = camera_to_world_rotation(
        yaw_degrees,
        pitch_degrees,
        roll_degrees,
    )
    world_rays = np.stack((world_x, world_y, world_z), axis=0)
    camera_rays = np.einsum("ij,j...->i...", rotation.T, world_rays)
    return camera_rays[0], camera_rays[1], camera_rays[2]


def source_map(
    source_size: tuple[int, int],
    horizontal_fov: float,
    yaw_degrees: float,
    pitch_degrees: float = 0.0,
    roll_degrees: float = 0.0,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    source_width, source_height = source_size
    panorama_x, panorama_y = np.meshgrid(
        np.arange(PANORAMA_WIDTH, dtype=np.float32),
        np.arange(PANORAMA_HEIGHT, dtype=np.float32),
    )
    longitude = (
        panorama_x / PANORAMA_WIDTH * (2.0 * math.pi) - math.pi
    )
    latitude = (
        math.pi / 2.0 - panorama_y / PANORAMA_HEIGHT * math.pi
    )

    world_x = np.sin(longitude) * np.cos(latitude)
    world_y = -np.sin(latitude)
    world_z = np.cos(longitude) * np.cos(latitude)
    camera_x, camera_y, camera_z = camera_ray_for_world_ray(
        world_x,
        world_y,
        world_z,
        yaw_degrees,
        pitch_degrees,
        roll_degrees,
    )

    angle = np.arccos(np.clip(camera_z, -1.0, 1.0))
    sine = np.sin(angle)
    focal_length = (
        (source_width / 2.0) / math.radians(horizontal_fov / 2.0)
    )
    radius = focal_length * angle
    scale = np.divide(
        radius,
        sine,
        out=np.zeros_like(radius),
        where=np.abs(sine) > 1e-7,
    )
    map_x = source_width / 2.0 + camera_x * scale
    map_y = source_height / 2.0 + camera_y * scale
    valid = (
        (map_x >= 0.0)
        & (map_x < source_width - 1.0)
        & (map_y >= 0.0)
        & (map_y < source_height - 1.0)
        & (angle < math.pi / 2.0)
    )
    return (
        map_x.astype(np.float32),
        map_y.astype(np.float32),
        valid.astype(np.uint8) * 255,
    )


def source_point_for_panorama_point(
    point: tuple[float, float],
    source_size: tuple[int, int],
    horizontal_fov: float,
    yaw_degrees: float,
    pitch_degrees: float = 0.0,
    roll_degrees: float = 0.0,
) -> tuple[float, float]:
    source_width, source_height = source_size
    longitude = point[0] / PANORAMA_WIDTH * (2.0 * math.pi) - math.pi
    latitude = math.pi / 2.0 - point[1] / PANORAMA_HEIGHT * math.pi
    world_x = math.sin(longitude) * math.cos(latitude)
    world_y = -math.sin(latitude)
    world_z = math.cos(longitude) * math.cos(latitude)
    camera_x, camera_y, camera_z = camera_ray_for_world_ray(
        np.array(world_x),
        np.array(world_y),
        np.array(world_z),
        yaw_degrees,
        pitch_degrees,
        roll_degrees,
    )

    angle = math.acos(float(np.clip(camera_z, -1.0, 1.0)))
    sine = math.sin(angle)
    if abs(sine) < 1e-7:
        return source_width / 2.0, source_height / 2.0

    focal_length = (
        (source_width / 2.0) / math.radians(horizontal_fov / 2.0)
    )
    radius = focal_length * angle
    scale = radius / sine
    return (
        source_width / 2.0 + float(camera_x) * scale,
        source_height / 2.0 + float(camera_y) * scale,
    )


def mutual_ratio_matches(
    descriptors_a: np.ndarray,
    descriptors_b: np.ndarray,
    ratio: float = 0.88,
) -> list[cv2.DMatch]:
    matcher = cv2.BFMatcher(cv2.NORM_L2)
    forward = matcher.knnMatch(descriptors_a, descriptors_b, k=2)
    backward = matcher.knnMatch(descriptors_b, descriptors_a, k=2)

    accepted_forward = {
        match.queryIdx: match
        for match, alternate in forward
        if match.distance < ratio * alternate.distance
    }
    accepted_backward = {
        match.queryIdx: match
        for match, alternate in backward
        if match.distance < ratio * alternate.distance
    }

    return [
        match
        for query_index, match in accepted_forward.items()
        if match.trainIdx in accepted_backward
        and accepted_backward[match.trainIdx].trainIdx == query_index
    ]


def wrapped_distance(
    point_a: tuple[float, float],
    point_b: tuple[float, float],
) -> float:
    horizontal_distance = abs(point_a[0] - point_b[0])
    horizontal_distance = min(
        horizontal_distance,
        PANORAMA_WIDTH - horizontal_distance,
    )
    vertical_distance = point_a[1] - point_b[1]
    return math.hypot(horizontal_distance, vertical_distance)


def main() -> None:
    arguments = parse_arguments()
    cv2.setNumThreads(1)
    cv2.setRNGSeed(0)

    detector = cv2.SIFT.create(
        nfeatures=16_000,
        contrastThreshold=0.012,
        edgeThreshold=12,
    )
    source_size: tuple[int, int] | None = None
    keypoints: list[list[cv2.KeyPoint]] = []
    descriptors: list[np.ndarray] = []
    yaws = [index * 90.0 for index in range(len(arguments.images))]

    for image_path, yaw in zip(arguments.images, yaws):
        source_image = cv2.imread(str(image_path), cv2.IMREAD_GRAYSCALE)
        if source_image is None:
            raise RuntimeError(f"Could not read {image_path}")

        current_size = (source_image.shape[1], source_image.shape[0])
        if source_size is None:
            source_size = current_size
        elif current_size != source_size:
            raise RuntimeError("All images must have the same dimensions")

        map_x, map_y, valid_mask = source_map(
            current_size,
            arguments.horizontal_fov,
            yaw,
        )
        normalized_image = cv2.remap(
            source_image,
            map_x,
            map_y,
            cv2.INTER_LINEAR,
            borderMode=cv2.BORDER_CONSTANT,
            borderValue=0,
        )
        valid_mask[normalized_image < 3] = 0
        current_keypoints, current_descriptors = detector.detectAndCompute(
            normalized_image,
            valid_mask,
        )
        keypoints.append(current_keypoints)
        descriptors.append(current_descriptors)
        print(
            f"{image_path.name}: "
            f"{len(current_keypoints)} normalized keypoints"
        )

    assert source_size is not None

    candidate_pairs = [
        (index, (index + 1) % len(arguments.images))
        for index in range(len(arguments.images))
    ]
    control_point_lines: list[str] = []

    for image_a, image_b in candidate_pairs:
        matches = mutual_ratio_matches(
            descriptors[image_a],
            descriptors[image_b],
        )
        filtered_matches = [
            match
            for match in matches
            if wrapped_distance(
                keypoints[image_a][match.queryIdx].pt,
                keypoints[image_b][match.trainIdx].pt,
            )
            < MAX_POSITION_ERROR
        ]
        filtered_matches.sort(
            key=lambda match: (
                wrapped_distance(
                    keypoints[image_a][match.queryIdx].pt,
                    keypoints[image_b][match.trainIdx].pt,
                ),
                match.distance,
            )
        )
        filtered_matches = filtered_matches[:60]
        print(
            f"{image_a + 1}-{image_b + 1}: "
            f"{len(matches)} descriptor matches, "
            f"{len(filtered_matches)} geometric matches"
        )

        if len(filtered_matches) < 6:
            raise RuntimeError(
                f"Too few reliable matches for images "
                f"{image_a + 1} and {image_b + 1}"
            )

        for match in filtered_matches:
            panorama_point_a = keypoints[image_a][match.queryIdx].pt
            panorama_point_b = keypoints[image_b][match.trainIdx].pt
            source_point_a = source_point_for_panorama_point(
                panorama_point_a,
                source_size,
                arguments.horizontal_fov,
                yaws[image_a],
            )
            source_point_b = source_point_for_panorama_point(
                panorama_point_b,
                source_size,
                arguments.horizontal_fov,
                yaws[image_b],
            )
            control_point_lines.append(
                f"c n{image_a} N{image_b} "
                f"x{source_point_a[0]:.6f} y{source_point_a[1]:.6f} "
                f"X{source_point_b[0]:.6f} Y{source_point_b[1]:.6f} t0"
            )

    project_text = arguments.input_project.read_text(encoding="utf-8")
    if not project_text.endswith("\n"):
        project_text += "\n"
    project_text += "\n".join(control_point_lines) + "\n"
    arguments.output_project.write_text(project_text, encoding="utf-8")
    print(f"Wrote {len(control_point_lines)} control points")


if __name__ == "__main__":
    main()
