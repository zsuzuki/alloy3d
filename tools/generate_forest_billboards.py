#!/usr/bin/env python3
"""Package original crown renders as MASK billboards; optional explicit Metal rebake."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
from generate_forest_assets import Mesh, ROOT

IMAGES = ROOT / 'billboards'

def sources():
    names = [stem+suffix+'.glb' for suffix in ('','_2','_3') for stem in ('crown','leaves')]
    return {name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in names}

def update(check=False, bake=None, shaders=None):
    if bake:
        if check or not shaders:
            raise SystemExit('--bake needs --shaders and cannot be combined with --check')
        before = sources()
        subprocess.run([str(Path(bake).resolve()),str(Path(shaders).resolve()),str(ROOT),str(IMAGES)],check=True)
        if before != sources():
            raise SystemExit('Crown sources changed while baking')
        manifest = dict(sources=before,images={p.name:hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(IMAGES.glob('*.png'))})
        (IMAGES/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    manifest = json.loads((IMAGES/'manifest.json').read_text())
    if manifest['sources'] != sources():
        raise SystemExit('Billboard sources changed: run the documented Metal rebake command')
    frames = json.loads((IMAGES/'frames.json').read_text())
    for variant,frame in enumerate(frames,1):
        half = frame['size']/2
        bottom,top = frame['center_y']-half,frame['center_y']+half
        for view in range(8):
            image_name = f'crown_{variant}_{view}.png'
            texture = (IMAGES/image_name).read_bytes()
            if hashlib.sha256(texture).hexdigest() != manifest['images'][image_name]:
                raise SystemExit('Billboard texture differs from bake manifest: '+image_name)
            mesh = Mesh()
            a,b,c,d = (-half,bottom,0),(half,bottom,0),(half,top,0),(-half,top,0)
            mesh.tri(a,b,c,(1,1,1),((0,1),(1,1),(1,0)))
            mesh.tri(a,c,d,(1,1,1),((0,1),(1,0),(0,0)))
            data = mesh.glb(unlit=True,texture=texture,mask=True)
            path = ROOT/f'billboard_{variant}_{view}.glb'
            if check:
                if not path.exists() or path.read_bytes()!=data:
                    raise SystemExit('Out of date: '+str(path))
            else:
                path.write_bytes(data)
    print('PASS: 24 billboard GLBs and source/texture hashes')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    parser.add_argument('--bake',metavar='BAKER_EXECUTABLE')
    parser.add_argument('--shaders',metavar='SHADERS_METALLIB')
    args=parser.parse_args()
    update(args.check,args.bake,args.shaders)
