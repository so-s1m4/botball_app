import http from 'node:http';
import {randomBytes} from 'node:crypto';
import {readFile, writeFile, rename, mkdir} from 'node:fs/promises';
import {resolve, dirname, extname} from 'node:path';
import {fileURLToPath} from 'node:url';

const project = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const catalog = new Map(JSON.parse(await readFile(resolve(project,'data/parts/botball_2026.json'))).parts.map(p=>[p.id,p]));
// Godot and JavaScript can round the last decimal digit differently.
export function equal(a,b) {
 if (typeof a==='number' && typeof b==='number') return Math.abs(a-b)<=1e-12*Math.max(1,Math.abs(a),Math.abs(b));
 if (a===b) return true;
 if (!a || !b || typeof a!=='object' || typeof b!=='object' || Array.isArray(a)!==Array.isArray(b)) return false;
 const keys=Object.keys(a);
 return keys.length===Object.keys(b).length && keys.every(key=>Object.hasOwn(b,key) && equal(a[key],b[key]));
}
const uidPattern = /^[a-f0-9]{32}$/;
const fail = (message,status=400) => Object.assign(new Error(message),{status});

export function validate(parts) {
 if (!Array.isArray(parts) || parts.length>2048) throw fail('Неверный формат сборки');
 const ids=new Map(), counts=new Map();
 for (const p of parts) {
  const entry=catalog.get(p?.id);
  if (!p || !uidPattern.test(p.uid) || ids.has(p.uid) || !entry?.usable_on_robot) throw fail('Неверная деталь');
  ids.set(p.uid,p); counts.set(p.id,(counts.get(p.id)||0)+1);
  if (counts.get(p.id)>entry.quantity) throw fail('Превышено количество деталей');
  for (const field of ['position','rotation']) {
   const limit=field==='position'?.6:360;
   if (!Array.isArray(p[field]) || p[field].length!==3 || p[field].some(v=>typeof v!=='number'||!Number.isFinite(v)||Math.abs(v)>limit)) throw fail('Неверные координаты');
  }
  if (!Array.isArray(p.links) || p.links.length>4096) throw fail('Неверные соединения');
 }
 for (const p of parts) {
  const occupied=new Set();
  for (const link of p.links) {
   const other=ids.get(link.other);
   if (!other || other===p || !Number.isSafeInteger(link.port) || link.port<0 || !Number.isSafeInteger(link.other_port)||link.other_port<0 || occupied.has(link.port)) throw fail('Неверные соединения');
   occupied.add(link.port);
   if (!other.links.some(l=>l.other===p.uid && l.port===link.other_port && l.other_port===link.port)) throw fail('Соединение должно быть взаимным');
  }
 }
 return parts;
}

export function merge(current,before,after) {
 validate(before); validate(after);
 const base=new Map(before.map(p=>[p.uid,p]));
 const proposed=new Map(after.map(p=>[p.uid,p]));
 const result=new Map(current.map(p=>[p.uid,p]));
 // Compare complete affected parts; connected movements are atomic.
 for (const uid of new Set([...base.keys(),...proposed.keys()])) {
  const old=base.get(uid), next=proposed.get(uid), live=result.get(uid);
  if (equal(old,next) || equal(live,next)) continue;
  if (!equal(live,old)) throw fail('Другой участник уже изменил эту деталь',409);
  if (next) result.set(uid,next); else result.delete(uid);
 }
 return validate([...result.values()]);
}

