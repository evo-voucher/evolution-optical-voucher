const SAFE_CACHE='evolution-voucher-safe-shell-v4';
const SAFE_SHELL=[
  './',
  './index.html',
  './admin-login.html',
  './admin-dashboard.html',
  './admin.html',
  './admin-staff.html',
  './admin-partner-password.html',
  './partner.html',
  './staff.html',
  './voucher.html',
  './voucher-engine.html',
  './assets/js/backend-config.js',
  './assets/css/evolution-theme.css',
  './assets/css/allocation-compact.css',
  './assets/css/partner-entry-layout.css'
];
self.addEventListener('install',event=>{self.skipWaiting();event.waitUntil(caches.open(SAFE_CACHE).then(cache=>cache.addAll(SAFE_SHELL)))});
self.addEventListener('activate',event=>{event.waitUntil((async()=>{for(const key of await caches.keys()){if(key!==SAFE_CACHE)await caches.delete(key)}await self.clients.claim()})())});
self.addEventListener('fetch',event=>{
  const req=event.request;
  if(req.method!=='GET')return;
  const url=new URL(req.url);
  if(url.origin!==self.location.origin)return;
  event.respondWith((async()=>{
    try{
      const res=await fetch(req,{cache:'no-store'});
      const cache=await caches.open(SAFE_CACHE);
      cache.put(req,res.clone());
      return res;
    }catch(_){
      return (await caches.match(req))||(await caches.match('./index.html'));
    }
  })());
});