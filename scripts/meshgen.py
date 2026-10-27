#!/usr/bin/env python3
"""Procedural hero meshes for NIGHT SHIFT (smooth-shaded OBJ, units = studs, Y up).

These replace the part-built placeholders for the props players see first. Import each
OBJ with Studio's 3D Importer, then save the resulting Model to assets/<Name>.rbxm
(docs/ASSETS.md has the exact steps). Object names follow the AssetRegistry convention
"<Material>_<Name>", so materials and colours are applied automatically in game.

Usage:  python3 scripts/meshgen.py            → writes art/meshes/*.obj
"""

from __future__ import annotations

import math
import os
from dataclasses import dataclass, field

Vec = tuple[float, float, float]
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "art", "meshes")


# ── vector helpers ────────────────────────────────────────────────────────────


def add(a: Vec, b: Vec) -> Vec:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub(a: Vec, b: Vec) -> Vec:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def mul(a: Vec, s: float) -> Vec:
    return (a[0] * s, a[1] * s, a[2] * s)


def cross(a: Vec, b: Vec) -> Vec:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def norm(a: Vec) -> Vec:
    length = math.sqrt(a[0] ** 2 + a[1] ** 2 + a[2] ** 2) or 1.0
    return (a[0] / length, a[1] / length, a[2] / length)


# ── mesh container ────────────────────────────────────────────────────────────


@dataclass
class Part:
    name: str
    verts: list[Vec] = field(default_factory=list)
    tris: list[tuple[int, int, int]] = field(default_factory=list)
    double_sided: bool = False

    def vert(self, p: Vec) -> int:
        self.verts.append(p)
        return len(self.verts) - 1

    def quad(self, a: int, b: int, c: int, d: int) -> None:
        self.tris.append((a, b, c))
        self.tris.append((a, c, d))

    def merge(self, other: "Part") -> None:
        offset = len(self.verts)
        self.verts.extend(other.verts)
        self.tris.extend((a + offset, b + offset, c + offset) for a, b, c in other.tris)

    def normals(self) -> list[Vec]:
        acc = [(0.0, 0.0, 0.0)] * len(self.verts)
        for a, b, c in self.tris:
            n = cross(sub(self.verts[b], self.verts[a]), sub(self.verts[c], self.verts[a]))
            for i in (a, b, c):
                acc[i] = add(acc[i], n)
        return [norm(n) for n in acc]


def write_obj(path: str, parts: list[Part]) -> int:
    lines = ["# NIGHT SHIFT procedural mesh — scripts/meshgen.py", "# units: studs, +Y up, front = -Z"]
    base = 1
    triangles = 0
    for part in parts:
        verts, tris, normals = part.verts, part.tris, part.normals()
        if part.double_sided:  # duplicate with flipped winding so both faces render
            n = len(verts)
            verts = verts + verts
            normals = normals + [mul(v, -1) for v in normals]
            tris = tris + [(a + n, c + n, b + n) for a, b, c in tris]
        lines.append(f"o {part.name}")
        lines.extend(f"v {x:.4f} {y:.4f} {z:.4f}" for x, y, z in verts)
        lines.extend(f"vn {x:.4f} {y:.4f} {z:.4f}" for x, y, z in normals)
        for a, b, c in tris:
            a, b, c = a + base, b + base, c + base
            lines.append(f"f {a}//{a} {b}//{b} {c}//{c}")
        base += len(verts)
        triangles += len(tris)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")
    return triangles


# ── generators ────────────────────────────────────────────────────────────────


def lathe(name: str, profile: list[tuple[float, float]], segments: int, radial=None, closed=False) -> Part:
    """Revolve (radius, y) points around Y. radial(theta, y) -> radius multiplier."""
    part = Part(name)
    rows = []
    for r, y in profile:
        row = []
        for s in range(segments):
            theta = 2 * math.pi * s / segments
            rr = r * (radial(theta, y) if radial else 1.0)
            row.append(part.vert((rr * math.cos(theta), y, rr * math.sin(theta))))
        rows.append(row)
    count = len(rows) if closed else len(rows) - 1
    for i in range(count):
        a_row, b_row = rows[i], rows[(i + 1) % len(rows)]
        for s in range(segments):
            t = (s + 1) % segments
            part.quad(a_row[s], a_row[t], b_row[t], b_row[s])
    return part


def torus(name: str, center_y: float, major: float, minor: float, segments=48, sides=10) -> Part:
    profile = [
        (major + minor * math.cos(2 * math.pi * k / sides), center_y + minor * math.sin(2 * math.pi * k / sides))
        for k in range(sides)
    ]
    return lathe(name, profile, segments, closed=True)