export function createServer({webRoot=resolve(project,'build/web'),dataRoot=resolve(project,'server/rooms')}={}) {
 const rooms=new Map();
 // Serialize mutations, including disk writes, to avoid interleaved revisions.
 let mutations=Promise.resolve();
 async function load(id) {
  if (rooms.has(id)) return rooms.get(id);
  try {
   const saved=JSON.parse(await readFile(resolve(dataRoot,id+'.json'),'utf8'));
   validate(saved.assembly);
   const room={...saved,clients:new Map()}; rooms.set(id,room); return room;
  } catch { throw fail('Комната не найдена',404); }
 }
 async function persist(id,room) {
  await mkdir(dataRoot,{recursive:true});
  const file=resolve(dataRoot,id+'.json');
  await writeFile(file+'.tmp',JSON.stringify({revision:room.revision,assembly:room.assembly}));
  await rename(file+'.tmp',file);
 }
 function snapshot(room,client) {
  if (uidPattern.test(client||'')) room.clients.set(client,Date.now());
  for (const [id,last] of room.clients) if (Date.now()-last>15000) room.clients.delete(id);
  return {revision:room.revision,assembly:room.assembly,participants:room.clients.size};
 }
 return http.createServer(async(req,res)=>{
  const send=(status,data)=>{res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'});res.end(JSON.stringify(data));};
  try {
   const url=new URL(req.url,'http://localhost');
   if (url.pathname.startsWith('/api/')) {
    res.setHeader('Access-Control-Allow-Origin','https://botball-lab.preview.s1m4.com');
    res.setHeader('Access-Control-Allow-Methods','GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers','Content-Type');
    if (req.method==='OPTIONS') {res.writeHead(204);res.end();return;}
    if (url.pathname==='/api/health') {send(200,{ok:true});return;}
    const match=url.pathname.match(/^\/api\/rooms(?:\/([a-f0-9]{48}))?$/);
    if (!match) throw fail('Не найдено',404);
    if (req.method==='GET' && match[1]) {send(200,snapshot(await load(match[1]),url.searchParams.get('client')));return;}
    if (req.method!=='POST') throw fail('Метод не поддерживается',405);
    let body='',bytes=0;
    for await (const chunk of req) {bytes+=chunk.length;if(bytes>4*1024*1024) throw fail('Файл слишком большой',413);body+=chunk;}
    let data;try {data=JSON.parse(body);}catch{throw fail('Некорректный JSON');}
    const work=mutations.catch(()=>{}).then(async()=>{
     if (!match[1]) {
      if (rooms.size>=500) throw fail('Слишком много комнат',503);
      const assembly=validate(data.assembly),id=randomBytes(24).toString('hex');
      const room={revision:1,assembly,clients:new Map()};
      await persist(id,room);rooms.set(id,room);send(201,{room:id,...snapshot(room,data.client)});
     } else {
      const room=await load(match[1]);
      const assembly=merge(room.assembly,data.before,data.after);
      if (!equal(assembly,room.assembly)) {
       const updated={...room,revision:room.revision+1,assembly};
       await persist(match[1],updated);rooms.set(match[1],updated);
       send(200,snapshot(updated,data.client));
      } else send(200,snapshot(room,data.client));
     }
    });
    mutations=work; await work;return;
   }
   if (!['GET','HEAD'].includes(req.method)) throw fail('Метод не поддерживается',405);
   const relative=decodeURIComponent(url.pathname).replace(/^\/+/, '')||'index.html';
   const file=resolve(webRoot,relative);
   if (!file.startsWith(resolve(webRoot)+'/') || relative.split('/').some(p=>p.startsWith('.'))) throw fail('Не найдено',404);
   const types={'.html':'text/html; charset=utf-8','.js':'text/javascript','.wasm':'application/wasm','.pck':'application/octet-stream','.png':'image/png'};
   let content; try {content=await readFile(file);}catch{throw fail('Не найдено',404);}
   res.writeHead(200,{'Content-Type':types[extname(file)]||'application/octet-stream','Cache-Control':'no-cache'});res.end(req.method==='HEAD'?undefined:content);
  } catch(error) {if (!res.headersSent) send(error.status||500,{error:error.status?error.message:'Ошибка сервера'});else res.end();}
 });
}
if (process.argv[1] && resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
 const server=createServer();server.listen(Number(process.env.BOTBALL_PORT||8094),'127.0.0.1',()=>console.log('Botball collaboration listening on '+server.address().port));
}
