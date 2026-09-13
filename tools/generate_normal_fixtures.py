#!/usr/bin/env python3
"""Deterministic glTF normal-map regression fixtures."""
import argparse
import json
from pathlib import Path
import struct
import sys
sys.dont_write_bytecode = True
from generate_material_fixtures import generate as base
from generate_surface_maps import png

KINDS = ('flat','tilted','zero_scale','tangent','mirrored_uv','degenerate_uv','blend','mask','unlit','skin')
def generate(kind):
    source=base('mirrored_skin' if kind=='skin' else 'unlit')
    size=struct.unpack_from('<I',source,12)[0]
    doc=json.loads(source[20:20+size]); binary=bytearray(source[28+size:])
    mat=doc['materials'][0]
    mat['pbrMetallicRoughness']['baseColorFactor']=[1,1,1,1]
    mat['doubleSided']=True
    if kind!='unlit':
        mat.pop('extensions',None); doc.pop('extensionsUsed',None)
    def append(data):
        idx=len(doc['bufferViews'])
        doc['bufferViews'].append(dict(buffer=0,byteOffset=len(binary),byteLength=len(data)))
        binary.extend(data); binary.extend(b'\0'*(-len(binary)%4))
        return idx
    attrs=doc['meshes'][0]['primitives'][0]['attributes']
    if kind=='tangent':
        count=doc['accessors'][attrs['POSITION']]['count']
        idx=append(struct.pack('<'+'f'*count*4,*([1,0,0,1]*count)))
        attrs['TANGENT']=len(doc['accessors'])
        doc['accessors'].append(dict(bufferView=idx,componentType=5126,count=count,type='VEC4'))
    if kind in ('mirrored_uv','degenerate_uv'):
        accessor=doc['accessors'][attrs['TEXCOORD_0']]
        offset=doc['bufferViews'][accessor['bufferView']]['byteOffset']+accessor.get('byteOffset',0)
        for i in range(accessor['count']):
            u,v=struct.unpack_from('<ff',binary,offset+i*8)
            struct.pack_into('<ff',binary,offset+i*8,1-u if kind=='mirrored_uv' else 0,v if kind=='mirrored_uv' else 0)
    if kind!='flat':
        idx=append(png(2,2,bytes([204,128,230,255])*4))
        doc.setdefault('images',[]).append(dict(bufferView=idx,mimeType='image/png'))
        tex=len(doc.setdefault('textures',[])); doc['textures'].append(dict(source=len(doc['images'])-1))
        mat['normalTexture']=dict(index=tex,scale=0 if kind=='zero_scale' else 1)
    if kind=='blend':
        mat['alphaMode']='BLEND'; mat['pbrMetallicRoughness']['baseColorFactor'][3]=.5
    if kind=='mask': mat['alphaMode']='MASK'
    doc['buffers'][0]['byteLength']=len(binary)
    payload=json.dumps(doc,separators=(',',':')).encode();payload+=b' '*(-len(payload)%4)
    return (struct.pack('<III',0x46546C67,2,28+len(payload)+len(binary))+struct.pack('<I4s',len(payload),b'JSON')
            +payload+struct.pack('<I4s',len(binary),b'BIN\0')+binary)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true');args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]/'assets/tests/normals'
    if not args.check:root.mkdir(parents=True,exist_ok=True)
    for kind in KINDS:
        path=root/(kind+'.glb');data=generate(kind)
        if args.check:
            if path.read_bytes()!=data:raise SystemExit('Out of date: '+str(path))
        else:path.write_bytes(data)
        print(kind,len(data))
