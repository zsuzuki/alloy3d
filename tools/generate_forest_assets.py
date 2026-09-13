#!/usr/bin/env python3
"""Build original forest geometry with checked-in albedo maps (Python standard library)."""
import argparse
import json
import math
from pathlib import Path
import random
import struct

ROOT = Path(__file__).resolve().parents[1] / 'assets/samples/forest'
TEXTURES = ROOT / 'textures'

def albedo(name):
    return (TEXTURES / (name + '.png')).read_bytes()


def add(a, b): return tuple(x + y for x, y in zip(a, b))
def mul(a, b): return tuple(x * b for x in a)
def cross(a, b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def unit(a): return mul(a, 1 / max(1e-8, math.sqrt(sum(x*x for x in a))))
def stream_center(z): return 4.6 + 1.15*math.sin(z*.14) + .35*math.sin(z*.37)
def stream_width(z): return .90 + .18*math.sin(z*.23+.7)
def water_level(z): return -.27-.008*z

def smooth(a, b, x):
    t = max(0, min(1, (x-a)/(b-a)))
    return t*t*(3-2*t)

def height(x, z):
    base = .22*math.sin(x*.31+z*.13) + .16*math.cos(z*.37-x*.12) + .10*math.sin(x*.83+z*.49)
    d = abs(x-stream_center(z))/stream_width(z)
    channel = water_level(z)-.32+.52*smooth(.6,1.6,d)
    blend = smooth(1.6,2.6,d)
    return channel*(1-blend)+base*blend + 7.5*max(smooth(55,92,-z),smooth(28,60,abs(x)))



class Mesh:
    def __init__(self): self.p, self.n, self.c, self.uv = [], [], [], []

    def tri(self, a, b, c, colors, uv=None):
        n = unit(cross(add(b, mul(a, -1)), add(c, mul(a, -1))))
        for i, p in enumerate((a, b, c)):
            self.p.append(p)
            self.n.append(n)
            color = colors[i] if isinstance(colors[0], tuple) else colors
            self.c.append(tuple(color) if len(color) == 4 else (*color, 1))
            self.uv.append(uv[i] if uv else (p[0], p[2]))

    def leaf(self, root, tip, width, color):
        axis = add(tip, mul(root, -1))
        side = mul(unit(cross(axis, (.2, 1, .1))), width)
        center = add(root, mul(axis, .48))
        ridge = add(center, (0, width*.20, 0))
        left, right = add(center, side), add(center, mul(side, -1))
        dark = mul(color, .72)
        self.tri(root, left, ridge, dark)
        self.tri(left, tip, ridge, color)
        self.tri(tip, right, ridge, color)
        self.tri(right, root, ridge, dark)

    def tube(self, a, b, r0, r1, color, sides=10, bark_uv=False):
        axis = unit(add(b, mul(a, -1)))
        u = unit(cross(axis, (0, 0, 1)))
        v = cross(axis, u)
        for i in range(sides):
            points, coords, normals = [], [], []
            for j, p, r in ((i, a, r0), (i+1, a, r0), (i+1, b, r1), (i, b, r1)):
                angle = 2*math.pi*j/sides
                normal = add(mul(u, math.cos(angle)), mul(v, math.sin(angle)))
                points.append(add(p, mul(normal, r)))
                normals.append(normal)
                # Integral repeats around circumference avoid a wrap seam. Along-axis UV
                # stays continuous between trunk sections and follows branches/root axes.
                repeats = 3 if r0 > .2 else 1
                longitudinal = p[1] if abs(axis[1])>.9 else sum(p[k]*axis[k] for k in range(3))
                coords.append((j/sides*repeats,longitudinal/1.25))
            tint = mul(color, .82 + .18*math.sin(i*2.3)**2)
            for ids in ((0,1,2),(0,2,3)):
                self.tri(*(points[k] for k in ids),tint,
                         tuple(coords[k] for k in ids) if bark_uv else None)
                if bark_uv:
                    self.n[-3:] = [normals[k] for k in ids]

    def smooth_normals(self):
        sums = {}
        def key(p): return tuple(round(x,7) for x in p)
        for i in range(0,len(self.p),3):
            a,b,c = self.p[i:i+3]
            n = cross(add(b,mul(a,-1)),add(c,mul(a,-1)))
            for p in (a,b,c):
                k=key(p)
                sums[k]=add(sums.get(k,(0,0,0)),n)
        self.n=[unit(sums[key(p)]) for p in self.p]

    def glb(self, blend=False, unlit=False, texture=None, mask=False, normal=None, normal_scale=1, surface=None):
        data, views, acc = bytearray(), [], []
        for values, size in ((self.p, 3), (self.n, 3), (self.c, 4), (self.uv, 2)):
            flat = [x for v in values for x in v]
            raw = struct.pack('<'+'f'*len(flat), *flat)
            views.append(dict(buffer=0, byteOffset=len(data), byteLength=len(raw)))
            data.extend(raw)
            accessor = dict(bufferView=len(views)-1, componentType=5126, count=len(values), type=f'VEC{size}')
            if len(views) == 1:
                accessor.update(min=[min(v[i] for v in values) for i in range(3)],
                                max=[max(v[i] for v in values) for i in range(3)])
            acc.append(accessor)
        material = dict(doubleSided=True, alphaMode='MASK' if mask else 'BLEND' if blend else 'OPAQUE',
                        pbrMetallicRoughness=dict(baseColorFactor=[1,1,1,1], metallicFactor=0, roughnessFactor=.9))
        if mask: material['alphaCutoff'] = .35
        if unlit: material['extensions'] = {'KHR_materials_unlit': {}}
        doc = dict(asset=dict(version='2.0', generator='Alloy3D original procedural forest'),
                   scene=0, scenes=[dict(nodes=[0])], nodes=[dict(mesh=0)],
                   meshes=[dict(primitives=[dict(attributes=dict(POSITION=0, NORMAL=1, COLOR_0=2, TEXCOORD_0=3), material=0)])],
                   materials=[material], buffers=[dict(byteLength=len(data))], bufferViews=views, accessors=acc)
        if texture:
            doc['images'] = [dict(bufferView=len(views),mimeType='image/png')]
            views.append(dict(buffer=0,byteOffset=len(data),byteLength=len(texture)))
            data.extend(texture)
            data.extend(b'\0' * (-len(data)%4))
            doc['buffers'][0]['byteLength'] = len(data)
            doc['samplers'] = [dict(wrapS=10497,wrapT=10497,magFilter=9729,minFilter=9987)]
            doc['textures'] = [dict(source=0,sampler=0)]
            material['pbrMetallicRoughness']['baseColorTexture'] = dict(index=0)
        if unlit: doc['extensionsUsed'] = ['KHR_materials_unlit']
        if normal:
            index = len(doc.get('textures', []))
            doc.setdefault('images', []).append(dict(bufferView=len(views), mimeType='image/png'))
            views.append(dict(buffer=0, byteOffset=len(data), byteLength=len(normal)))
            data.extend(normal)
            data.extend(b'\0' * (-len(data) % 4))
            doc.setdefault('textures', []).append(dict(source=index))
            doc['buffers'][0]['byteLength'] = len(data)
            material['normalTexture'] = dict(index=index, scale=normal_scale)
        if surface:
            index = len(doc.get('textures', []))
            doc.setdefault('images', []).append(dict(bufferView=len(views), mimeType='image/png'))
            views.append(dict(buffer=0, byteOffset=len(data), byteLength=len(surface)))
            data.extend(surface); data.extend(b'\0' * (-len(data) % 4))
            doc.setdefault('textures', []).append(dict(source=index))
            doc['buffers'][0]['byteLength'] = len(data)
            material['pbrMetallicRoughness']['metallicRoughnessTexture'] = dict(index=index)
            material['occlusionTexture'] = dict(index=index, strength=.8)
        payload = json.dumps(doc, separators=(',', ':')).encode()
        payload += b' ' * (-len(payload) % 4)
        return struct.pack('<III', 0x46546C67, 2, 28+len(payload)+len(data)) + struct.pack('<I4s', len(payload), b'JSON') + payload + struct.pack('<I4s', len(data), b'BIN\0') + data


# Offline tree growth: four branching orders with deterministic, asymmetric crowns.
# Crown wood and leaves share a pivot at (0,4,0) so wind never separates them.
def forest_tree(variant):
    rng = random.Random(18271 + variant*7919)
    trunk, crown, leaves = Mesh(), Mesh(), Mesh()
    crown_lod, leaves_lod = Mesh(), Mesh()
    tree_height = (11.2,12.0,10.5)[variant]
    spread = (1.30,1.06,1.38)[variant]
    lean = ((.085,.025),(-.065,.06),(.035,-.08))[variant]
    branch_count = 0
    leaf_count = 0

    def center(y):
        t = max(0,y-4)
        return (lean[0]*t + .065*math.sin(y*1.1)*math.sin(math.pi*y/4),
                y, lean[1]*t + .04*math.sin(y*.7)*math.sin(math.pi*y/4))

    def bark(y):
        moss = 1-smooth(.2,2.8,y)
        return tuple(a*(1-moss)+b*moss for a,b in zip((1.02,.98,.90),(.65,.88,.46)))

    def sweep(mesh, points, radii, sides=8, repeats=1, v_start=0, flutes=0):
        rings, distance = [], v_start
        for j,p in enumerate(points):
            if j:
                distance += math.sqrt(sum(x*x for x in add(p,mul(points[j-1],-1))))
            tangent = unit(add(points[min(j+1,len(points)-1)],mul(points[max(j-1,0)],-1)))
            u = unit(cross(tangent,(0,0,1)))
            v = cross(tangent,u)
            ring = []
            for i in range(sides+1):
                phi = math.tau*i/sides
                r = radii[j]*(1+flutes*math.cos(phi*5+.4))
                point = add(p,mul(add(mul(u,math.cos(phi)),mul(v,math.sin(phi))),r))
                ring.append((point,bark(p[1]),(i/sides*repeats,distance/1.25)))
            rings.append(ring)
        for j in range(len(rings)-1):
            for i in range(sides):
                quad = (rings[j][i],rings[j][i+1],rings[j+1][i+1],rings[j+1][i])
                for ids in ((0,1,2),(0,2,3)):
                    mesh.tri(*(quad[k][0] for k in ids),tuple(quad[k][1] for k in ids),
                             tuple(quad[k][2] for k in ids))

    def leaf(root, direction, length, roll):
        nonlocal leaf_count
        leaf_count += 1
        axis = unit(direction)
        side = unit(cross(axis,(.05,1,.1)))
        side = add(mul(side,math.cos(roll)),mul(cross(axis,side),math.sin(roll)))
        normal = unit(cross(side,axis))
        tint = rng.uniform(.72,1.22)
        color = mul((.085,.225,.036),tint)
        # Far foliage retains deterministic distributed leaves and their coverage.
        if leaf_count % 2 == 0:
            leaves_lod.leaf(root,add(root,mul(axis,length*1.16)),length*.24*1.16,color)
        rows = []
        for t in (0,.30,.67,1):
            c = add(root,add(mul(axis,length*t),mul(normal,length*.10*math.sin(math.pi*t))))
            width = length*.24*math.sin(math.pi*t)**.8
            ridge = add(c,mul(normal,width*.18))
            rows.append((add(c,mul(side,-width)),ridge,add(c,mul(side,width))))
        for j in range(3):
            for k in (0,1):
                a,b,c,d = rows[j][k],rows[j][k+1],rows[j+1][k+1],rows[j+1][k]
                shade = mul(color,.86 if k==0 else 1)
                if j != 0:
                    leaves.tri(a,b,c,shade)
                if j != 2:
                    leaves.tri(a,c,d,shade)

    def grow(start, direction, length, radius, depth):
        nonlocal branch_count
        branch_count += 1
        direction = unit(direction)
        side = unit(cross(direction,(0,1,0)))
        bend = rng.uniform(-.28,.28)
        lift = rng.uniform(.12,.27) if depth==0 else rng.uniform(-.12,.17)
        # Main boughs flatten before turning upward; finer shoots seek upward space.
        points = [start]
        for k in range(1,7):
            t = k/6
            uplift = lift*t*t
            points.append(add(start,add(mul(direction,length*t),
                add((0,length*uplift,0),mul(side,length*bend*math.sin(t*math.pi*.75))))))
        radii = [max(.003,radius*(1-.92*(k/6))**.85) for k in range(7)]
        sweep(crown,points,radii,sides=(12,9,7,5)[depth])
        ids = (0,2,4,6) if depth<2 else (0,3,6)
        sweep(crown_lod,[points[k] for k in ids],[radii[k] for k in ids],sides=(8,6,4,3)[depth])
        if depth < 3:
            # Rotate branching planes in 3D; random node positions prevent repeated fans.
            nodes = sorted(rng.sample((2,3,4,5),rng.choice((2,3)))) + [6] if depth<2 else [3,5,6]
            for child,k in enumerate(nodes):
                tangent = unit(add(points[k],mul(points[k-1],-1)))
                lateral = unit(cross(tangent,(0,1,0)))
                vertical = cross(tangent,lateral)
                roll = rng.uniform(-math.pi,math.pi)
                outward = add(mul(lateral,math.cos(roll)),mul(vertical,math.sin(roll)))
                angle = rng.uniform(.55,1.15) if k<6 else rng.uniform(.15,.40)
                child_dir = unit(add(add(mul(tangent,math.cos(angle)),mul(outward,math.sin(angle))),
                                     (0,.10,0)))
                ratio = rng.uniform(.43,.60) if k<6 else rng.uniform(.40,.55)
                grow(points[k],child_dir,length*ratio,radii[k]*.78,depth+1)
        if depth >= 1:
            first = 2 if depth>=2 else 5
            phase = rng.uniform(0,math.tau)
            for k in range(first,7):
                tangent = unit(add(points[k],mul(points[k-1],-1)))
                lateral = unit(cross(tangent,(0,1,0)))
                vertical = cross(tangent,lateral)
                # Three leaves around successive twig nodes fill space without flat fern-like rows.
                for n in range(3):
                    a = phase+k*2.399+n*math.tau/3+rng.uniform(-.35,.35)
                    outward = add(mul(lateral,math.cos(a)),mul(vertical,math.sin(a)))
                    leaf_direction = add(outward,add(mul(tangent,.35),(0,.20,0)))
                    leaf(points[k],leaf_direction,rng.uniform(.23,.36),rng.uniform(-.55,.55))
            leaf(points[-1],add(direction,(0,.3,0)),rng.uniform(.24,.34),rng.uniform(-.4,.4))

    # One ring sequence is split at the crown pivot without changing its geometry or UVs.
    ys = [k*.25 for k in range(17)] + [4+(tree_height-4)*k/28 for k in range(1,29)]
    points = [center(y) for y in ys]
    radii = [.59*(1-y/(tree_height+.15))**.92*(1+.24*math.exp(-y*2)) for y in ys]
    # Generate the whole sweep first, then split its triangles at the exact pivot ring.
    stem = Mesh()
    sweep(stem,points,radii,sides=24,repeats=3,flutes=.075)
    stem.smooth_normals()
    boundary = 16*24*6
    for attribute in ('p','n','c','uv'):
        values = getattr(stem,attribute)
        setattr(trunk,attribute,values[:boundary])
        setattr(crown,attribute,values[boundary:])
        setattr(crown_lod,attribute,list(values[boundary:]))
    for j in range(9):
        angle = j*2.399+rng.uniform(-.22,.22)
        extent = rng.uniform(1.3,2.1)
        pts = [(math.cos(angle)*extent*(k/6),
                .65*(1-k/6)**2+.025,math.sin(angle)*extent*(k/6)) for k in range(7)]
        sweep(trunk,pts,[.22*(1-k/6)**1.1+.008 for k in range(7)],sides=12)
    for j in range(18):
        y = 4.35+j*(tree_height-4.65)/18+rng.uniform(-.12,.12)
        angle = j*2.399 + variant*.75+rng.uniform(-.28,.28)
        crown_t = (y-4)/(tree_height-4)
        length = (2.65*(1-crown_t)**.65+.45)*spread*rng.uniform(.84,1.15)
        grow(center(y),(math.cos(angle),rng.uniform(-.12,.25),math.sin(angle)),
             length,.16*(1-crown_t)**.8+.023,0)
    # Fine leaders fill the top without creating a flat umbrella of foliage.
    for j in range(4):
        a = j*2.399
        grow(center(tree_height-.55),(math.cos(a)*.5,1,math.sin(a)*.5),.75,.023,2)
    for mesh in (trunk,crown,crown_lod):
        mesh.smooth_normals()
    for mesh in (crown,leaves,crown_lod,leaves_lod):
        mesh.p = [add(p,(0,-4,0)) for p in mesh.p]
    return trunk,crown,leaves,crown_lod,leaves_lod,dict(variant=variant,branches=branch_count,
        leaves=leaf_count,triangles=sum(len(m.p)//3 for m in (trunk,crown,leaves)),
        distant_triangles=sum(len(m.p)//3 for m in (trunk,crown_lod,leaves_lod)))


def generate():
    rng = random.Random(7319)
    ground = Mesh()
    for iz in range(256):
        for ix in range(280):
            x, z = ix*.5-70, iz*.5-100
            points, colors = [], []
            for px, pz in ((x,z), (x,z+.5), (x+.5,z+.5), (x+.5,z)):
                points.append((px, height(px,pz), pz))
                path = math.exp(-((px-1.7*math.sin(pz*.12))/1.4)**2)
                variation = .8+.2*math.sin(px*1.7+pz*2.1)
                colors.append(tuple((a*(1-path)+b*path)*variation for a,b in zip((.80,1.20,.72), (1.12,1.02,.90))))
            for ids in ((0,1,2), (0,2,3)):
                ground.tri(*(points[i] for i in ids), tuple(colors[i] for i in ids),
                           tuple((points[i][0]/1.6,points[i][2]/1.6) for i in ids))
    ground.smooth_normals()
    yield 'ground', ground.glb(texture=albedo('ground'), normal=albedo('ground_normal'), normal_scale=.6, surface=albedo('ground_surface'))

    water = Mesh()
    # Segments follow a monotonically falling river; UV.v follows distance downstream.
    for iz in range(380):
        z = iz*.25-68
        for ix in range(1):
            u = ix
            verts, coords, colors = [], [], []
            for pu,pz in ((u,z),(u,z+.25),(u+1,z+.25),(u+1,z)):
                x = stream_center(pz)+(pu*2-1)*stream_width(pz)
                verts.append((x,water_level(pz),pz))
                coords.append((pu,(pz+68)*.5))
                colors.append((1,1,1,.88))
            for ids in ((0,1,2),(0,2,3)):
                water.tri(*(verts[i] for i in ids),tuple(colors[i] for i in ids),tuple(coords[i] for i in ids))
    yield 'water', water.glb(blend=True,texture=albedo('water_surface'), normal=albedo('water_normal'), normal_scale=.5)

    for variant,suffix in enumerate(('', '_2', '_3')):
        trunk,crown,leaves,crown_lod,leaves_lod,stats = forest_tree(variant)
        print('tree quality:',json.dumps(stats,sort_keys=True))
        yield 'tree'+suffix, trunk.glb(texture=albedo('bark'), normal=albedo('bark_normal'), normal_scale=.65)
        yield 'crown'+suffix, crown.glb(texture=albedo('bark'))
        yield 'leaves'+suffix, leaves.glb()
        yield 'crown_lod'+suffix, crown_lod.glb(texture=albedo('bark'))
        yield 'leaves_lod'+suffix, leaves_lod.glb()
    # Preserve the existing grass/fern asset random stream after replacing the leaf generator.
    for _ in range(180*7):
        rng.random()

    grass = Mesh()
    for _ in range(20):
        angle, h = rng.uniform(0,math.tau), rng.uniform(.22,.68)
        root = (rng.uniform(-.25,.25),0,rng.uniform(-.25,.25))
        side = (math.cos(angle)*.025,0,math.sin(angle)*.025)
        mid = add(root, (math.sin(angle)*h*.17,h*.58,math.cos(angle)*h*.17))
        tip = add(root, (math.sin(angle)*h*.48,h,math.cos(angle)*h*.48))
        color = mul((.23,.38,.07), rng.uniform(.7,1.1))
        grass.tri(add(root,side),add(root,mul(side,-1)),add(mid,mul(side,-.5)),mul(color,.55))
        grass.tri(add(root,side),add(mid,mul(side,-.5)),add(mid,mul(side,.5)),color)
        grass.tri(add(mid,mul(side,.5)),add(mid,mul(side,-.5)),tip,color)
    yield 'grass', grass.glb()

    fern = Mesh()
    for j in range(9):
        angle, length = j*2.399, rng.uniform(.6,1.1)
        direction = (math.cos(angle),0,math.sin(angle))
        side = (-math.sin(angle),0,math.cos(angle))
        def stem(t): return add(mul(direction,length*t), (0,.06+math.sin(t*2.25)*length*.58,0))
        for k in range(1,11):
            t = k/11
            root = stem(t)
            fern.tube(stem(t-.09),root,.008,.005,(.16,.24,.055),4)
            for sign in (-1,1):
                tip = add(add(root,mul(side,sign*.23*length*math.sin(math.pi*t))),mul(direction,.12*length))
                fern.leaf(root,tip,.047*length*math.sin(math.pi*t),(.105,.31,.065))
    yield 'fern', fern.glb()

    rock = Mesh()
    rings = []
    for j in range(13):
        theta = math.pi*j/12
        row = []
        for i in range(25):
            phi = math.tau*i/24
            r = 1+.07*math.sin(phi*3+j*.41)+.035*math.sin(phi*5-j*.4)
            row.append((math.sin(theta)*math.cos(phi)*r, math.cos(theta)*.64, math.sin(theta)*math.sin(phi)*r))
        rings.append(row)
    for j in range(12):
        color = (.98,1.08,.90) if j<6 else (.75,.80,.74)
        for i in range(24):
            a,b,c,d = rings[j][i],rings[j][i+1],rings[j+1][i+1],rings[j+1][i]
            # Continuous longitude unwrap; duplicate seam vertices retain distinct UVs.
            points = (a,b,c,d)
            coords = ((i/12,j/12),((i+1)/12,j/12),
                      ((i+1)/12,(j+1)/12),(i/12,(j+1)/12))
            faces = ((0,2,1),) if j==11 else ((0,3,2),) if j==0 else ((0,2,1),(0,3,2))
            for ids in faces:
                rock.tri(*(points[k] for k in ids),color,tuple(coords[k] for k in ids))
    rock.smooth_normals()
    yield 'rock', rock.glb(texture=albedo('moss_rock'), normal=albedo('rock_normal'), normal_scale=.7, surface=albedo('rock_surface'))

    # One soft, transparent sheet per shaft. Vertex alpha fades on every edge.
    beam = Mesh()
    def beam_vertex(i,j):
        u, v = i/16, j/16
        y = v*12
        w = 1.05-.65*v
        p = ((u*2-1)*w+.65*y, y, -.38*y)
        alpha = math.sin(math.pi*u)**3 * math.sin(math.pi*v)**.65 * .24
        return p, (1.0,.91,.67,alpha)
    for j in range(16):
        for i in range(16):
            verts = [beam_vertex(a,b) for a,b in ((i,j),(i+1,j),(i+1,j+1),(i,j+1))]
            for ids in ((0,1,2),(0,2,3)):
                beam.tri(*(verts[k][0] for k in ids),tuple(verts[k][1] for k in ids))
    yield 'beam', beam.glb(blend=True,unlit=True)

    mote = Mesh()
    for i in range(12):
        a,b = math.tau*i/12,math.tau*(i+1)/12
        mote.tri((0,0,0),(math.cos(a),math.sin(a),0),(math.cos(b),math.sin(b),0),
                 ((.85,1,.6,.28),(.85,1,.6,0),(.85,1,.6,0)))
    yield 'mote', mote.glb(blend=True,unlit=True)

    # A tiny rounded drop stays visible from any viewing angle. Brighter upper
    # vertices suggest a sky glint without a texture or a large glowing halo.
    droplet = Mesh()
    def drop_vertex(ring, segment):
        latitude, angle = -math.pi/2 + ring*math.pi/3, segment*math.tau/8
        return (math.cos(latitude)*math.cos(angle), math.sin(latitude),
                math.cos(latitude)*math.sin(angle))
    colors = ((.25,.48,.54,.22), (.42,.66,.73,.48), (.84,.95,1,.82), (.98,1,1,.92))
    for ring in range(3):
        for segment in range(8):
            vertices = [(ring,segment), (ring,segment+1),
                        (ring+1,segment+1), (ring+1,segment)]
            for ids in ((0,2,1), (0,3,2)):
                if (ring == 0 and ids == (0,2,1)) or (ring == 2 and ids == (0,3,2)):
                    continue
                droplet.tri(*(drop_vertex(*vertices[k]) for k in ids),
                            tuple(colors[vertices[k][0]] for k in ids))
    droplet.smooth_normals()
    yield 'droplet', droplet.glb(blend=True,unlit=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    args = parser.parse_args()
    for name,data in generate():
        path = ROOT / (name+'.glb')
        if args.check:
            if not path.exists() or path.read_bytes()!=data: raise SystemExit(f'Out of date: {path}')
        else:
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_bytes(data)
        print(f'{name}: {len(data)} bytes')
