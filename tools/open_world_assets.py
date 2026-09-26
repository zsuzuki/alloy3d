"""Original rural-valley meshes and a small glTF writer with shared texture buffers."""
import json
import math
import random
import struct
from pathlib import Path
from generate_forest_assets import Mesh, unit, add, mul, cross

ATLAS = 'material-atlas.png'
FOLIAGE = 'foliage-atlas.png'
MEADOW = 'meadow.png'


def uv(tile, p, foliage=False):
    cols, rows = (2, 2) if foliage else (4, 2)
    # Leave a gutter inside each generated swatch for bilinear/mipmap filtering.
    return ((tile % cols + .045 + p[0] * .91) / cols,
            (tile // cols + .045 + p[1] * .91) / rows)


def tri(m, a, b, c, tile=4, color=(1, 1, 1), coords=((0, 1), (1, 1), (.5, 0))):
    m.tri(a, b, c, color, tuple(uv(tile, p) for p in coords))


def quad(m, a, b, c, d, tile=4, color=(1, 1, 1)):
    coords = ((0, 1), (1, 1), (1, 0), (0, 0))
    for ids in ((0, 1, 2), (0, 2, 3)):
        m.tri(*[(a, b, c, d)[i] for i in ids], color, tuple(uv(tile, coords[i]) for i in ids))


def box(m, x, y, z, sx, sy, sz, tile=5, color=(1, 1, 1)):
    p = [(x+a*sx, y+b*sy, z+c*sz) for a, b, c in
         [(-.5,0,-.5),(.5,0,-.5),(.5,0,.5),(-.5,0,.5),(-.5,1,-.5),(.5,1,-.5),(.5,1,.5),(-.5,1,.5)]]
    for ids in ((0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)):
        quad(m, *(p[i] for i in ids), tile, color)


def tube(m, a, b, r0, r1, sides=7, color=(1, 1, 1)):
    start = len(m.p)
    m.tube(a, b, r0, r1, color, sides, bark_uv=True)
    m.uv[start:] = [uv(3, (u / 3, v % 1)) for u, v in m.uv[start:]]


def card(m, center, side, up, tile, color=(1, 1, 1), normal=None):
    p = [add(center, add(mul(side, sx), mul(up, sy))) for sx, sy in [(-1,-1),(1,-1),(1,1),(-1,1)]]
    coords = ((0,1),(1,1),(1,0),(0,0))
    for ids in ((0,1,2),(0,2,3)):
        m.tri(*(p[i] for i in ids), color, tuple(uv(tile, coords[i], True) for i in ids))
        if normal is not None:
            m.n[-3:] = [normal]*3


def tree(pine=False, low=False):
    wood, leaves = Mesh(), Mesh()
    rng = random.Random(617 + pine)
    tube(wood, (0,-.3,0), (.25,14 if pine else 10,0), .42, .08, 6 if low else 9)
    if pine:
        for level in range(5 if low else 8):
            y = 4 + level * (1.75 if low else 1.15)
            radius = (15-y)*.34
            for branch in range(3 if low else 5):
                a = branch*2*math.pi/(3 if low else 5)+level*1.3
                direction = (math.cos(a), .15, math.sin(a))
                end = (direction[0]*radius, y+.6, direction[2]*radius)
                if not low:
                    tube(wood, (0,y,0), end, .09, .015, 5)
                center = (end[0]*.55, y+.6, end[2]*.55)
                card(leaves, center, (math.cos(a)*radius*.8, .1, math.sin(a)*radius*.8),
                     (-math.sin(a)*radius*.35, .75, math.cos(a)*radius*.35), 2, (.8,.93,.78), (0,.8,0.6))
                card(leaves, center, (-math.sin(a)*radius*.6, 0, math.cos(a)*radius*.6),
                     (math.cos(a)*.4, 1.25, math.sin(a)*.4), 2, (.85,1,.8), (0,1,0))
    else:
        for b in range(5 if low else 9):
            a = b*2.399
            h = 5.5 + (b%3)*1.5
            r = 3.5 if b%3 != 2 else 2.4
            end = (math.cos(a)*r, h+2.2, math.sin(a)*r)
            tube(wood, (0,h-2,0), end, .19, .04, 5 if low else 7)
            for cluster in range(2 if low else 5):
                c = add(end, (rng.uniform(-1.9,1.9), rng.uniform(-.6,2.0), rng.uniform(-1.9,1.9)))
                for plane in range(2 if low else 3):
                    angle = a + plane*math.pi/3
                    card(leaves, c, (math.cos(angle)*2, 0, math.sin(angle)*2),
                         (.25,1.5,.15) if plane < 2 else (1, .5, 1.2), b%2,
                         (.85+rng.random()*.15, .9+rng.random()*.1, .8), unit((c[0]*.1,.8,c[2]*.1)))
    return [(wood, ATLAS, False), (leaves, FOLIAGE, True)]


def house(variant=0, low=False):
    m = Mesh()
    height = 5.8 if variant else 4.6
    box(m, 0,-1,0, 10.6,1.5,8.6, 7, (.9,.9,.87))
    box(m, 0,.5,0, 10,height,8, 4, (1,.94,.82) if not variant else (.84,.91,.91))
    # Gabled roof with eaves, visible fascia and ridge cap.
    a,b,c,d = [(-5.8,height+.35,-4.7),(5.8,height+.35,-4.7),(5.8,height+.35,4.7),(-5.8,height+.35,4.7)]
    e,f = (0,height+4.1,-4.7),(0,height+4.1,4.7)
    quad(m,a,d,f,e,6, (.9,.87,.81)); quad(m,e,f,c,b,6, (.9,.87,.81))
    tri(m,(-5,height+.5,-4),(5,height+.5,-4),(0,height+3.75,-4),4,(.95,.87,.72))
    tri(m,(5,height+.5,4),(-5,height+.5,4),(0,height+3.75,4),4,(.95,.87,.72))
    box(m,0,height+4.05,0,.28,.18,9.6,6)
    if low:
        return [(m, ATLAS, False)]
    for x in (-4.9, 0, 4.9):
        for z in (-4.04,4.04): box(m,x,.4,z,.22,height+.15,.22,5,(.55,.48,.4))
    for z in (-4.06,4.06):
        box(m,0,height+.22,z,10.2,.22,.24,5,(.6,.52,.43))
        box(m,0,1.05,z,10.2,.15,.14,5,(.7,.6,.5))
    # Windows are dark glass set inside projecting frames and open shutters.
    for z in (-4.12,4.12):
        for x in (-2.9,2.9):
            box(m,x,1.95,z,1.6,1.75,.12,4,(.055,.12,.15))
            for dx in (-.86,.86):
                box(m,x+dx,1.85,z,.14,1.95,.25,5,(.75,.65,.5))
                box(m,x+dx*1.55,1.94,z,.65,1.77,.15,5,(.36,.49,.41))
            for h in (1.85,2.8,3.72): box(m,x,h,z,1.82,.11,.27,5,(.8,.7,.55))
            box(m,x,1.9,z,.08,1.84,.28,5)
            box(m,x,1.72,z,2.1,.13,.48,7)
            if variant:
                box(m,x,4.35,z,1.15,1.1,.15,4,(.06,.12,.14))
    box(m,0,.5,-4.13,1.65,2.9,.18,5,(.6,.52,.44))
    for x in (-.93,.93): box(m,x,.48,-4.25,.18,3.1,.35,7)
    box(m,0,3.48,-4.25,2.05,.25,.35,7)
    for i in range(3): box(m,0,i*.17,-4.4-(2-i)*.5,2.6,.18,1.7,7)
    # Small porch canopy, posts and a masonry chimney.
    quad(m,(-1.7,3.6,-6.2),(1.7,3.6,-6.2),(1.7,4.05,-3.95),(-1.7,4.05,-3.95),6)
    for x in (-1.5,1.5): box(m,x,.1,-6,.16,3.5,.16,5)
    box(m,2.6,height+1.5,1.7,1.1,3.2,1.1,7)
    box(m,2.6,height+4.5,1.7,1.4,.25,1.4,7,(.75,.74,.7))
    return [(m, ATLAS, False)]


def rock(low=False):
    m = Mesh(); rng=random.Random(825)
    rings=[]; sides=5 if low else 9
    for y,r in ((-.3,1),(.65,1.3),(1.65,.8),(2,.1)):
        rings.append([(math.cos(a*2*math.pi/sides)*r*rng.uniform(.8,1.2),y+rng.uniform(-.15,.15),
                       math.sin(a*2*math.pi/sides)*r*rng.uniform(.8,1.2)) for a in range(sides)])
    for j in range(3):
        for i in range(sides): quad(m,rings[j][i],rings[j][(i+1)%sides],rings[j+1][(i+1)%sides],rings[j+1][i],2,(.83,.85,.8))
    return [(m,ATLAS,False)]


def grass():
    m = Mesh(); rng = random.Random(2407)
    for i in range(7):
        a = i*2.399; r = rng.uniform(.0,1.1); h = rng.uniform(.35,.8)
        card(m, (math.cos(a)*r,h*.5,math.sin(a)*r), (math.cos(a)*.55,0,math.sin(a)*.55),
             (0,h*.5,0), 3, (.78,.95,.68), (0,1,0))
    return [(m,FOLIAGE,True)]


def bridge(center, z, water, half=56):
    m = Mesh(); deck = water+5
    def top(x): return deck+1.3*(1-(x/half)**2)
    for i in range(28):
        x0=-half+i*4; x1=x0+4
        y0,y1=top(x0),top(x1)
        quad(m,(center+x0,y0,z-4),(center+x0,y0,z+4),(center+x1,y1,z+4),(center+x1,y1,z-4),7,(.94,.91,.81))
        for side in (-1,1):
            zz=z+side*4.3
            # Repeating arch apertures: solid stone above the curved soffit.
            a0=((x0+half)% (half*2/3))/(half/3)-1
            a1=((x1+half-1e-5)% (half*2/3))/(half/3)-1
            low0=water+.7+3*math.sqrt(max(0,1-a0*a0)); low1=water+.7+3*math.sqrt(max(0,1-a1*a1))
            quad(m,(center+x0,low0,zz),(center+x1,low1,zz),(center+x1,y1,zz),(center+x0,y0,zz),7,(.76,.78,.74))
            quad(m,(center+x0,y0,zz),(center+x1,y1,zz),(center+x1,y1+1,zz),(center+x0,y0+1,zz),7,(.86,.87,.82))
            quad(m,(center+x0,y0+1,zz-.35),(center+x1,y1+1,zz-.35),(center+x1,y1+1,zz+.35),(center+x0,y0+1,zz+.35),7)
    for i in range(4):
        xx=center-half+i*half*2/3
        box(m,xx,water-4,z,2.5,9,9,7,(.7,.73,.7))
    return m


def save(path, parts):
    """glTF 2.0: geometry in GLB, PNG bytes in shared external *buffers*.

    Images use bufferViews, supported by Alloy3D's existing cgltf loader. This
    avoids repeated embedded atlases without adding a new library API.
    """
    data=bytearray(); views=[]; acc=[]; primitives=[]; materials=[]; buffers=[{}]; images=[]; textures=[]
    texture_ids={}
    for m,texture,mask in parts:
        if not m.p: continue
        attrs={}
        for name,values,size in [('POSITION',m.p,3),('NORMAL',m.n,3),('COLOR_0',m.c,4),('TEXCOORD_0',m.uv,2)]:
            raw=struct.pack('<'+'f'*(len(values)*size),*(x for v in values for x in v))
            views.append(dict(buffer=0,byteOffset=len(data),byteLength=len(raw)));data.extend(raw)
            accessor=dict(bufferView=len(views)-1,componentType=5126,count=len(values),type=f'VEC{size}')
            if name=='POSITION': accessor.update(min=[min(p[i] for p in values) for i in range(3)],max=[max(p[i] for p in values) for i in range(3)])
            attrs[name]=len(acc);acc.append(accessor)
        material=dict(doubleSided=True,alphaMode='MASK' if mask else 'OPAQUE',pbrMetallicRoughness=dict(baseColorFactor=[1,1,1,1],metallicFactor=0,roughnessFactor=.85))
        if mask: material['alphaCutoff']=.4
        if texture:
            if texture not in texture_ids:
                ti=len(textures);texture_ids[texture]=ti
                length=(path.parent/texture).stat().st_size
                buffers.append(dict(uri=texture,byteLength=length))
                views.append(dict(buffer=len(buffers)-1,byteOffset=0,byteLength=length))
                images.append(dict(bufferView=len(views)-1,mimeType='image/png'));textures.append(dict(source=ti,sampler=1 if texture==MEADOW else 0))
            material['pbrMetallicRoughness']['baseColorTexture']=dict(index=texture_ids[texture])
        primitives.append(dict(attributes=attrs,material=len(materials)));materials.append(material)
    buffers[0]=dict(byteLength=len(data))
    doc=dict(asset=dict(version='2.0',generator='Alloy3D original river valley'),scene=0,scenes=[dict(nodes=[0])],nodes=[dict(mesh=0)],meshes=[dict(primitives=primitives)],buffers=buffers,bufferViews=views,accessors=acc,materials=materials)
    if textures:doc.update(images=images,textures=textures,samplers=[dict(wrapS=33071,wrapT=33071,magFilter=9729,minFilter=9987),dict(wrapS=10497,wrapT=10497,magFilter=9729,minFilter=9987)])
    payload=json.dumps(doc,separators=(',',':')).encode();payload+=b' '*(-len(payload)%4)
    path.write_bytes(struct.pack('<III',0x46546C67,2,28+len(payload)+len(data))+struct.pack('<I4s',len(payload),b'JSON')+payload+struct.pack('<I4s',len(data),b'BIN\0')+data)
