#!/usr/bin/env python3
"""Generate tiny original GLBs for normals, instancing and transparency tests."""
import argparse
import json
import math
from pathlib import Path
import struct
import zlib


def generate(kind):
    binary = bytearray()
    views, accessors = [], []

    def accessor(values, width, fmt='f'):
        raw = struct.pack('<' + fmt * len(values), *values)
        views.append(dict(buffer=0, byteOffset=len(binary), byteLength=len(raw)))
        binary.extend(raw)
        binary.extend(b'\0' * (-len(binary) % 4))
        item = dict(bufferView=len(views)-1, componentType=5126 if fmt == 'f' else 5123,
                    count=len(values)//width, type={1:'SCALAR', 3:'VEC3', 4:'VEC4'}[width])
        if width == 3:
            item['min'] = [min(values[i::width]) for i in range(width)]
            item['max'] = [max(values[i::width]) for i in range(width)]
        accessors.append(item)
        return len(accessors)-1

    positions = [-.2, -.2, 0, .2, -.2, -.4, 0, .2, -.6]
    attrs = dict(POSITION=accessor(positions, 3), NORMAL=accessor([1/math.sqrt(3)]*9, 3))
    indices = accessor([0,1,2], 1, 'H')
    prims = [dict(attributes=attrs, indices=indices, material=0)]
    materials = [dict(pbrMetallicRoughness=dict(baseColorFactor=[1,1,1,1]))]
    nodes = [dict(name='TiltedTriangle', mesh=0, scale=[.8,1.2,.6], translation=[0,0,.6])]
    doc = dict(asset=dict(version='2.0', generator='Alloy3D generate_render_fixtures.py'),
               scene=0, scenes=[dict(nodes=[0])], nodes=nodes, meshes=[dict(primitives=prims)],
               materials=materials, bufferViews=views, accessors=accessors)
    if kind == 'skinned_normals':
        attrs['JOINTS_0'] = accessor([0,1,0,0]*3, 4, 'H')
        attrs['WEIGHTS_0'] = accessor([.25,.75,0,0]*3, 4)
        nodes[0] = dict(name='SkinnedTriangle', mesh=0, skin=0)
        nodes += [dict(name='JointA', scale=[.5,1.5,.3], translation=[0,0,.6]),
                  dict(name='JointB', scale=[.9,1.1,.7], translation=[0,0,.6])]
        doc['skins'] = [dict(joints=[1,2])]
        doc['scenes'][0]['nodes'] = [0,1,2]
    if kind in ('opaque_parts', 'transparent_parts', 'textured_parts'):
        positions2 = [v + (.06 if i % 3 == 0 else -.06 if i % 3 == 2 else 0)
                      for i,v in enumerate(positions)]
        prims.append(dict(attributes=dict(POSITION=accessor(positions2,3), NORMAL=attrs['NORMAL']),
                          indices=indices, material=1))
        alpha = .5 if kind == 'transparent_parts' else 1
        materials[:] = [dict(pbrMetallicRoughness=dict(baseColorFactor=[1,.2,.1,alpha]),
                            alphaMode='BLEND' if alpha < 1 else 'OPAQUE'),
                        dict(pbrMetallicRoughness=dict(baseColorFactor=[.1,.3,1,alpha]),
                            alphaMode='BLEND' if alpha < 1 else 'OPAQUE')]
    if kind == 'textured_parts':
        def chunk(name, data):
            return struct.pack('>I',len(data)) + name + data + struct.pack('>I',zlib.crc32(name+data))
        png = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR',struct.pack('>IIBBBBB',1,1,8,6,0,0,0))
               + chunk(b'IDAT',zlib.compress(bytes([0,255,255,255,128]))) + chunk(b'IEND',b''))
        doc['images'] = [dict(bufferView=len(views), mimeType='image/png')]
        doc['textures'] = [dict(source=0)]
        views.append(dict(buffer=0, byteOffset=len(binary), byteLength=len(png)))
        binary.extend(png)
        binary.extend(b'\0' * (-len(binary) % 4))
        for material in materials:
            material['pbrMetallicRoughness']['baseColorTexture'] = dict(index=0)
    doc['buffers'] = [dict(byteLength=len(binary))]
    payload = json.dumps(doc, separators=(',',':')).encode()
    payload += b' ' * (-len(payload) % 4)
    return (struct.pack('<III', 0x46546C67, 2, 28+len(payload)+len(binary))
            + struct.pack('<I4s',len(payload), b'JSON') + payload
            + struct.pack('<I4s',len(binary), b'BIN\0') + binary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1] / 'assets/tests/rendering'
    for kind in ('normals', 'skinned_normals', 'opaque_parts', 'transparent_parts', 'textured_parts'):
        path = root / (kind + '.glb')
        data = generate(kind)
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                raise SystemExit(f'Out of date: {path}')
        else:
            path.write_bytes(data)
        print(f'{kind}: {len(data)} bytes')


if __name__ == '__main__':
    main()
