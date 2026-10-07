#!/usr/bin/env python3
"""Extract connection locations in the same coordinate frame as imported meshes.
LEGO female ports come from LDraw primitives, not bounding-box guesses.
Estimated metal ports deliberately retain an estimated provenance.
"""
import functools, json, math, re, zipfile
from build_part_models import estimated
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
z = zipfile.ZipFile(ROOT/'assets/parts/ldraw_sources.zip')
names = {n.lower(): n for n in z.namelist()}

def resolve(name):
    name=name.replace(chr(92), '/')
    for prefix in ('ldraw/parts/', 'ldraw/p/'):
        if prefix+name.lower() in names: return names[prefix+name.lower()]
    raise ValueError(name)

def apply(a, p, off=(0,0,0)):
    return tuple(off[i]+sum(a[i*3+j]*p[j] for j in range(3)) for i in range(3))

@functools.lru_cache(None)
def read(path):
    vertices, ports = [], []
    for line in z.read(path).decode('utf-8-sig',errors='replace').splitlines():
        t=line.split()
        if not t: continue
        if t[0] in ('3','4'):
            v=list(map(float,t[2:])); vertices += [tuple(v[i:i+3]) for i in range(0,len(v),3)]
        elif t[0]=='1':
            v=list(map(float,t[2:14])); off,a=v[:3],v[3:]; child=resolve(' '.join(t[14:])); base=Path(child).name
            points,subports=read(child)
            vertices += [apply(a,p,off) for p in points]
            tangent=apply(a,(1,0,0))
            if base=='peghole.dat':
                ports.append(('pin_hole',tuple(off),apply(a,(0,-1,0)),tangent))
            elif base in ('axlehole.dat','axl2hole.dat','axl3hole.dat','axlehol4.dat','axlehol5.dat'):
                ports.append(('axle_hole',tuple(off),apply(a,(0,-1,0)),tangent))
                ports.append(('axle_hole',apply(a,(0,1,0),off),apply(a,(0,1,0)),tangent))
            elif base in ('stud.dat','stud2.dat','stud2a.dat','stud6a.dat','stud10.dat'):
                ports.append(('stud',tuple(off),apply(a,(0,-1,0)),tangent))
            elif base in ('confric.dat','confric4.dat','confric5.dat','confric6.dat','confric8.dat','confric9.dat','connect.dat','connect2.dat','connect3.dat','connect7.dat','connect8.dat'):
                ports.append(('pin',tuple(off),apply(a,(0,-1,0)),tangent))
            elif base=='axleend20.dat':
                ports.append(('axle',tuple(off),apply(a,(0,-1,0)),tangent))
            else:
                ports += [(k,apply(a,p,off),apply(a,n),apply(a,t)) for k,p,n,t in subports]
    return vertices,ports

def port(kind,p,n,quality,tangent=None):
    length=math.sqrt(sum(v*v for v in n))
    result={'kind':kind,'position':[round(v,7) for v in p],'normal':[round(v/length,7) for v in n],'quality':quality}
    if tangent is not None:
        length=math.sqrt(sum(v*v for v in tangent)); result['tangent']=[round(v/length,7) for v in tangent]
    return result

