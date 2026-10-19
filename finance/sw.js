'use strict';
const VERSION='distinct-finance-v1';
const ASSETS=['./','./index.html','./style.css','./app.js','./icon.svg','./distinct-logo.svg','./manifest.webmanifest'];
self.addEventListener('install',event=>event.waitUntil(caches.open(VERSION).then(c=>c.addAll(ASSETS)).then(()=>self.skipWaiting())));
self.addEventListener('activate',event=>event.waitUntil(caches.keys().then(names=>Promise.all(names.filter(n=>n!==VERSION).map(n=>caches.delete(n)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',event=>{const req=event.request,url=new URL(req.url);if(req.method!=='GET'||url.origin!==self.location.origin)return;event.respondWith(fetch(req).then(res=>{if(res.ok){const copy=res.clone();caches.open(VERSION).then(c=>c.put(req,copy)).catch(()=>{})}return res}).catch(()=>caches.match(req).then(hit=>hit||new Response('Offline. Financial records require an internet connection.',{status:503,headers:{'Content-Type':'text/plain'}}))))});