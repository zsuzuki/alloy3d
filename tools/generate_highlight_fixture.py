#!/usr/bin/env python3
"""Generate the original smooth sphere used to inspect simple highlights."""
import argparse
import json
import math
from pathlib import Path
import struct


def generate():
    slices, stacks = 64, 32
    vertices, indices = [], []
    for j in range(stacks + 1):
        theta = math.pi * j / stacks
        for i in range(slices + 1):
            phi = 2 * math.pi * i / slices
            vertices.extend((math.sin(theta) * math.cos(phi), math.cos(theta),
                             math.sin(theta) * math.sin(phi)))
    for j in range(stacks):
        for i in range(slices):
            a = j * (slices + 1) + i
            b = a + slices + 1
            if j != stacks - 1:
                indices.extend((a, b + 1, b))
            if j != 0:
                indices.extend((a, a + 1, b + 1))
    data = struct.pack('<' + 'f' * len(vertices), *vertices)
    vertex_bytes = len(data)
    data += struct.pack('<' + 'H' * len(indices), *indices)
    data += b'\0' * (-len(data) % 4)
    doc = dict(asset=dict(version='2.0', generator='Alloy3D generate_highlight_fixture.py'),
               scene=0, scenes=[dict(nodes=[0])], nodes=[dict(mesh=0)],
               meshes=[dict(primitives=[dict(attributes=dict(POSITION=0, NORMAL=0),
                                             indices=1, material=0)])],
               materials=[dict(pbrMetallicRoughness=dict(baseColorFactor=[.15, .35, .65, 1]))],
               buffers=[dict(byteLength=len(data))],
               bufferViews=[dict(buffer=0, byteOffset=0, byteLength=vertex_bytes),
                            dict(buffer=0, byteOffset=vertex_bytes, byteLength=len(indices) * 2)],
               accessors=[dict(bufferView=0, componentType=5126, count=len(vertices) // 3,
                               type='VEC3', min=[-1,-1,-1], max=[1,1,1]),
                          dict(bufferView=1, componentType=5123, count=len(indices), type='SCALAR')])
    payload = json.dumps(doc, separators=(',', ':')).encode()
    payload += b' ' * (-len(payload) % 4)
    return (struct.pack('<III', 0x46546C67, 2, 28 + len(payload) + len(data))
            + struct.pack('<I4s', len(payload), b'JSON') + payload
            + struct.pack('<I4s', len(data), b'BIN\0') + data)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    path = Path(__file__).resolve().parents[1] / 'assets/tests/highlights/sphere.glb'
    data = generate()
    if args.check:
        if not path.exists() or path.read_bytes() != data:
            raise SystemExit(f'Out of date: {path}')
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    print(f'sphere: {len(data)} bytes')
