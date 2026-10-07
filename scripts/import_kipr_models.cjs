#!/usr/bin/env node
/* Extract kit components from KIPR's GPL-3.0 simulator, preserving mesh colours.
 * npm install --prefix /tmp/botball-model-tools draco3dgltf
 * NODE_PATH=/tmp/botball-model-tools/node_modules node scripts/import_kipr_models.cjs demobot_v6.glb
 */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const draco = require('draco3dgltf');
const root = path.resolve(__dirname, '..');
const out = path.join(root, 'assets/parts');
const source = fs.readFileSync(process.argv[2]);
const jsonSize = source.readUInt32LE(12);
const doc = JSON.parse(source.subarray(20, 20 + jsonSize).toString());
const bin = source.subarray(28 + jsonSize);
const identity = [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1];
function matrix(node) {
  if (node.matrix) return node.matrix;
  const [x,y,z,w] = node.rotation || [0,0,0,1];
  const [a,b,c] = node.scale || [1,1,1];
  const [u,v,t] = node.translation || [0,0,0];
  return [(1-2*y*y-2*z*z)*a,(2*x*y+2*w*z)*a,(2*x*z-2*w*y)*a,0,
    (2*x*y-2*w*z)*b,(1-2*x*x-2*z*z)*b,(2*y*z+2*w*x)*b,0,
    (2*x*z+2*w*y)*c,(2*y*z-2*w*x)*c,(1-2*x*x-2*y*y)*c,0,u,v,t,1];
}
function multiply(a,b) {
  const r = Array(16).fill(0);
  for (let col=0;col<4;col++) for(let row=0;row<4;row++)
    for(let k=0;k<4;k++) r[col*4+row]+=a[k*4+row]*b[col*4+k];
  return r;
}
function transform(p,m) { return [0,1,2].map(i=>m[i]*p[0]+m[4+i]*p[1]+m[8+i]*p[2]+m[12+i]); }
const mapping = {
  electronics_001:[36], electronics_003:[282], electronics_006:[178],
  electronics_008:[164], electronics_009:[271], electronics_010:[146],
  electronics_012:[410], electronics_015:[291], electronics_018:[414,415],
  metal_011:[78], metal_013:[29], metal_016:[58],
  metal_017:[72], metal_018:[38], metal_024:[85], metal_026:[181]
};
(async()=>{
 const mod = await draco.createDecoderModule({});
 const cache = new Map();
 function decode(index) {
  if(cache.has(index)) return cache.get(index);
  const primitives=[];
  for(const prim of doc.meshes[index].primitives) {
   if(prim.mode!==undefined && prim.mode!==4) throw Error('Expected triangles');
   const extension=prim.extensions.KHR_draco_mesh_compression;
   const view=doc.bufferViews[extension.bufferView];
   const bytes=bin.subarray(view.byteOffset||0,(view.byteOffset||0)+view.byteLength);
   const decoder=new mod.Decoder(); const buffer=new mod.DecoderBuffer();
   buffer.Init(new Int8Array(bytes),bytes.length);
   const mesh=new mod.Mesh();const status=decoder.DecodeBufferToMesh(buffer,mesh);
   if(!status.ok()) throw Error(status.error_msg());
   const attr=decoder.GetAttributeByUniqueId(mesh,extension.attributes.POSITION);
   const values=new mod.DracoFloat32Array();decoder.GetAttributeFloatForAllPoints(mesh,attr,values);
   const positions=[];
   for(let i=0;i<mesh.num_points();i++) positions.push([0,1,2].map(j=>values.GetValue(i*3+j)));
   const triangles=[];const indices=new mod.DracoInt32Array();
   for(let i=0;i<mesh.num_faces();i++) { decoder.GetFaceFromMesh(mesh,i,indices);triangles.push([0,1,2].map(j=>indices.GetValue(j))); }
   primitives.push({positions,triangles,material:prim.material});
   for(const item of [indices,values,mesh,buffer,decoder]) mod.destroy(item);
  }
  cache.set(index,primitives);return primitives;
 }
 const manifest=JSON.parse(fs.readFileSync(path.join(out,'models.json')));
 for(const [id,nodes] of Object.entries(mapping)) {
  const groups=[];
  function walk(index,parent,skipTransform=false) {
   // Battery is a separately accounted inventory item, not part of Wombat.
   if(id==='electronics_012' && index===291) return;
   const node=doc.nodes[index];const m=skipTransform?parent:multiply(parent,matrix(node));
   if(node.mesh!==undefined) for(const p of decode(node.mesh)) groups.push({...p,positions:p.positions.map(v=>transform(v,m))});
   for(const child of node.children||[]) walk(child,m);
  }
  for(const index of nodes) walk(index,identity,true);
  const points=groups.flatMap(p=>p.positions);
  const lo=[0,1,2].map(i=>Math.min(...points.map(p=>p[i])));
  const hi=[0,1,2].map(i=>Math.max(...points.map(p=>p[i])));
  const origin=[(lo[0]+hi[0])/2,lo[1],(lo[2]+hi[2])/2];
  let obj=`# Extracted from KIPR Simulator demobot_v6.glb; GPL-3.0\nmtllib ${id}.mtl\ns off\n`;
  let mtl='';let offset=1;
  groups.forEach((g,i)=>{
   const mat=doc.materials[g.material]?.pbrMetallicRoughness||{};
   const color=mat.baseColorFactor||[.6,.6,.6,1];
   mtl+=`newmtl material_${i}\nKd ${color.slice(0,3).join(' ')}\nd ${color[3]}\n\n`;
   obj+=`usemtl material_${i}\n`;
   for(const p of g.positions) obj+=`v ${p.map((v,j)=>(v-origin[j]).toFixed(7)).join(' ')}\n`;
   for(const face of g.triangles) obj+=`f ${face.map(j=>j+offset).join(' ')}\n`;
   offset+=g.positions.length;
  });
  fs.writeFileSync(path.join(out,id+'.obj'),obj);fs.writeFileSync(path.join(out,id+'.mtl'),mtl);
  manifest.models[id]={path:`res://assets/parts/${id}.obj`,size:hi.map((v,i)=>v-lo[i]),quality:'kipr',
   source:'https://github.com/kipr/Simulator/blob/master/static/object_binaries/demobot_v6.glb',
   source_sha256:crypto.createHash('sha256').update(source).digest('hex'),nodes:nodes.map(i=>doc.nodes[i].name),license:'GPL-3.0'};
  console.log(id,manifest.models[id].size.map(v=>(v*1000).toFixed(1)).join(' x ')+' mm');
 }
 fs.writeFileSync(path.join(out,'models.json'),JSON.stringify(manifest,null,2)+'\n');
})();
