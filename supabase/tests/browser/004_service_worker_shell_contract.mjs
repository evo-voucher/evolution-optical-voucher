import fs from 'node:fs';

const source=fs.readFileSync('service-worker.js','utf8');
const required=[
  './index.html',
  './admin.html',
  './admin-staff.html',
  './admin-partner-password.html',
  './partner.html',
  './staff.html',
  './voucher.html',
  './voucher-engine.html',
  './assets/js/backend-config.js'
];
for(const path of required){
  if(!source.includes(`'${path}'`)) throw new Error(`Safe shell is missing ${path}`);
}
if(!source.includes("fetch(req,{cache:'no-store'})")) throw new Error('Safe shell must remain network-first with no-store fetches');
if(!source.includes("caches.match('./index.html')")) throw new Error('Safe shell fallback must remain fail-closed through index.html');
console.log('Service worker safe-shell contract passed.');
