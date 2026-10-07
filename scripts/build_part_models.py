#!/usr/bin/env python3
"""Offline OBJ assets: actual LDraw LEGO geometry, estimated KIPR kit geometry.
Usage: python3 scripts/build_part_models.py /path/to/complete.zip
No third-party Python dependencies. Original LDraw sources and licenses retained.
"""
import functools, hashlib, json, math, re, sys, zipfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/parts'
ALIASES = {'6538c': '59443', 'x346': '41669'}

class Mesh:
    def __init__(self): self.faces = []
    def face(self, points):
        for i in range(1, len(points)-1): self.faces.append((points[0], points[i], points[i+1]))
    def box(self, size, at=(0,0,0)):
        x,y,z = [v/2 for v in size]; a,b,c = at
        p=[(a+sx*x,b+sy*y,c+sz*z) for sx,sy,sz in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
        for ids in [(3,2,1,0),(4,5,6,7),(0,1,5,4),(2,3,7,6),(1,2,6,5),(3,0,4,7)]: self.face([p[i] for i in ids])
    def ring(self, radius, hole, height, at=(0,0,0), segments=24):
        a,b,c=at
        for i in range(segments):
            t,u=2*math.pi*i/segments,2*math.pi*(i+1)/segments
            p=[(a+r*math.cos(v),b+y,c+r*math.sin(v)) for y,r,v in [(-height/2,radius,t),(-height/2,radius,u),(height/2,radius,u),(height/2,radius,t),(-height/2,hole,t),(-height/2,hole,u),(height/2,hole,u),(height/2,hole,t)]]
            for ids in [(0,3,2,1),(4,5,6,7),(3,7,6,2),(0,1,5,4)]: self.face([p[j] for j in ids])
    def panel(self, rows, cols, at=(0,0,0), vertical=False):
        # Perforated sheet, circular through-holes; 1/2 inch pitch is estimated.
        pitch=.0127; h=.0015; r=.0022
        a,b,c=at
        for row in range(rows):
            for col in range(cols):
                x=(row-(rows-1)/2)*pitch; z=(col-(cols-1)/2)*pitch
                for i in range(16):
                    angles=[2*math.pi*j/16 for j in (i,i+1)]
                    outer=[(math.cos(t)*pitch/2/max(abs(math.cos(t)),abs(math.sin(t))),math.sin(t)*pitch/2/max(abs(math.cos(t)),abs(math.sin(t)))) for t in angles]
                    inner=[(r*math.cos(t),r*math.sin(t)) for t in angles]
                    p=[(x+dx,y,z+dz) for y in (-h/2,h/2) for dx,dz in outer+inner]
                    for ids in [(0,1,3,2),(4,6,7,5),(2,3,7,6),(0,4,5,1)]:
                        pts=[p[j] for j in ids]
                        self.face([(a+px,b+(pz if vertical else py),c+(-py if vertical else pz)) for px,py,pz in pts])
    def save(self, path):
        points=[p for f in self.faces for p in f]
        low=[min(p[i] for p in points) for i in range(3)]
        high=[max(p[i] for p in points) for i in range(3)]
        origin=[(low[0]+high[0])/2,low[1],(low[2]+high[2])/2]
        vertices={}; faces=[]
        for face in self.faces:
            ids=[]
            for point in face:
                p=tuple(round(point[i]-origin[i],7) for i in range(3))
                if p not in vertices: vertices[p]=len(vertices)+1
                ids.append(vertices[p])
            if len(set(ids))==3: faces.append(ids)
        with path.open('w') as f:
            f.write('# Botball Lab: metres, +Y up, centred XZ, base Y=0\ns off\n')
            for p in vertices: f.write('v '+' '.join(f'{v:.7f}' for v in p)+'\n')
            for face in faces: f.write('f '+' '.join(map(str,face))+'\n')
        return [round(high[i]-low[i],7) for i in range(3)]

def estimated(part):
    m=Mesh(); n=part['name'].lower(); group=part['group']
    if group=='metal':
        dims=re.search(r'(\d+) x (\d+)',n)
        if any(s in n for s in ['strap','channel','plate','chassis','bracket','mount','1 x 5 servo horn']):
            rows,cols=map(int,dims.groups()) if dims else (4,12) if 'chassis' in n else (2,3)
            m.panel(rows,cols)
            if 'channel' in n or 'chassis' in n:
                for sign in (-1,1): m.panel(2,cols,(sign*rows*.0127/2,.0127,0),True)
            elif 'bracket' in n or 'mount' in n: m.panel(rows,2,(0,.0127,cols*.0127/2),True)
        elif 'horn' in n or 'washer' in n or 'nut' in n:
            m.ring(.014 if 'horn' in n else .0045,.0018,.002 if 'washer' in n else .004,segments=6 if 'nut' in n else 32)
        elif 'caster' in n and 'screw' not in n:
            m.box((.025,.003,.03),(0,.024,0)); m.ring(.011,.002,.008,(0,.011,0))
        else:
            length=.0127
            inch=re.search(r'(\d+(?:/\d+)?)"',n)
            if inch:
                nums=inch[1].split('/'); length=float(nums[0])/(float(nums[1]) if len(nums)>1 else 1)*.0254
            m.ring(.003 if 'standoff' in n else .0018,.001 if 'standoff' in n else 0,length,(0,length/2,0))
            if 'screw' in n: m.ring(.0035,0,.002,(0,length+.001,0))
    elif 'wheel' in n:
        m.ring(.035 if 'solarbotics' in n else .05,.004,.023)
        if 'mecanum' in n:
            for i in range(8):
                t=2*math.pi*i/8; m.ring(.01,0,.028,(.048*math.cos(t),0,.048*math.sin(t)),12)
    elif 'cable' in n:
        for x in (-.003,0,.003): m.box((.0015,.0015,.12),(x,0,0))
        for z in (-.06,.06): m.box((.01,.007,.01),(0,0,z))
    elif 'servo' in n:
        s=.55 if 'micro' in n else 1
        m.box((.04*s,.036*s,.02*s),(0,.018*s,0)); m.box((.054*s,.003*s,.015*s),(0,.006*s,0)); m.ring(.008*s,.0015*s,.004*s,(0,.038*s,0))
    elif 'motor' in n:
        m.box((.032,.025,.05),(0,.013,0)); m.ring(.012,0,.025,(0,.033,0)); m.ring(.0025,0,.013,(0,.05,0))
    elif 'wombat' in n and 'battery' not in n:
        m.box((.145,.043,.09),(0,.0215,0)); m.box((.08,.002,.05),(0,.044,0))
        for x in (-.06,.06):
            for z in (-.026,0,.026): m.box((.012,.012,.013),(x,.045,z))
    elif 'battery' in n:
        m.box((.07,.025,.038),(0,.0125,0)); m.box((.012,.004,.012),(0,.027,0))
    elif 'camera' in n or 'rangefinder' in n:
        m.box((.035,.025,.02),(0,.0125,0)); m.ring(.009,.005,.008,(0,.029,0))
    else:
        m.box((.025,.012,.015),(0,.006,0)); m.ring(.004,0,.003,(0,.0135,0))
    return m

def build(archive):
    OUT.mkdir(parents=True,exist_ok=True)
    z=zipfile.ZipFile(archive); names={n.lower():n for n in z.namelist()}; used=set()
    def resolve(name):
        name=name.replace('\\','/').lower()
        for prefix in ('ldraw/parts/','ldraw/p/'):
            if prefix+name in names: return names[prefix+name]
        raise ValueError('Missing LDraw dependency: '+name)
    @functools.lru_cache(None)
    def geometry(path):
        used.add(path); faces=[]; winding=1; invert=False
        for line in z.read(path).decode('utf-8-sig',errors='replace').splitlines():
            t=line.split()
            if not t: continue
            if t[0]=='0':
                if 'BFC' in t:
                    if 'CW' in t: winding=-1
                    if 'CCW' in t: winding=1
                    if 'INVERTNEXT' in t: invert=True
            elif t[0]=='1':
                v=list(map(float,t[2:14])); off=v[:3]; a=v[3:]
                det=a[0]*(a[4]*a[8]-a[5]*a[7])-a[1]*(a[3]*a[8]-a[5]*a[6])+a[2]*(a[3]*a[7]-a[4]*a[6])
                flip=(det<0)^invert; invert=False
                for face in geometry(resolve(' '.join(t[14:]))):
                    pts=[tuple(off[i]+sum(a[i*3+j]*p[j] for j in range(3)) for i in range(3)) for p in face]
                    faces.append(tuple(reversed(pts)) if flip else tuple(pts))
            elif t[0] in ('3','4'):
                coords=list(map(float,t[2:])); pts=[tuple(coords[i:i+3]) for i in range(0,len(coords),3)]
                if winding<0: pts.reverse()
                for i in range(1,len(pts)-1): faces.append((pts[0],pts[i],pts[i+1]))
        return tuple(faces)
    models={}
    for part in json.loads((ROOT/'data/parts/botball_2026.json').read_text())['parts']:
        if not part['usable_on_robot']: continue
        source=None
        if part['group']=='lego':
            number=ALIASES.get(part['part_number'],part['part_number']); source=resolve(number+'.dat')
            m=Mesh(); m.faces=[tuple((x*.0004,-y*.0004,-zz*.0004) for x,y,zz in face) for face in geometry(source)]
        else: m=estimated(part)
        size=m.save(OUT/(part['id']+'.obj'))
        models[part['id']]={'path':'res://assets/parts/'+part['id']+'.obj','size':size,'quality':'ldraw' if source else 'estimated','source':source}
    (OUT/'models.json').write_text(json.dumps({'schema_version':1,'library_sha256':hashlib.sha256(Path(archive).read_bytes()).hexdigest(),'models':models},indent=2)+'\n')
    with zipfile.ZipFile(OUT/'ldraw_sources.zip','w',zipfile.ZIP_DEFLATED) as subset:
        for name in sorted(used): subset.writestr(name,z.read(name))
        for name in z.namelist():
            if name.lower().split('/')[-1] in ('careadme.txt','calicense.txt','calicense4.txt'): subset.writestr(name,z.read(name)); (OUT/Path(name).name).write_bytes(z.read(name))
    print(f'Built {len(models)} models: {sum(v["quality"]=="ldraw" for v in models.values())} LDraw, others estimated.')

if __name__=='__main__': build(sys.argv[1])
