'use strict';
const CACHE='distinct-time-cloud-v2-20261110';
const LOCAL=['./','./index.html','./style.css','./app.js','./manifest.webmanifest','./schema.sql','../icon.svg','../distinct-logo.svg'];
self.addEventListener('install',event=>event.waitUntil(caches.open(CACHE).then(c=>c.addAll(LOCAL)).then(()=>self.skipWaiting())));
self.addEventListener('activate',event=>event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(x=>x.startsWith('distinct-time-cloud-v2-')&&x!==CACHE).map(x=>caches.delete(x)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',event=>{const req=event.request;const url=new URL(req.url);if(req.method!=='GET'||url.origin!==self.location.origin)return;
  event.respondWith(fetch(req).then(resp=>{if(resp.ok&&url.pathname.includes('/time/v2/')){const copy=resp.clone();caches.open(CACHE).then(c=>c.put(req,copy)).catch(()=>{})}return resp}).catch(()=>caches.match(req).then(v=>v||Response.error())));
});
