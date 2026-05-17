#!/usr/bin/env python3
import json
import math
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "samples" / "models" / "animated_bouncer.glb"


def align4(data: bytes, pad: bytes = b"\x00") -> bytes:
    return data + pad * ((4 - len(data) % 4) % 4)


def pack_floats(values):
    return struct.pack("<" + "f" * len(values), *values)


def pack_uint16(values):
    return struct.pack("<" + "H" * len(values), *values)


positions = [
    -0.55, 0.0, -0.55,
    0.55, 0.0, -0.55,
    0.55, 0.0, 0.55,
    -0.55, 0.0, 0.55,
    0.0, 1.05, 0.0,
]

normals = []
for i in range(0, len(positions), 3):
    x, y, z = positions[i], positions[i + 1], positions[i + 2]
    length = math.sqrt(x * x + y * y + z * z) or 1.0
    normals.extend([x / length, y / length, z / length])

texcoords = [
    0.0, 0.0,
    1.0, 0.0,
    1.0, 1.0,
    0.0, 1.0,
    0.5, 0.5,
]

indices = [
    0, 1, 2, 0, 2, 3,
    0, 4, 1,
    1, 4, 2,
    2, 4, 3,
    3, 4, 0,
]

times = [0.0, 0.5, 1.0]
translations = [
    0.0, 0.0, 0.0,
    0.0, 0.55, 0.0,
    0.0, 0.0, 0.0,
]

chunks = []
buffer_views = []


def add_buffer_view(data: bytes, target=None) -> int:
    offset = sum(len(chunk) for chunk in chunks)
    padded = align4(data)
    chunks.append(padded)
    view = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
    if target is not None:
        view["target"] = target
    buffer_views.append(view)
    return len(buffer_views) - 1


position_view = add_buffer_view(pack_floats(positions), 34962)
normal_view = add_buffer_view(pack_floats(normals), 34962)
texcoord_view = add_buffer_view(pack_floats(texcoords), 34962)
index_view = add_buffer_view(pack_uint16(indices), 34963)
time_view = add_buffer_view(pack_floats(times))
translation_view = add_buffer_view(pack_floats(translations))

binary = b"".join(chunks)

gltf = {
    "asset": {"version": "2.0", "generator": "Alloy3D generate_bouncer_glb.py"},
    "scene": 0,
    "scenes": [{"nodes": [0]}],
    "nodes": [{"name": "AnimatedBouncer", "mesh": 0}],
    "meshes": [
        {
            "name": "BouncerPyramid",
            "primitives": [
                {
                    "attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2},
                    "indices": 3,
                    "material": 0,
                }
            ],
        }
    ],
    "materials": [
        {
            "name": "BouncerBlue",
            "pbrMetallicRoughness": {
                "baseColorFactor": [0.2, 0.55, 0.9, 1.0],
                "metallicFactor": 0.0,
                "roughnessFactor": 0.65,
            },
        }
    ],
    "animations": [
        {
            "name": "Bounce",
            "samplers": [{"input": 4, "output": 5, "interpolation": "LINEAR"}],
            "channels": [{"sampler": 0, "target": {"node": 0, "path": "translation"}}],
        }
    ],
    "buffers": [{"byteLength": len(binary)}],
    "bufferViews": buffer_views,
    "accessors": [
        {"bufferView": position_view, "componentType": 5126, "count": 5, "type": "VEC3", "min": [-0.55, 0.0, -0.55], "max": [0.55, 1.05, 0.55]},
        {"bufferView": normal_view, "componentType": 5126, "count": 5, "type": "VEC3"},
        {"bufferView": texcoord_view, "componentType": 5126, "count": 5, "type": "VEC2"},
        {"bufferView": index_view, "componentType": 5123, "count": len(indices), "type": "SCALAR"},
        {"bufferView": time_view, "componentType": 5126, "count": len(times), "type": "SCALAR", "min": [0.0], "max": [1.0]},
        {"bufferView": translation_view, "componentType": 5126, "count": len(times), "type": "VEC3"},
    ],
}

json_chunk = align4(json.dumps(gltf, separators=(",", ":")).encode("utf-8"), b" ")
bin_chunk = align4(binary)
length = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)

OUT.parent.mkdir(parents=True, exist_ok=True)
with OUT.open("wb") as f:
    f.write(struct.pack("<III", 0x46546C67, 2, length))
    f.write(struct.pack("<I4s", len(json_chunk), b"JSON"))
    f.write(json_chunk)
    f.write(struct.pack("<I4s", len(bin_chunk), b"BIN\x00"))
    f.write(bin_chunk)

print(OUT)
