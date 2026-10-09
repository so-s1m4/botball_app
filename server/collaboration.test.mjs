import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createServer,merge,validate} from './collaboration.mjs';
const part=(uid,id='metal_001')=>({uid:uid.repeat(32),id,position:[0,0,0],rotation:[0,0,0],links:[]});

test('independent concurrent edits merge, conflicting edits are atomic',()=>{
 const base=[part('a'),part('b','metal_007')];
 const alice=structuredClone(base),bob=structuredClone(base);
 alice[0].position[0]=.01;bob[1].position[1]=.02;
 const merged=merge(alice,base,bob);
 assert.equal(merged[0].position[0],.01);assert.equal(merged[1].position[1],.02);
 bob[0].position[0]=.03;
 assert.throws(()=>merge(alice,base,bob),e=>e.status===409);
 assert.equal(alice[0].position[0],.01);
 assert.deepEqual(merge(alice,base,alice),alice);
});

test('stable identities keep links valid across concurrent insertions and deletions',()=>{
 const base=[part('a')],left=[...structuredClone(base),part('b')],right=[...structuredClone(base),part('c')];
 assert.equal(merge(left,base,right).length,3);
 const linked=[part('a'),part('b')];linked[0].links=[{port:0,other:linked[1].uid,other_port:1}];linked[1].links=[{port:1,other:linked[0].uid,other_port:0}];
 validate(linked);
 assert.throws(()=>validate(linked.slice(0,1)));
 const changed=structuredClone(linked);changed[1].position[0]=.04;
 assert.throws(()=>merge(changed,linked,[]),e=>e.status===409);
});

test('HTTP rooms persist and reject invalid updates without changing state',async()=>{
 const dataRoot=await mkdtemp(join(tmpdir(),'botball-rooms-'));
 let server=createServer({dataRoot});
 const start=async()=>{await new Promise(r=>server.listen(0,'127.0.0.1',r));return 'http://127.0.0.1:'+server.address().port;};
 const stop=async()=>{server.closeAllConnections();await new Promise(r=>server.close(r));};
 try {
  let baseUrl=await start();
  const post=(path,data)=>fetch(baseUrl+path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});
  const initial=[part('a'),part('b','metal_007')];
  const created=await post('/api/rooms',{assembly:initial,client:'d'.repeat(32)});
  assert.equal(created.status,201);const room=await created.json();
  const path='/api/rooms/'+room.room;
  const state=await (await fetch(baseUrl+path+'?client='+'e'.repeat(32))).json();assert.equal(state.participants,2);
  const left=structuredClone(initial),right=structuredClone(initial);left[0].position[0]=.01;right[1].position[1]=.02;
  const responses=await Promise.all([post(path,{before:initial,after:left}),post(path,{before:initial,after:right})]);
  assert.deepEqual(responses.map(r=>r.status),[200,200]);
  const merged=await (await fetch(baseUrl+path)).json();assert.equal(merged.revision,3);
  const conflict=await post(path,{before:initial,after:[{...initial[0],position:[.04,0,0]},initial[1]]});assert.equal(conflict.status,409);
  assert.equal((await post(path,{before:merged.assembly,after:[{...initial[0],position:[999,0,0]}]})).status,400);
  assert.equal((await fetch(baseUrl+'/api/rooms/'+'0'.repeat(48))).status,404);
  assert.equal((await fetch(baseUrl+'/.git/config')).status,404);
  await stop();server=createServer({dataRoot});baseUrl=await start();
  assert.deepEqual((await (await fetch(baseUrl+path)).json()).assembly,merged.assembly);
 } finally {await stop();await rm(dataRoot,{recursive:true,force:true});}
});