def sphere(name: str, center: Vec, radius: float, rings=10, segments=16) -> Part:
    profile = [(radius * math.sin(math.pi * k / rings), -radius * math.cos(math.pi * k / rings)) for k in range(rings + 1)]
    part = lathe(name, profile, segments)
    part.verts = [add(v, center) for v in part.verts]
    return part


def tube(name: str, path: list[Vec], radii: list[float], sides: int) -> Part:
    """Sweep a circle along a polyline (parallel-transport frames)."""
    part = Part(name)
    up = (0.0, 0.0, 1.0)
    rows = []
    for i, p in enumerate(path):
        nxt = path[min(i + 1, len(path) - 1)]
        prv = path[max(i - 1, 0)]
        tangent = norm(sub(nxt, prv))
        side = norm(cross(tangent, up))
        up = norm(cross(side, tangent))
        row = []
        for s in range(sides):
            a = 2 * math.pi * s / sides
            offset = add(mul(side, math.cos(a) * radii[i]), mul(up, math.sin(a) * radii[i]))
            row.append(part.vert(add(p, offset)))
        rows.append(row)
    for i in range(len(rows) - 1):
        for s in range(sides):
            t = (s + 1) % sides
            part.quad(rows[i][s], rows[i][t], rows[i + 1][t], rows[i + 1][s])
    tip = part.vert(path[-1])
    for s in range(sides):
        part.tris.append((rows[-1][s], rows[-1][(s + 1) % sides], tip))
    return part


# ── assets ────────────────────────────────────────────────────────────────────


def palm_tree() -> list[Part]:
    """16-stud palm: ringed, gently S-curved trunk; 10 drooping fronds with leaflets."""
    height = 15.0
    samples = 90
    path, radii = [], []
    for i in range(samples + 1):
        t = i / samples
        x = 0.9 * math.sin(math.pi * t) * (1 - 0.3 * t)
        path.append((x, height * t, 0.25 * math.sin(2 * math.pi * t)))
        rings = 1 + 0.07 * (0.5 + 0.5 * math.cos(2 * math.pi * 24 * t))
        radii.append((0.95 - 0.42 * t) * rings * (1.25 if t < 0.04 else 1.0))
    trunk = tube("Bark_Trunk", path, radii, 16)

    top = path[-1]
    crown = sphere("Bark_Crown", add(top, (0, 0.2, 0)), 0.85)
    for k in range(3):
        a = k * 2.1
        crown.merge(sphere("nut", add(top, (0.75 * math.cos(a), -0.55, 0.75 * math.sin(a))), 0.42, 8, 10))

    fronds_a, fronds_b = Part("Leaf_FrondsA", double_sided=True), Part("LeafDark_FrondsB", double_sided=True)
    count = 10
    for f in range(count):
        yaw = 2 * math.pi * f / count + (0.15 if f % 2 else -0.1)
        heading = (math.cos(yaw), 0.0, math.sin(yaw))
        side_dir = (-heading[2], 0.0, heading[0])
        length = 7.6 if f % 2 else 6.6
        pitch0 = math.radians(48 if f % 2 else 30)
        drop = math.radians(85)
        steps = 22
        rachis = [add(top, (0, 0.3, 0))]
        for i in range(1, steps + 1):
            s = i / steps
            pitch = pitch0 - drop * s**1.6
            step = mul(add(mul(heading, math.cos(pitch)), (0, math.sin(pitch), 0)), length / steps)
            rachis.append(add(rachis[-1], step))
        target = fronds_a if f % 2 == 0 else fronds_b
        target.merge(tube("rachis", rachis, [0.11 * (1 - i / (steps + 1)) + 0.03 for i in range(steps + 1)], 5))
        for i in range(2, steps + 1):
            s = i / steps
            base_pt = rachis[i]
            along = norm(sub(rachis[i], rachis[i - 1]))
            leaflet_len = 1.9 * math.sin(math.pi * (0.12 + 0.88 * s)) + 0.2
            for side in (-1, 1):
                out = norm(add(add(mul(side_dir, side), mul(along, 0.55)), (0, -0.45 - 0.3 * s, 0)))
                tip = add(base_pt, mul(out, leaflet_len))
                width = 0.22
                a = target.vert(add(base_pt, mul(along, -width)))
                b = target.vert(add(base_pt, mul(along, width)))
                mid = target.vert(add(add(base_pt, mul(out, leaflet_len * 0.55)), mul(along, width * 0.9)))
                c = target.vert(tip)
                target.tris.append((a, b, mid))
                target.tris.append((a, mid, c))
    return [trunk, crown, fronds_a, fronds_b]


