import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, execSync, spawn } from 'node:child_process';
import puppeteer from 'puppeteer-core';

const API_URL='http://127.0.0.1:54321';
const DB_URL='postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const WEB_URL='http://127.0.0.1:4180';
const password='AdminNav!123456';
const suffix=`${Date.now()}-${Math.floor(Math.random()*100000)}`;
const adminEmail=`browser-nav-admin-${suffix}@example.test`;

const statusText=execSync('supabase status -o env',{encoding:'utf8'});
const anonKey=statusText.match(/^ANON_KEY="?([^"\n]+)"?/m)?.[1];
if(!anonKey) throw new Error('ANON_KEY not found from local Supabase status');

async function signup(email,password){
  const r=await fetch(`${API_URL}/auth/v1/signup`,{method:'POST',headers:{apikey:anonKey,'Content-Type':'application/json'},body:JSON.stringify({email,password})});
  const body=await r.json();
  if(!r.ok||!body?.user?.id) throw new Error(`Signup failed for ${email}: ${JSON.stringify(body)}`);
  return body.user.id;
}
function sqlLiteral(v){return `'${String(v).replaceAll("'","''")}'`;}
function runSql(sql){execFileSync('psql',[DB_URL,'-v','ON_ERROR_STOP=1'],{input:sql,stdio:['pipe','inherit','inherit']});}

const adminUid=await signup(adminEmail,password);
runSql(`
begin;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
insert into public.admin_users(user_id,display_name,status)
values (${sqlLiteral(adminUid)}::uuid,'Navigation Browser Admin','active');
commit;
`);

for(const target of ['voucher-engine.html','admin-staff.html','admin-partner-password.html']){
  const html=fs.readFileSync(target,'utf8');
  if(!html.includes('href="admin.html"') || !html.includes('Back to Admin Portal')){
    throw new Error(`${target} is missing reciprocal Back to Admin Portal navigation`);
  }
}

const root=fs.mkdtempSync(path.join(os.tmpdir(),'evo-admin-nav-browser-'));
fs.mkdirSync(path.join(root,'assets','js'),{recursive:true});
let html=fs.readFileSync('admin.html','utf8');
html=html.replace(/const configured=cfg\.enabled===true&&[\s\S]*?;\s*if\(!configured\)return;/,'const configured=cfg.enabled===true;if(!configured)return;');
if(!html.includes('const configured=cfg.enabled===true;if(!configured)return;')) throw new Error('Unable to patch local admin config guard');
fs.writeFileSync(path.join(root,'admin.html'),html);
fs.writeFileSync(path.join(root,'assets','js','backend-config.js'),`window.EVOLUTION_VOUCHER_BACKEND=Object.freeze({enabled:true,environment:'test',projectId:'local-browser-test',supabaseUrl:'${API_URL}',publishableKey:'${anonKey}',siteBase:'${WEB_URL}/'});\n`);

const server=spawn('python3',['-m','http.server','4180','--bind','127.0.0.1'],{cwd:root,stdio:['ignore','ignore','inherit']});
let browser;
try{
  await new Promise(r=>setTimeout(r,500));
  browser=await puppeteer.launch({headless:true,executablePath:process.env.CHROME_PATH||'/usr/bin/google-chrome',args:['--no-sandbox','--disable-dev-shm-usage']});
  const page=await browser.newPage();
  await page.goto(`${WEB_URL}/admin.html`,{waitUntil:'networkidle0'});
  await page.type('#email',adminEmail);
  await page.type('#password',password);
  await page.click('#loginBtn');
  await page.waitForSelector('#dashboardState:not(.hidden)',{visible:true,timeout:15000});
  await page.waitForSelector('#adminToolsCard',{visible:true,timeout:5000});

  const links=await page.evaluate(()=>({
    voucher:document.getElementById('voucherEngineLink')?.getAttribute('href'),
    staff:document.getElementById('adminStaffLink')?.getAttribute('href'),
    password:document.getElementById('partnerPasswordLink')?.getAttribute('href')
  }));
  if(links.voucher!=='voucher-engine.html') throw new Error(`Voucher Engine Admin link mismatch: ${links.voucher}`);
  if(links.staff!=='admin-staff.html') throw new Error(`Admin Staff link mismatch: ${links.staff}`);
  if(links.password!=='admin-partner-password.html') throw new Error(`Partner Password link mismatch: ${links.password}`);

  console.log('Admin navigation browser E2E passed.');
} finally {
  if(browser) await browser.close();
  server.kill('SIGTERM');
  fs.rmSync(root,{recursive:true,force:true});
}
