#!/usr/bin/env python3
"""Generate glTF roughness/AO fixtures for lightweight material detail tests."""
import argparse
import json
from pathlib import Path
import struct
import sys
sys.dont_write_bytecode=True
from generate_normal_fixtures import generate as base
from generate_surface_maps import png

def generate(kind):
    source=base('flat');size=struct.unpack_from('<I',source,12)[0]
    doc=json.loads(source[20:20+size]);binary=bytearray(source[28+size:]);mat=doc['materials'][0]
    mat['pbrMetallicRoughness']['roughnessFactor']=.2 if kind=='smooth' else .8
    if kind=='mapped':
        data=png(2,2,bytes([128,64,0,255])*4);idx=len(doc['bufferViews'])
        doc['bufferViews'].append(dict(buffer=0,byteOffset=len(binary),byteLength=len(data)))
        binary.extend(data);binary.extend(b'\0'*(-len(binary)%4))
        doc['images']=[dict(bufferView=idx,mimeType='image/png')];doc['textures']=[dict(source=0)]
        mat['pbrMetallicRoughness']['metallicRoughnessTexture']=dict(index=0)
        mat['occlusionTexture']=dict(index=0,strength=1)
    doc['buffers'][0]['byteLength']=len(binary)
    payload=json.dumps(doc,separators=(',',':')).encode();payload+=b' '*(-len(payload)%4)
    return struct.pack('<III',0x46546C67,2,28+len(payload)+len(binary))+struct.pack('<I4s',len(payload),b'JSON')+payload+struct.pack('<I4s',len(binary),b'BIN\0')+binary

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true');args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]/'assets/tests/surface'
    if not args.check:root.mkdir(parents=True,exist_ok=True)
    for kind in ('smooth','rough','mapped'):
        path=root/(kind+'.glb');data=generate(kind)
        if args.check:
            if path.read_bytes()!=data:raise SystemExit('Out of date: '+str(path))
        else:path.write_bytes(data)