catalog=json.loads((ROOT/'data/parts/botball_2026.json').read_text())['parts']
models=json.loads((ROOT/'assets/parts/models.json').read_text())['models']
result={}
for part in catalog:
    id=part['id']
    if id not in models: continue
    meta=models[id]; sx,sy,sz=meta['size']; ports=[]; name=part['name'].lower()
    if part['group']=='lego':
        points,raw=read(meta['source'])
        points=[(x*.0004,-y*.0004,-zz*.0004) for x,y,zz in points]
        lo=[min(p[i] for p in points) for i in range(3)]; hi=[max(p[i] for p in points) for i in range(3)]
        origin=[(lo[0]+hi[0])/2,lo[1],(lo[2]+hi[2])/2]
        for kind,p,n,t in raw:
            p=(p[0]*.0004,-p[1]*.0004,-p[2]*.0004)
            ports.append(port(kind,[p[i]-origin[i] for i in range(3)],(n[0],-n[1],-n[2]),'ldraw',(t[0],-t[1],-t[2])))
        # Flat rectangular LEGO plates/bricks have a stud socket under each stud.
        if 'liftarm' not in name and re.match(r'^\d+ x \d+ ', name) and ('plate' in name or 'w/ hole' in name or 'w/ axle hole' in name or 'tile' in name):
            rows,cols=map(int,re.match(r'^(\d+) x (\d+) ',name).groups())
            for x in range(cols):
                for zz in range(rows):
                    ports.append(port('stud_socket',((x-(cols-1)/2)*.008,0,(zz-(rows-1)/2)*.008),(0,-1,0),'ldraw_grid'))
        # Simple standalone axles/pins: collars are centred on the shaft axis.
        if re.match(r'^#\s*\d+.*axle',name):
            axis=max(range(3),key=lambda i:meta['size'][i]); mid=[0,sy/2,0]
            for sign in (-1,1):
                p=mid.copy(); n=[0,0,0]; n[axis]=sign
                kind='axle' if 'axle' in name and not name.startswith('axle pin') else 'pin'
                if name.startswith('axle pin'): kind='axle' if sign<0 else 'pin'
                # End insertion depth 8mm, centred collar for a two-unit pin.
                p[axis]+=sign*max(0,meta['size'][axis]/2-.008)
                t=[0,0,0]; t[(axis+1)%3]=1
                ports.append(port(kind,p,n,'shaft_axis',t))
    elif part['group']=='metal':
        # Reproduce the generated sheet transforms, including bracket side faces.
        if meta['quality']=='estimated' and 'screw' not in name and any(w in name for w in ('strap','channel','plate','chassis','bracket','mount','1 x 5 servo horn')):
            dims=re.search(r'(\d+) x (\d+)',name)
            rows,cols=map(int,dims.groups()) if dims else (4,12) if 'chassis' in name else (2,3)
            points=[p for f in estimated(part).faces for p in f]
            lo=[min(p[i] for p in points) for i in range(3)]; hi=[max(p[i] for p in points) for i in range(3)]
            origin=[(lo[0]+hi[0])/2,lo[1],(lo[2]+hi[2])/2]
            panels=[(rows,cols,(0,0,0),False)]
            if 'channel' in name or 'chassis' in name:
                panels += [(2,cols,(sign*rows*.0127/2,.0127,0),'side') for sign in (-1,1)]
            elif 'bracket' in name or 'mount' in name:
                panels.append((rows,2,(0,.0127,cols*.0127/2),True))
            for r,c,at,vertical in panels:
                for row in range(r):
                    for col in range(c):
                        for sign in (-1,1):
                            x=(row-(r-1)/2)*.0127; y=sign*.0015/2; zz=(col-(c-1)/2)*.0127
                            p=(at[0]+y,at[1]+x,at[2]+zz) if vertical=='side' else (at[0]+x,at[1]+(zz if vertical else y),at[2]+(-y if vertical else zz))
                            n=(sign,0,0) if vertical=='side' else (0,0,-sign) if vertical else (0,sign,0)
                            ports.append(port('hole_8_32',[p[i]-origin[i] for i in range(3)],n,'estimated'))
        if 'screw' in name and 'mount' not in name and 'machine' not in name and 'mecanum' not in name:
            thread='m3' if '(m3)' in name else '8_32' if '8-32' in name else ''
            if thread:
                axis=max(range(3),key=lambda i:meta['size'][i]); mid=[0,sy/2,0]
                head_sign=1; head_boundary=mid[axis]+meta['size'][axis]/2-.002
                if meta['quality']=='kipr':
                    points=[list(map(float,line.split()[1:])) for line in (ROOT/'assets/parts'/f'{id}.obj').read_text().splitlines() if line.startswith('v ')]
                    low=min(p[axis] for p in points); high=max(p[axis] for p in points)
                    def radial(p): return sum((p[i]-mid[i])**2 for i in range(3) if i!=axis)**.5
                    low_radius=max(radial(p) for p in points if p[axis]<low+.001)
                    high_radius=max(radial(p) for p in points if p[axis]>high-.001)
                    head_sign=-1 if low_radius>high_radius else 1
                    threshold=(low_radius+high_radius)/2
                    head_points=[p[axis] for p in points if radial(p)>threshold]
                    head_boundary=max(head_points) if head_sign<0 else min(head_points)
                n=[0,0,0]; n[axis]=-head_sign
                p=mid.copy(); p[axis]=head_boundary
                ports.append(port('bolt_'+thread,p,n,'estimated'))
                # Nut thread engagement near the far end of the screw.
                p=mid.copy(); p[axis]-=head_sign*(meta['size'][axis]/2-.002)
                ports.append(port('thread_'+thread,p,n,'estimated'))
        if 'nut' in name or 'standoff' in name:
            thread='m3' if '(m3)' in name else '8_32' if '8-32' in name else ''
            if thread:
                axis=0 if id=='metal_026' else 1
                for sign in (-1,1):
                    p=[0,sy/2,0]; n=[0,0,0]; n[axis]=sign; p[axis]+=sign*meta['size'][axis]/2
                    ports.append(port('nut_'+thread,p,n,'estimated'))
    # Collapse duplicate semantic references; stable indexing is persisted in projects.
    unique={ (p['kind'],tuple(p['position']),tuple(p['normal'])):p for p in ports }
    result[id]=list(unique.values())
(ROOT/'assets/parts/connections.json').write_text(json.dumps({'schema_version':1,'parts':result},indent=2)+'\n')
print(sum(bool(p) for p in result.values()),'parts with ports;',sum(map(len,result.values())),'connection points')
