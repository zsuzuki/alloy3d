#!/usr/bin/env python3
"""Generate repository-owned skinned GLB fixtures; no external assets or packages.

Each five-joint strand has linear quaternion animation and STEP translation /
linear scale animation. Joint nodes are stored in reverse order to exercise
parent lookup. Static matrix and TRS nodes test unanimated pose preservation.
"""
import argparse
import json
import math
from pathlib import Path
import struct


def generate(count):
    binary = bytearray()
    views, accessors = [], []

    def accessor(values, kind, fmt="f", target=None, bounds=False):
        width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[kind]
        raw = struct.pack("<" + fmt * len(values), *values)
        view = {"buffer": 0, "byteOffset": len(binary), "byteLength": len(raw)}
        if target:
            view["target"] = target
        views.append(view)
        binary.extend(raw)
        binary.extend(b"\0" * (-len(binary) % 4))
        item = {"bufferView": len(views) - 1, "componentType": 5126 if fmt == "f" else 5123,
                "count": len(values) // width, "type": kind}
        if bounds:
            item["min"] = [min(values[i::width]) for i in range(width)]
            item["max"] = [max(values[i::width]) for i in range(width)]
        accessors.append(item)
        return len(accessors) - 1

    def matrix(x, y, z):
        return [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, z, 1]

    node_index = lambda joint: 2 + count - 1 - joint
    roots = [node_index(i) for i in range(0, count, 5)]
    nodes = [{"name": "StaticMatrixRoot", "matrix": matrix(.1, -.1, 0),
              "children": [1, count + 2, count + 3] + roots},
             {"name": "SkinnedStrands", "mesh": 0, "skin": 0}] + [{} for _ in range(count)]
    nodes += [{"name": "StaticMatrixLeaf", "matrix": matrix(.3, .2, .1)},
              {"name": "StaticTRSLeaf", "translation": [-.2, .3, .1], "scale": [1, 2, 1]}]
    positions, normals, joints, weights, indices, inverse_bind = [], [], [], [], [], []
    local_positions = []
    for i in range(count):
        strand, segment = divmod(i, 5)
        cols = min(8, count // 5)
        x = (strand % cols - (cols - 1) / 2) * .4
        y = (strand // cols - ((count // 5 - 1) // cols) / 2) * .85
        local = [x, y, 0] if segment == 0 else [0, .15, 0]
        local_positions.append(local)
        node = {"name": f"AnimationFixture_LongJointName_{i:03}", "translation": local}
        if segment < 4:
            node["children"] = [node_index(i + 1)]
        nodes[node_index(i)] = node
        # Bind-space mesh and inverse bind include the matrix root transform.
        bx, by = x + .1, y + segment * .15 - .1
        inverse_bind.extend(matrix(-bx, -by, 0))
        base = len(positions) // 3
        for dx, dy in [(-.055, 0), (.055, 0), (-.055, .14), (.055, .14)]:
            positions.extend([bx + dx, by + dy, 0])
            normals.extend([0, 0, 1])
            joints.extend([i, i - 1 if segment else i, 0, 0])
            weights.extend([.75, .25, 0, 0])
        indices.extend([base, base + 1, base + 2, base + 2, base + 1, base + 3])

    attributes = {
        "POSITION": accessor(positions, "VEC3", target=34962, bounds=True),
        "NORMAL": accessor(normals, "VEC3", target=34962),
        "JOINTS_0": accessor(joints, "VEC4", fmt="H", target=34962),
        "WEIGHTS_0": accessor(weights, "VEC4", target=34962),
    }
    index_accessor = accessor(indices, "SCALAR", fmt="H", target=34963)
    bind_accessor = accessor(inverse_bind, "MAT4")
    wave_times = accessor([0, 1, 2], "SCALAR", bounds=True)
    lift_times = accessor([0, 1.5, 3], "SCALAR", bounds=True)
    clips = []
    for clip in range(2):
        samplers, channels = [], []

        def channel(joint, path, values, kind, interpolation):
            samplers.append({"input": wave_times if clip == 0 else lift_times,
                             "output": accessor(values, kind), "interpolation": interpolation})
            channels.append({"sampler": len(samplers) - 1,
                             "target": {"node": node_index(joint), "path": path}})

        for i in range(count):
            if clip == 0:
                angle = .18 if i % 2 == 0 else -.18
                # Negative equivalent endpoint exercises shortest-path quaternion interpolation.
                channel(i, "rotation", [0, 0, 0, 1, 0, 0, math.sin(angle / 2), math.cos(angle / 2),
                                         0, 0, 0, -1], "VEC4", "LINEAR")
            else:
                p = local_positions[i]
                channel(i, "translation", p + [p[0] + .02, p[1] + .03, p[2]] + p,
                        "VEC3", "STEP")
                channel(i, "scale", [1, 1, 1, 1.02, .98, 1, 1, 1, 1], "VEC3", "LINEAR")
        clips.append({"name": "Wave" if clip == 0 else "Lift", "samplers": samplers, "channels": channels})

    doc = {"asset": {"version": "2.0", "generator": "Alloy3D generate_animation_fixtures.py"},
           "scene": 0, "scenes": [{"nodes": [0]}], "nodes": nodes,
           "skins": [{"name": f"Rig{count}", "skeleton": 0,
                      "joints": [node_index(i) for i in range(count)], "inverseBindMatrices": bind_accessor}],
           "meshes": [{"primitives": [{"attributes": attributes, "indices": index_accessor, "material": 0}]}],
           "materials": [{"pbrMetallicRoughness": {"baseColorFactor": [.2, .7, .9, 1]}}],
           "animations": clips, "buffers": [{"byteLength": len(binary)}],
           "bufferViews": views, "accessors": accessors}
    payload = json.dumps(doc, separators=(",", ":")).encode()
    payload += b" " * (-len(payload) % 4)
    return (struct.pack("<III", 0x46546C67, 2, 28 + len(payload) + len(binary))
            + struct.pack("<I4s", len(payload), b"JSON") + payload
            + struct.pack("<I4s", len(binary), b"BIN\0") + binary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify checked-in models match the generator")
    parser.add_argument("--output-dir", type=Path,
                        default=Path(__file__).resolve().parents[1] / "assets/tests/animation")
    args = parser.parse_args()
    for count in (25, 100, 200):
        path = args.output_dir / f"rig_{count}.glb"
        data = generate(count)
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                raise SystemExit(f"Fixture differs: {path}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        print(f"{path.name}: {count} joints, {len(data)} bytes")


if __name__ == "__main__":
    main()
