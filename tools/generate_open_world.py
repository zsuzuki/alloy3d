#!/usr/bin/env python3
"""Build the original 5 km river valley; only shared source atlases are checked in."""
import argparse
from array import array
import math
import random
import shutil
import struct
import sys
from pathlib import Path
sys.dont_write_bytecode = True
from generate_forest_assets import Mesh, unit
from open_world_assets import ATLAS, FOLIAGE, MEADOW, uv, box, quad, card, tree, house, rock, grass, bridge, save

SIZE, CELLS, CELL, SUB = 5000, 20, 250, 32
STEP, N = CELL/SUB, CELLS*SUB+1
ROOT=Path(__file__).resolve().parents[1]/'assets/samples/open_world'


def smooth(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)


def river(z): return 2200+180*math.sin(z*.0017)+90*math.sin(z*.0042)
def water(z): return 12+z*.0015
def halfwidth(z): return 25+5*math.sin(z*.0021)
BRIDGES=[(river(z),z,water(z),56) for z in (1400,3500)]
TOWNS=[(river(1400)-240,1400),(river(3500)+240,3500)]
TRAIL=[(river(1400)-380,1400),(river(1400)+180,1400),(3100,1400),(3370,1550),
       (3450,1850),(3550,2080),(3850,2170),(4100,2420),
       (4050,2820),(3780,3180),(3350,3500),(river(3500)-180,3500)]
PATHS=[[(400,1400),(4600,1400)],[(400,3500),(4600,3500)],TRAIL[2:],
       [(river(z)-90,z) for z in range(400,4501,100)]]


def raw_height(x,z):
    base=26+10*math.sin(x*.0018)*math.cos(z*.0014)+3*math.sin(x*.018+z*.012)+1.5*math.cos(z*.037-x*.02)
    hills=sum(h*math.exp(-((x-a)**2/sx**2+(z-b)**2/sz**2)) for a,b,h,sx,sz in
              [(4120,2450,460,660,900),(3800,4000,280,850,630),(600,4050,210,650,750),(580,400,170,580,550)])
    # Broad valley floor, carved riverbed and soft banks. At bridge ends the road
    # approaches are leveled to the deck, while the channel remains underneath.
    d=abs(x-river(z))/halfwidth(z)
    channel=water(z)-4+8*smooth(.8,1.5,d)
    y=channel*(1-smooth(1.5,3.2,d))+(base+hills)*smooth(1.5,3.2,d)
    # Small level village plots retain the broader slope without undulating walls.
    for tx,tz in TOWNS:
        blend=(1-smooth(150,245,math.hypot(x-tx,z-tz)))*.7
        base_y=26+10*math.sin(tx*.0018)*math.cos(tz*.0014)
        y=y*(1-blend)+base_y*blend
    # Bridge approaches override the village leveling near the abutments.
    for bx,bz,w,span in BRIDGES:
        approach=(1-smooth(9,18,abs(z-bz)))*(1-smooth(span+12,span+85,abs(x-bx)))
        if abs(x-bx)>halfwidth(z)*1.45:
            y=y*(1-approach)+(w+5)*approach
    return y


def distance_segment(x,z,a,b):
    dx,dz=b[0]-a[0],b[1]-a[1];t=max(0,min(1,((x-a[0])*dx+(z-a[1])*dz)/(dx*dx+dz*dz)))
    return math.hypot(x-a[0]-dx*t,z-a[1]-dz*t)


def path_distance(x,z):
    # Wide village roads are straight, with a winding riverbank/summit trail.
    d=min(abs(z-1400),abs(z-3500))
    d=min(d,abs(x-river(z)+90)+2)
    if x>2950:
        d=min(d,min(distance_segment(x,z,a,b)+2 for a,b in zip(TRAIL[2:],TRAIL[3:])))
    return d


