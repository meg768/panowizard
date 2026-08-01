#!/usr/bin/env python3

"""Fit a shared fisheye lens and camera rotations from control points.

This is an isolated diagnostic experiment. It does not write source images or
project packages. The model is intentionally independent of PTGui/Hugin lens
coefficient conventions:

    observed radius -> radial polynomial -> equisolid ray -> camera rotation

The first camera is the world-frame anchor. All errors are reported in
source-pixel-equivalent units.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
from scipy.optimize import least_squares
from scipy.spatial.transform import Rotation


WIDTH = 2600.0
HEIGHT = 3888.0


def load_points(path: Path) -> tuple[list[dict[str, float]], int]:
    data = json.loads(path.read_text())
    if "project" in data and "controlpoints" in data["project"]:
        result = []
        for point in data["project"]["controlpoints"]:
            first = point["0"]
            second = point["1"]
            result.append(
                {
                    "firstImage": int(first[0]),
                    "secondImage": int(second[0]),
                    "firstX": float(first[2]),
                    "firstY": float(first[3]),
                    "secondX": float(second[2]),
                    "secondY": float(second[3]),
                }
            )
        image_count = len(data["project"]["imagegroups"])
        return result, image_count
    points = data["controlPoints"]
    image_count = 1 + max(
        max(point["firstImage"], point["secondImage"]) for point in points
    )
    return points, image_count


def initial_yaws(points: list[dict[str, float]], image_count: int) -> np.ndarray:
    parents = list(range(image_count))

    def root(index: int) -> int:
        while parents[index] != index:
            index = parents[index]
        return index

    grouped: dict[tuple[int, int], list[dict[str, float]]] = {}
    for point in points:
        pair = (point["firstImage"], point["secondImage"])
        grouped.setdefault(pair, []).append(point)
    for (first, second), pair_points in grouped.items():
        distances = sorted(
            math.hypot(
                point["firstX"] - point["secondX"],
                point["firstY"] - point["secondY"],
            )
            for point in pair_points
        )
        if len(pair_points) < 6 or distances[len(distances) // 2] >= 250:
            continue
        first_root = root(first)
        second_root = root(second)
        if first_root != second_root:
            parents[second_root] = first_root

    roots = [root(index) for index in range(image_count)]
    ordered_roots = list(dict.fromkeys(roots))
    step = 2 * math.pi / len(ordered_roots)
    return np.array([ordered_roots.index(root_) * step for root_ in roots])


def unpack(parameters: np.ndarray, image_count: int):
    focal = math.exp(parameters[0])
    center_x = parameters[1]
    center_y = parameters[2]
    radial = parameters[3:6]
    rotations = [Rotation.identity()]
    rotations.extend(
        Rotation.from_rotvec(parameters[6:].reshape(image_count - 1, 3))
    )
    return focal, center_x, center_y, radial, rotations


def camera_ray(
    x: float,
    y: float,
    focal: float,
    center_x: float,
    center_y: float,
    radial: np.ndarray,
) -> np.ndarray:
    dx = x - center_x
    dy = y - center_y
    radius = math.hypot(dx, dy)
    if radius < 1e-9:
        return np.array([0.0, 0.0, 1.0])
    normalized = radius / (0.5 * HEIGHT)
    correction = (
        1.0
        + radial[0] * normalized**2
        + radial[1] * normalized**4
        + radial[2] * normalized**6
    )
    corrected_radius = radius * correction
    sine_half_angle = np.clip(corrected_radius / (2 * focal), -0.999999, 0.999999)
    angle = 2 * math.asin(sine_half_angle)
    sine = math.sin(angle)
    return np.array(
        [
            dx / radius * sine,
            -dy / radius * sine,
            math.cos(angle),
        ]
    )


def residuals(
    parameters: np.ndarray,
    points: list[dict[str, float]],
    image_count: int,
) -> np.ndarray:
    focal, center_x, center_y, radial, rotations = unpack(
        parameters, image_count
    )
    result = []
    for point in points:
        first_ray = rotations[point["firstImage"]].apply(
            camera_ray(
                point["firstX"],
                point["firstY"],
                focal,
                center_x,
                center_y,
                radial,
            )
        )
        second_ray = rotations[point["secondImage"]].apply(
            camera_ray(
                point["secondX"],
                point["secondY"],
                focal,
                center_x,
                center_y,
                radial,
            )
        )
        result.extend((first_ray - second_ray) * focal)
    return np.asarray(result)


def point_errors(
    parameters: np.ndarray,
    points: list[dict[str, float]],
    image_count: int,
) -> np.ndarray:
    vectors = residuals(parameters, points, image_count).reshape(-1, 3)
    return np.linalg.norm(vectors, axis=1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("project", type=Path)
    parser.add_argument("--reject-above", type=float)
    args = parser.parse_args()
    points, image_count = load_points(args.project)
    yaws = initial_yaws(points, image_count)

    rotations = [
        Rotation.from_euler("y", yaw).as_rotvec() for yaw in yaws[1:]
    ]
    initial = np.concatenate(
        (
            [math.log(1365.0), 1274.0, 1897.0, 0.0, 0.0, 0.0],
            np.concatenate(rotations),
        )
    )
    lower = np.concatenate(
        (
            [math.log(700), 1100, 1720, -1, -1, -1],
            np.full((image_count - 1) * 3, -2 * math.pi),
        )
    )
    upper = np.concatenate(
        (
            [math.log(2600), 1450, 2150, 1, 1, 1],
            np.full((image_count - 1) * 3, 2 * math.pi),
        )
    )
    fitted = least_squares(
        residuals,
        initial,
        args=(points, image_count),
        bounds=(lower, upper),
        loss="soft_l1",
        f_scale=3.0,
        max_nfev=3000,
        verbose=1,
    )
    if args.reject_above is not None:
        initial_errors = point_errors(fitted.x, points, image_count)
        retained = [
            point
            for point, error in zip(points, initial_errors)
            if error <= args.reject_above
        ]
        print(
            f"refitting with {len(retained)}/{len(points)} points below "
            f"{args.reject_above:g} px"
        )
        fitted = least_squares(
            residuals,
            fitted.x,
            args=(retained, image_count),
            bounds=(lower, upper),
            loss="soft_l1",
            f_scale=3.0,
            max_nfev=3000,
            verbose=1,
        )
    errors = point_errors(fitted.x, points, image_count)
    focal, center_x, center_y, radial, fitted_rotations = unpack(
        fitted.x, image_count
    )
    print(f"success={fitted.success} evaluations={fitted.nfev}")
    print(
        "lens "
        f"focal_px={focal:.6f} center=({center_x:.6f},{center_y:.6f}) "
        f"radial={radial.tolist()}"
    )
    print(
        f"errors rms={math.sqrt(np.mean(errors**2)):.4f} "
        f"median={np.median(errors):.4f} max={np.max(errors):.4f}"
    )
    for index, rotation in enumerate(fitted_rotations):
        matrix = rotation.as_matrix()
        yaw = math.degrees(math.atan2(matrix[0, 2], matrix[2, 2]))
        pitch = math.degrees(
            math.atan2(-matrix[1, 2], math.hypot(matrix[1, 0], matrix[1, 1]))
        )
        roll = math.degrees(math.atan2(matrix[1, 0], matrix[1, 1]))
        print(
            f"image={index + 1} yaw={yaw:.5f} "
            f"pitch={pitch:.5f} roll={roll:.5f}"
        )
    worst = np.argsort(errors)[-15:][::-1]
    for index in worst:
        point = points[index]
        print(
            f"cp={index + 1} pair={point['firstImage'] + 1}-"
            f"{point['secondImage'] + 1} error={errors[index]:.4f}"
        )


if __name__ == "__main__":
    main()
