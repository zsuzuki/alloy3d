#!/usr/bin/env python3
"""Generate original, deterministic GLBs for glTF material regression tests and viewer."""
import argparse
import json
from pathlib import Path
import struct
import zlib

KINDS = ('opaque_alpha', 'mask_checker', 'mask_cutoff', 'mask_equal', 'blend_red',
         'blend_blue', 'blend_parts', 'single_sided', 'double_sided', 'unlit',
         'mirrored_node', 'mirrored_skin', 'animated_blend')


def generate(kind):
    binary = bytearray()
    views, accessors = [], []

    def blob(raw):
        index = len(views)
        views.append(dict(buffer=0, byteOffset=len(binary), byteLength=len(raw)))
        binary.extend(raw)
        binary.extend(b'\0' * (-len(binary) % 4))
        return index

    def accessor(values, width, fmt='f'):
        item = dict(bufferView=blob(struct.pack('<' + fmt * len(values), *values)),
                    componentType=5126 if fmt == 'f' else 5123,
                    count=len(values)//width, type={1:'SCALAR', 2:'VEC2', 3:'VEC3', 4:'VEC4'}[width])
        if fmt == 'f':
            item['min'] = [min(values[i::width]) for i in range(width)]
            item['max'] = [max(values[i::width]) for i in range(width)]
        accessors.append(item)
        return len(accessors)-1

    positions = [-.5,-.5,0, .5,-.5,0, .5,.5,0, -.5,.5,0]
    attrs = dict(POSITION=accessor(positions,3), NORMAL=accessor([0,0,1]*4,3),
                 TEXCOORD_0=accessor([0,0,1,0,1,1,0,1],2))
    indices = accessor([0,1,2,0,2,3],1,'H')
    color = [.2,.4,.6,1]
    material = dict(pbrMetallicRoughness=dict(baseColorFactor=color, metallicFactor=0, roughnessFactor=1))
    materials = [material]
    prims = [dict(attributes=attrs, indices=indices, material=0)]
    nodes = [dict(mesh=0, name=kind)]
    doc = dict(asset=dict(version='2.0', generator='Alloy3D generate_material_fixtures.py'),
               scene=0, scenes=[dict(nodes=[0])], nodes=nodes, meshes=[dict(primitives=prims)],
               materials=materials, bufferViews=views, accessors=accessors)
    if kind == 'double_sided':
        material['doubleSided'] = True
    if kind in ('unlit', 'opaque_alpha', 'mask_checker', 'mask_cutoff', 'mask_equal',
                'blend_red', 'blend_blue', 'blend_parts', 'animated_blend'):
        doc['extensionsUsed'] = ['KHR_materials_unlit']
        material['extensions'] = dict(KHR_materials_unlit={})
    if kind.startswith('blend_') or kind == 'animated_blend':
        material['alphaMode'] = 'BLEND'
        color[:] = [0,0,1,.5] if kind == 'blend_blue' else [1,0,0,.5]
    if kind == 'opaque_alpha':
        color[:] = [1,0,0,.125]
        attrs['COLOR_0'] = accessor([1,1,1,.5]*4,4)
    if kind.startswith('mask_'):
        material['alphaMode'] = 'MASK'
        color[:] = [0,1,0,.8]
        attrs['COLOR_0'] = accessor([1,1,1,.75]*4,4)
        if kind == 'mask_cutoff':
            material['alphaCutoff'] = .7
        if kind == 'mask_equal':
            color[3] = .5
            del attrs['COLOR_0']
    if kind in ('opaque_alpha','mask_checker','mask_cutoff'):
        def chunk(name, data):
            return struct.pack('>I',len(data)) + name + data + struct.pack('>I',zlib.crc32(name+data))
        pixels = bytearray()
        for y in range(8):
            pixels.append(0)
            for x in range(8):
                alpha = 64 if kind == 'opaque_alpha' else 255 if (x//2+y//2)%2 else 0
                pixels.extend([255,255,255,alpha])
        png = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR',struct.pack('>IIBBBBB',8,8,8,6,0,0,0))
               + chunk(b'IDAT',zlib.compress(pixels)) + chunk(b'IEND',b''))
        doc['images'] = [dict(bufferView=blob(png),mimeType='image/png')]
        doc['textures'] = [dict(source=0)]
        material['pbrMetallicRoughness']['baseColorTexture'] = dict(index=0)
    if kind == 'blend_parts':
        # Intentionally near-first mesh order; renderer must sort parts far-first.
        attrs['POSITION'] = accessor([v+(.3 if i%3==2 else 0) for i,v in enumerate(positions)],3)
        second = dict(POSITION=accessor([v+(.7 if i%3==2 else 0) for i,v in enumerate(positions)],3),
                      NORMAL=attrs['NORMAL'])
        prims.append(dict(attributes=second, indices=indices, material=1))
        materials.append(dict(pbrMetallicRoughness=dict(baseColorFactor=[0,0,1,.5]),
                              alphaMode='BLEND', extensions=dict(KHR_materials_unlit={})))
    if kind == 'mirrored_node':
        nodes[0]['scale'] = [-1,1,1]
    if kind in ('mirrored_skin','animated_blend'):
        nodes[0]['skin'] = 0
        nodes.append(dict(name='Joint', scale=[-1 if kind == 'mirrored_skin' else 1,1,1]))
        doc['scenes'][0]['nodes'].append(1)
        doc['skins'] = [dict(joints=[1])]
        attrs['JOINTS_0'] = accessor([0,0,0,0]*4,4,'H')
        attrs['WEIGHTS_0'] = accessor([1,0,0,0]*4,4)
        if kind == 'animated_blend':
            doc['animations'] = [dict(name='Depth',samplers=[dict(input=accessor([0,1,2],1),
                output=accessor([0,0,.2, 0,0,.8, 0,0,.2],3), interpolation='LINEAR')],
                channels=[dict(sampler=0,target=dict(node=1,path='translation'))])]
    doc['buffers'] = [dict(byteLength=len(binary))]
    payload = json.dumps(doc,separators=(',',':')).encode()
    payload += b' ' * (-len(payload)%4)
    return (struct.pack('<III',0x46546C67,2,28+len(payload)+len(binary))
            + struct.pack('<I4s',len(payload),b'JSON') + payload
            + struct.pack('<I4s',len(binary),b'BIN\0') + binary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1] / 'assets/tests/materials'
    if not args.check:
        root.mkdir(parents=True,exist_ok=True)
    for kind in KINDS:
        path = root / (kind+'.glb')
        data = generate(kind)
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                raise SystemExit(f'Out of date: {path}')
        else:
            path.write_bytes(data)
        print(f'{kind}: {len(data)} bytes')


if __name__ == '__main__':
    main()
