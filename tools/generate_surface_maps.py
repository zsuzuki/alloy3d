#!/usr/bin/env python3
"""Generate deterministic tangent-space data maps from periodic height functions.

These are procedural surface data, independent of the generated color artwork.
Only Python's standard library is required. No network access or image service.
"""
import argparse
import math
from pathlib import Path
import struct
import zlib

def png(width, height, pixels):
    def chunk(name, data):
        return struct.pack('>I', len(data)) + name + data + struct.pack('>I', zlib.crc32(name + data))
    rows = b''.join(b'\0' + bytes(pixels[y*width*4:(y+1)*width*4]) for y in range(height))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))

def normal_map(kind, size=256):
    def height(u, v):
        a, b = math.tau*u, math.tau*v
        if kind == 'bark':
            return .011*math.sin(19*a+.6*math.sin(3*b))+.003*math.sin(47*a+2*math.sin(b))
        if kind == 'water':
            return .005*math.sin(7*a+3*b)+.003*math.sin(3*a-5*b)+.001*math.sin(19*a+11*b)
        return .004*math.sin(13*a+9*b)+.003*math.sin(7*a-17*b)+.0015*math.sin(43*a+31*b)
    pixels = bytearray()
    step = 1/size
    for y in range(size):
        for x in range(size):
            u, v = x/size, y/size
            du = (height(u+step,v)-height(u-step,v))/(2*step)
            dv = (height(u,v+step)-height(u,v-step))/(2*step)
            length = math.sqrt(du*du+dv*dv+1)
            pixels.extend([round(127.5*(1-du/length)), round(127.5*(1-dv/length)), round(127.5*(1+1/length)), 255])
    return png(size,size,pixels)

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]/'assets/samples/forest/textures'
    for kind in ('ground','rock','bark','water'):
        path=root/(kind+'_normal.png'); data=normal_map(kind)
        if args.check:
            if path.read_bytes()!=data: raise SystemExit('Out of date: '+str(path))
        else: path.write_bytes(data)
        print(f'{kind}: {len(data)} bytes')
