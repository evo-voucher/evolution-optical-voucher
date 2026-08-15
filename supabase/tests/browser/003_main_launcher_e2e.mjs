import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import puppeteer from 'puppeteer-core';

const WEB_URL='http://127.0.0.1:4175';
const root=fs.mkdtempSync(path.join(os.tmpdir(),'evo-launcher-'));
fs.mkdirSync(path.join(root,'assets','js'),{recursive:true});
fs.copyFileSync('index.html',path.join(root,'index.html'));

function writeConfig(config){
  fs.writeFileSync(path.join(root,'assets','js','backend-config.js'),`window.EVOLUTION_VOUCHER_BACKEND=Object.freeze(${JSON.stringify(config)});\n`);
}

writeConfig({enabled:false,environment:'reconstruction',projectId:'',supabaseUrl:'',publishableKey:''});
const server=spawn('python3',['-m','http.server','4175','--bind','127.0.0.1'],{cwd:root,stdio:['ignore','ignore','inherit']});
let browser;
try{
  await new Promise(r=>setTimeout(r,400));
  browser=await puppeteer.launch({headless:true,executablePath:process.env.CHROME_PATH||'/usr/bin/google-chrome',args:['--no-sandbox','--disable-dev-shm-usage']});
  const page=await browser.newPage();

  await page.goto(`${WEB_URL}/index.html`,{waitUntil:'networkidle0'});
  const disabledStatus=await page.$eval('#backendStatus',el=>el.textContent||'');
  if(!disabledStatus.includes('not configured')) throw new Error(`Launcher did not fail closed when disabled: ${disabledStatus}`);

  const hrefs=await page.$$eval('a',els=>Object.fromEntries(els.map(el=>[el.id,el.getAttribute('href')])));
  const expected={
    adminPortalLink:'admin.html',
    partnerPortalLink:'partner.html',
    staffPortalLink:'staff.html',
    adminStaffLink:'admin-staff.html',
    adminPartnerPasswordLink:'admin-partner-password.html'
  };
  for(const [id,href] of Object.entries(expected)){
    if(hrefs[id]!==href) throw new Error(`Launcher route ${id} expected ${href}, got ${hrefs[id]}`);
  }

  writeConfig({
    enabled:true,
    environment:'test',
    projectId:'local-launcher-test',
    supabaseUrl:'https://local-launcher-test.supabase.co',
    publishableKey:'sb_publishable_local_launcher_test_key_1234567890'
  });
  await page.reload({waitUntil:'networkidle0'});
  const enabledStatus=await page.$eval('#backendStatus',el=>el.textContent||'');
  const enabledMeta=await page.$eval('#backendMeta',el=>el.textContent||'');
  if(!enabledStatus.includes('configured')) throw new Error(`Launcher did not reflect enabled backend: ${enabledStatus}`);
  if(!enabledMeta.includes('local-launcher-test')) throw new Error(`Launcher did not expose configured project identity metadata: ${enabledMeta}`);

  console.log('Main launcher E2E passed for fail-closed and configured states with stable role/admin routes.');
} finally {
  if(browser) await browser.close();
  server.kill('SIGTERM');
  fs.rmSync(root,{recursive:true,force:true});
}
