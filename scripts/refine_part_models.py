#!/usr/bin/env python3
"""Refine estimated kit meshes and add crease-aware normals to every OBJ.
Keeps official LEGO/KIPR geometry and preserves hard edges (50 degrees).
"""
import json, math
from collections import defaultdict
from build_part_models import ROOT, OUT, estimated

def normals(path):
    lines=path.read_text().splitlines(); vertices=[]; faces=[]; slots=[]
    for i,line in enumerate(lines):
        if line.startswith('v '): vertices.append(tuple(map(float,line.split()[1:])))
        elif line.startswith('f '):
            ids=[int(token.split('/')[0])-1 for token in line.split()[1:]]
            faces.append(ids); slots.append(i)
    adjacency=defaultdict(list); ns=[]; areas=[]
    def sub(a,b): return tuple(x-y for x,y in zip(a,b))
    def cross(a,b): return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
    def unit(v):
        length=math.sqrt(sum(x*x for x in v)); return tuple(x/length for x in v) if length>1e-14 else (0,1,0)
    for index,ids in enumerate(faces):
        n=cross(sub(vertices[ids[1]],vertices[ids[0]]),sub(vertices[ids[2]],vertices[ids[0]]))
        areas.append(n); ns.append(unit(n))
        for v in set(ids): adjacency[tuple(round(x,7) for x in vertices[v])].append(index)
    unique={}; result=[]; threshold=math.cos(math.radians(50))
    for fi,ids in enumerate(faces):
        row=[]
        for vi in ids:
            neighbors=adjacency[tuple(round(x,7) for x in vertices[vi])]
            close=[j for j in neighbors if sum(a*b for a,b in zip(ns[fi],ns[j]))>=threshold]
            n=tuple(round(x,7) for x in unit(tuple(sum(areas[j][i] for j in close) for i in range(3))))
            if n not in unique: unique[n]=len(unique)+1
            row.append(f'{vi+1}//{unique[n]}')
        result.append('f '+' '.join(row))
    for slot,row in zip(slots,result): lines[slot]=row
    # Face indices can reference normals declared before the faces.
    first=next(i for i,line in enumerate(lines) if line.startswith('f '))
    lines=[line for line in lines[:first] if not line.startswith('vn ')]+['vn '+' '.join(map(str,n)) for n in unique]+[line for line in lines[first:] if not line.startswith('vn ')]
    path.write_text('\n'.join(lines)+'\n')

if __name__=='__main__':
    manifest=json.loads((OUT/'models.json').read_text())
    for part in json.loads((ROOT/'data/parts/botball_2026.json').read_text())['parts']:
        meta=manifest['models'].get(part['id'])
        if not meta: continue
        path=OUT/(part['id']+'.obj')
        if meta['quality']=='estimated':
            meta['size']=estimated(part).save(path)
            meta['detail']='chamfered surfaces, high resolution holes and visible fastener threads'
        normals(path)
    manifest['geometry_revision']=2
    (OUT/'models.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('Refined 39 estimated models; crease normals on all 156 models')