def field():
    heights=[]; zones=bytearray()
    for j in range(N):
        z=j*STEP
        for i in range(N):
            x=i*STEP;y=raw_height(x,z);heights.append(y)
            zone=2 if abs(x-river(z))<halfwidth(z)*1.24 else 1 if path_distance(x,z)<7 else 3 if y>230 else 0
            zones.append(zone)
    return heights,zones


def sample(heights,x,z):
    fx=max(0,min(N-1.001,x/STEP));fz=max(0,min(N-1.001,z/STEP));i,j=int(fx),int(fz);u,v=fx-i,fz-j
    a,b,c,d=[heights[k] for k in (j*N+i,j*N+i+1,(j+1)*N+i,(j+1)*N+i+1)]
    return a+(d-c)*u+(c-a)*v if v>=u else a+(b-a)*u+(d-b)*v


def terrain(cx,cz,n,heights,zones):
    m=Mesh();meadow=Mesh();step=SUB//n;ox,oz=cx*SUB,cz*SUB
    def point(i,j):
        ix,iz=ox+i*step,oz+j*step;return ix*STEP,heights[iz*N+ix],iz*STEP
    for j in range(n):
        for i in range(n):
            p=[point(i,j),point(i,j+1),point(i+1,j+1),point(i+1,j)]
            cxp,czp=(p[0][0]+p[2][0])*.5,(p[0][2]+p[2][2])*.5
            h=sample(heights,cxp,czp);d=abs(cxp-river(czp))/halfwidth(czp)
            tile=1 if path_distance(cxp,czp)<9 or d<1.7 else 2 if h>245 else 0
            col=(.88,.95,.8) if tile==0 else (.92,.91,.87)
            target=meadow if n==SUB and tile==0 else m
            begin=len(target.p)
            quad(target,*p,tile,col)
            coords=[(0,1),(1,1),(1,0),(0,0)]
            for offset,k in enumerate((0,1,2,0,2,3)):
                u,v=coords[k]
                if (ox//step+i)%2:u=1-u
                if (oz//step+j)%2:v=1-v
                target.uv[begin+offset]=uv(tile,(u,v))
            if n==SUB:
                for k in range(len(target.p)-6,len(target.p)):
                    x,y,z=target.p[k]
                    target.n[k]=unit((sample(heights,x-2,z)-sample(heights,x+2,z),4,sample(heights,x,z-2)-sample(heights,x,z+2)))
                    if tile==0:target.uv[k]=(x/4,z/4)
            else:
                average=[(.23,.32,.12),(.48,.43,.32),(.42,.43,.39)][0 if tile==0 else 1 if tile==1 else 2]
                m.c[-6:]=[(*average,1)]*6
    for j in range(n):
        for a,b in [((j,0),(j+1,0)),((n,j),(n,j+1)),((j+1,n),(j,n)),((0,j+1),(0,j))]:
            p,q=point(*a),point(*b);quad(m,p,q,(q[0],q[1]-12,q[2]),(p[0],p[1]-12,p[2]),0,(.27,.34,.16))
    return m,meadow


def placements(cx,cz,heights):
    rng=random.Random(cz*CELLS+cx+2407);rows=[]
    # Town houses follow both sides of the road, with gardens and a clear bridge approach.
    for tx,tz in TOWNS:
        for ix in range(-4,5):
            for iz in (-2,-1,1,2):
                x=tx+ix*30;z=tz+iz*25+(3 if ix%2 else -3)
                if not (cx*CELL<=x<(cx+1)*CELL and cz*CELL<=z<(cz+1)*CELL):continue
                if abs(x-river(z))<90:continue
                rows.append((2+(ix%2),x,sample(heights,x,z),z,0 if iz>0 else math.pi,rng.uniform(.88,1.05)))
    for j in range(20):
        for i in range(20):
            x=(cx+(i+rng.uniform(.15,.85))/20)*CELL;z=(cz+(j+rng.uniform(.15,.85))/20)*CELL
            h=sample(heights,x,z);d=abs(x-river(z))
            if path_distance(x,z)<13 or d<halfwidth(z)*1.65:continue
            town=min(math.hypot(x-a,z-b) for a,b in TOWNS)
            if town<175:continue
            meadow=math.sin(x*.003+math.sin(z*.002))*math.cos(z*.004)
            if h>300 or rng.random()<(.82 if meadow>.05 or town<250 else .20):
                if rng.random()<.11:rows.append((4,x,h-.2,z,rng.uniform(0,6.28),rng.uniform(.7,2.7)))
                continue
            kind=1 if h>160 or rng.random()<.35 else 0
            rows.append((kind,x,h-.15,z,rng.uniform(0,6.28),rng.uniform(.8,1.4)))
    return rows


def proxy_tree(wood,leaves,x,y,z,s,pine):
    # Crossed foliage cards keep the same atlas/color as the near trees, while
    # their per-cell batching is much cheaper than individual distant trees.
    wood.tube((x,y,z),(x,y+8*s,z),.35*s,.1*s,(.19,.14,.085),3)
    for a in (0,math.pi/2):
        if pine:
            for h,r in ((6,3.5),(10,2.2)):
                card(leaves,(x,y+h*s,z),(math.cos(a)*r*s,0,math.sin(a)*r*s),(0,3*s,0),2,(.78,.9,.74),(0,1,0))
        else:
            card(leaves,(x,y+9*s,z),(math.cos(a)*4.5*s,0,math.sin(a)*4.5*s),(0,4*s,0),0,(.87,.98,.8),(0,1,0))


def add_house_proxy(m,row):
    kind,x,y,z,a,s=row
    part=house(kind-2,True)[0][0]
    colors=[(.23,.32,.12),(.48,.43,.32),(.42,.43,.39),(.2,.13,.08),(.67,.62,.49),(.3,.22,.14),(.35,.13,.065),(.43,.42,.35)]
    for p,n,c,uv in zip(part.p,part.n,part.c,part.uv):
        m.p.append((x+(math.cos(a)*p[0]+math.sin(a)*p[2])*s,y+p[1]*s,z+(-math.sin(a)*p[0]+math.cos(a)*p[2])*s))
        m.n.append((math.cos(a)*n[0]+math.sin(a)*n[2],n[1],-math.sin(a)*n[0]+math.cos(a)*n[2]))
        tile=min(3,int(uv[0]*4))+4*min(1,int(uv[1]*2));m.c.append((*colors[tile],1));m.uv.append((0,0))


def main():
    parser=argparse.ArgumentParser();parser.add_argument('output',type=Path);args=parser.parse_args();out=args.output;out.mkdir(parents=True,exist_ok=True)
    for name in (ATLAS,FOLIAGE,MEADOW):shutil.copyfile(ROOT/name,out/name)
    for name,parts in [('oak',tree()),('pine',tree(True)),('cottage',house()),('farmhouse',house(1)),('rock',rock()),
                       ('oak_low',tree(low=True)),('pine_low',tree(True,True)),('cottage_low',house(low=True)),('farmhouse_low',house(1,True)),('rock_low',rock(True)),('grass',grass())]:save(out/(name+'.glb'),parts)
    heights,zones=field()
    values=array('f',heights)
    if sys.byteorder!='little':values.byteswap()
    (out/'heightfield.bin').write_bytes(struct.pack('<I',N)+values.tobytes()+zones)
    with (out/'landscape.txt').open('w') as f:
        f.write(f'ALLOY3D_LANDSCAPE_V1 {N} {STEP}\n501\n')
        for z in range(0,5001,10):f.write(f'{river(z)} {z} {water(z)} {halfwidth(z)}\n')
        f.write(f'{len(BRIDGES)}\n')
        for row in BRIDGES:f.write(' '.join(map(str,row))+'\n')
        f.write(f'{len(TRAIL)}\n')
        for row in TRAIL:f.write(' '.join(map(str,row))+'\n')
    count=0
    for cz in range(CELLS):
        for cx in range(CELLS):
            key=cz*CELLS+cx;rows=placements(cx,cz,heights);count+=len(rows)
            (out/f'{key}.cell').write_text('ALLOY3D_CELL_V2\n'+str(len(rows))+'\n'+'\n'.join(' '.join(map(str,row)) for row in rows)+'\n')
            ground,meadow=terrain(cx,cz,SUB,heights,zones)
            save(out/f'{key}.glb',[(ground,ATLAS,False),(meadow,MEADOW,False)])
            proxy=terrain(cx,cz,8,heights,zones)[0];leaves=Mesh()
            for row in rows:
                kind,x,y,z,angle,s=row
                if kind in (2,3):add_house_proxy(proxy,row)
                elif kind<2 and (int(x)+int(z))%3!=0:proxy_tree(proxy,leaves,x,y,z,s,kind==1)
            save(out/f'{key}_far.glb',[(proxy,None,False),(leaves,FOLIAGE,True)])
        print(f'Terrain row {cz+1}/{CELLS}',flush=True)
    structures=Mesh()
    for bx,bz,w,span in BRIDGES:
        part=bridge(bx,bz,w,span)
        for attr in ('p','n','c','uv'):getattr(structures,attr).extend(getattr(part,attr))
    # Garden fences, roadside markers and low stone walls make villages legible at ground level.
    for tx,tz in TOWNS:
        for dx in range(-140,141,12):
            for dz in (-70,70):
                x,z=tx+dx,tz+dz;y=sample(heights,x,z)
                box(structures,x,y,z,.28,1.25,.28,5)
                for h in (.48,.94):box(structures,x+5.5,y+h,z,11,.12,.13,5)
    save(out/'structures.glb',[(structures,ATLAS,False)])
    river_mesh=Mesh()
    for z in range(0,5000,8):
        zz=min(5000,z+8);x0,x1=river(z),river(zz);w0,w1=halfwidth(z)*1.14,halfwidth(zz)*1.14
        for a,b in ((-1,-.7),(-.7,.7),(.7,1)):
            color=(.075,.27,.29) if a==-.7 else (.15,.36,.34)
            pts=[(x0+a*w0,water(z),z),(x0+b*w0,water(z),z),(x1+b*w1,water(zz),zz),(x1+a*w1,water(zz),zz)]
            for ids in ((0,2,1),(0,3,2)):
                river_mesh.tri(*(pts[i] for i in ids),color,tuple((pts[i][0]*.05,pts[i][2]*.05) for i in ids))
    save(out/'river.glb',[(river_mesh,None,False)])
    # Continuous narrow ribbons keep paths clear even when a cell uses coarse terrain.
    roads=Mesh()
    for path in PATHS:
        for a,b in zip(path,path[1:]):
            length=math.dist(a,b);steps=max(1,math.ceil(length/4));side=(-(b[1]-a[1])/length*3.5,(b[0]-a[0])/length*3.5)
            for i in range(steps):
                points=[]
                for t,sgn in ((i/steps,-1),(i/steps,1),((i+1)/steps,1),((i+1)/steps,-1)):
                    x=a[0]+(b[0]-a[0])*t+side[0]*sgn;z=a[1]+(b[1]-a[1])*t+side[1]*sgn
                    points.append((x,sample(heights,x,z)+.10,z))
                if any(abs(p[0]-river(p[2]))<halfwidth(p[2])*1.4 for p in points):continue
                quad(roads,*points,1,(.9,.91,.84))
    save(out/'paths.glb',[(roads,ATLAS,False)])
    (out/'world.txt').write_text(f'ALLOY3D_WORLD_V2 {SIZE} {CELLS} {CELL}\n')
    print(f'Generated valley: {CELLS**2} cells, {count} shared placements, 2 bridges, {N}x{N} heightfield',flush=True)

if __name__=='__main__':main()