def fountain() -> list[Part]:
    """Matches the procedural fountain's footprint (r 11.7) and spout height (y 11)."""
    seg = 64
    basin = lathe(
        "Marble_Basin",
        [
            (0.0, 0.6), (10.1, 0.6), (10.15, 2.05), (10.4, 2.25), (10.9, 2.32),
            (11.3, 2.16), (11.5, 1.7), (11.35, 1.1), (11.55, 0.45), (11.7, 0.0),
        ],
        seg,
    )
    tiers = lathe(
        "Marble_Tiers",
        [
            (1.95, 0.6), (1.95, 1.0), (1.6, 1.35), (1.42, 3.4), (1.25, 5.5), (1.7, 6.0),
            (3.1, 6.6), (4.6, 7.1), (5.12, 7.45), (5.15, 7.85), (4.9, 7.98), (4.62, 7.75),
            (4.45, 7.52), (1.0, 7.52), (0.9, 7.7), (0.74, 8.7), (0.7, 9.6), (1.05, 9.95),
            (2.2, 10.25), (2.72, 10.52), (2.76, 10.78), (2.5, 10.84), (2.3, 10.66), (0.6, 10.66),
        ],
        seg,
    )
    water = lathe("Water_Pools", [(0.0, 1.62), (10.12, 1.62)], seg)
    water.merge(lathe("upper", [(0.0, 7.62), (4.44, 7.62)], seg))
    gold = torus("Gold_Trim", 2.36, 10.9, 0.12)
    gold.merge(torus("t2", 7.9, 5.0, 0.1))
    gold.merge(torus("t3", 6.0, 1.72, 0.12))
    gold.merge(sphere("spout", (0.0, 11.05, 0.0), 0.6))
    gold.merge(lathe("finial", [(0.0, 11.0), (0.18, 11.0), (0.12, 11.9), (0.0, 12.2)], 16))
    return [basin, tiers, water, gold]


def column() -> list[Part]:
    """48-stud fluted column with moulded base and capital (atrium balcony supports)."""
    def flutes(theta: float, y: float) -> float:
        blend = max(0.0, min(1.0, (y - 2.2) / 0.4, (45.8 - y) / 0.4))
        return 1.0 - blend * 0.055 * (0.5 + 0.5 * math.cos(16 * theta))

    profile = [
        (2.15, 0.0), (2.15, 0.55), (1.95, 0.75), (1.9, 1.15), (1.62, 1.45), (1.52, 2.0), (1.5, 2.2),
        (1.5, 12.0), (1.5, 24.0), (1.5, 36.0), (1.5, 45.8), (1.52, 46.0), (1.62, 46.4),
        (1.95, 46.8), (2.2, 47.3), (2.25, 48.0),
    ]
    shaft = lathe("Marble_Shaft", profile, 128, radial=flutes)
    rings = torus("Gold_Rings", 1.05, 1.92, 0.14)
    for y, r in ((21.6, 1.6), (24.4, 1.6), (46.6, 1.92)):
        rings.merge(torus("ring", y, r, 0.13))
    return [shaft, rings]


def planter_bench() -> list[Part]:
    """Round planter (r 3) wrapped by a seating ring (to r 4.45). Palm sits on soil (y 2.45)."""
    seg = 48
    base = lathe("MarbleWarm_Base", [(3.0, 0.0), (4.4, 0.0), (4.4, 0.15), (4.3, 0.3), (4.3, 1.45), (3.0, 1.45)], seg)
    seat = lathe(
        "Wood_Seat",
        [(3.15, 1.5), (4.4, 1.5), (4.48, 1.6), (4.45, 1.78), (4.3, 1.84), (3.2, 1.84), (3.15, 1.76)],
        seg,
        radial=lambda theta, y: 1.0 - 0.006 * (1 if math.sin(24 * theta) > 0.92 else 0),
        closed=True,
    )
    pot = lathe(
        "Marble_Pot",
        [(3.0, 1.45), (3.05, 2.4), (3.25, 2.55), (3.3, 2.7), (3.15, 2.82), (2.85, 2.76), (2.8, 2.45)],
        seg,
    )
    soil = lathe("Soil_Top", [(0.0, 2.45), (2.82, 2.45)], seg)
    gold = torus("Gold_Rim", 1.48, 4.42, 0.06)
    gold.merge(torus("lip", 2.72, 3.28, 0.06))
    return [base, seat, pot, soil, gold]


ASSETS = {
    "PalmTree": palm_tree,
    "Fountain": fountain,
    "Column": column,
    "PlanterBench": planter_bench,
}


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, build in ASSETS.items():
        parts = build()
        path = os.path.join(OUT_DIR, f"{name}.obj")
        triangles = write_obj(path, parts)
        names = ", ".join(p.name for p in parts)
        print(f"{name:13s} {triangles:6d} tris  [{names}]  → {os.path.relpath(path)}")


if __name__ == "__main__":
    main()
