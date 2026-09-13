#!/usr/bin/env python3
"""Generate repository-owned embedded PNG textures for mipmap regression tests."""
import argparse
import json
from pathlib import Path
import struct
import sys
import zlib

sys.dont_write_bytecode = True
from generate_material_fixtures import generate as material_fixture


def generate(kind):
    source = material_fixture('unlit')
    json_size = struct.unpack_from('<I', source, 12)[0]
    doc = json.loads(source[20:20 + json_size])
    binary = bytearray(source[28 + json_size:])
    width, height = {'checker': (1024, 1024), 'anisotropic': (512, 512), 'npot': (30, 18),
                     'single': (1, 1), 'mask_dense': (64, 64),
                     'mask_sparse': (64, 64)}[kind]
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            if kind == 'checker':
                v = 255 if (x + y) % 2 else 0
                pixel = (v, v, v, 255)
            elif kind == 'anisotropic':
                v = 255 if (x // 4) % 2 else 0
                pixel = (v, v, v, 255)
            elif kind.startswith('mask_'):
                # 75% and 25% coverage; ordinary mipmaps average the alpha.
                covered = bool(x % 2 or y % 2)
                if kind == 'mask_sparse':
                    covered = not covered
                pixel = (255, 255, 255, 255 if covered else 0)
            else:
                pixel = (64, 128, 192, 255)
            rows.extend(pixel)

    def chunk(name, data):
        return (struct.pack('>I', len(data)) + name + data
                + struct.pack('>I', zlib.crc32(name + data)))

    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))
    doc['images'] = [dict(bufferView=len(doc['bufferViews']), mimeType='image/png')]
    doc['bufferViews'].append(dict(buffer=0, byteOffset=len(binary), byteLength=len(png)))
    binary.extend(png)
    binary.extend(b'\0' * (-len(binary) % 4))
    doc['textures'] = [dict(source=0)]
    material = doc['materials'][0]
    material['pbrMetallicRoughness']['baseColorFactor'] = [1, 1, 1, 1]
    material['pbrMetallicRoughness']['baseColorTexture'] = dict(index=0)
    if kind.startswith('mask_'):
        material['alphaMode'] = 'MASK'
        material['alphaCutoff'] = .5
    doc['buffers'][0]['byteLength'] = len(binary)
    doc['asset']['generator'] = 'Alloy3D generate_mipmap_fixtures.py'
    payload = json.dumps(doc, separators=(',', ':')).encode()
    payload += b' ' * (-len(payload) % 4)
    return (struct.pack('<III', 0x46546C67, 2, 28 + len(payload) + len(binary))
            + struct.pack('<I4s', len(payload), b'JSON') + payload
            + struct.pack('<I4s', len(binary), b'BIN\0') + binary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1] / 'assets/tests/mipmaps'
    if not args.check:
        root.mkdir(parents=True, exist_ok=True)
    for kind in ('checker', 'npot', 'single', 'mask_dense', 'mask_sparse', 'anisotropic'):
        path, data = root / (kind + '.glb'), generate(kind)
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                raise SystemExit(f'Out of date: {path}')
        else:
            path.write_bytes(data)
        print(f'{kind}: {len(data)} bytes')


if __name__ == '__main__':
    main()
