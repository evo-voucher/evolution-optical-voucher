import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, execSync, spawn } from 'node:child_process';
import puppeteer from 'puppeteer-core';

const API_URL='http://127.0.0.1:54321';
const DB_URL='postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const WEB_URL='http://127.0.0.1:4174';
const initialPassword='PartnerResetOld!123';
const newPassword='PartnerResetNew!456';
const adminPassword='AdminReset!123456';
const suffix=`${Date.now()}-${Math.floor(Math.random()*100000)}`;
const adminEmail=`browser-reset-admin-${suffix}@example.test`;
const partnerEmail=`browser-reset-partner-${suffix}@example.test`;
const partnerCode=`RESET_${String(Date.now()).slice(-8)}_${Math.floor(Math.random()*1000)}`;

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

const adminUid=await signup(adminEmail,adminPassword);
const partnerUid=await signup(partnerEmail,initialPassword);
runSql(`
begin;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
insert into public.admin_users(user_id,display_name,status) values (${sqlLiteral(adminUid)}::uuid,'Reset Browser Admin','active');
insert into public.partners(partner_code,partner_name,voucher_limit,vouchers_issued,staff_limit,staff_access_enabled,status)
values (${sqlLiteral(partnerCode)},'Reset Browser Partner',0,0,2,true,'active');
insert into public.partner_users(user_id,partner_id,role,status,staff_name,login_email)
select ${sqlLiteral(partnerUid)}::uuid,p.id,'partner_admin','active','Reset Browser Partner Admin',${sqlLiteral(partnerEmail)} from public.partners p where p.partner_code=${sqlLiteral(partnerCode)};
commit;
`);

const root=fs.mkdtempSync(path.join(os.tmpdir(),'evo-reset-browser-'));
fs.mkdirSync(path.join(root,'assets','js'),{recursive:true});
for(const name of ['admin-partner-password.html','partner.html']){
  let html=fs.readFileSync(name,'utf8');
  html=html.replace(/const configured=cfg\.enabled===true&&[\s\S]*?;\s*if\(!configured\)return;/,'const configured=cfg.enabled===true;if(!configured)return;');
  if(!html.includes('const configured=cfg.enabled===true;if(!configured)return;')) throw new Error(`Unable to patch local test config guard in ${name}`);
  fs.writeFileSync(path.join(root,name),html);
}
fs.writeFileSync(path.join(root,'assets','js','backend-config.js'),`window.EVOLUTION_VOUCHER_BACKEND=Object.freeze({enabled:true,environment:'test',projectId:'local-browser-test',supabaseUrl:'${API_URL}',publishableKey:'${anonKey}',siteBase:'${WEB_URL}/'});\n`);

const server=spawn('python3',['-m','http.server','4174','--bind','127.0.0.1'],{cwd:root,stdio:['ignore','ignore','inherit']});
let browser;
try{
  await new Promise(r=>setTimeout(r,500));
  browser=await puppeteer.launch({headless:true,executablePath:process.env.CHROME_PATH||'/usr/bin/google-chrome',args:['--no-sandbox','--disable-dev-shm-usage']});
  const adminPage=await browser.newPage();
  await adminPage.goto(`${WEB_URL}/admin-partner-password.html`,{waitUntil:'networkidle0'});
  await adminPage.type('#email',adminEmail);
  await adminPage.type('#password',adminPassword);
  await adminPage.click('#loginBtn');
  await adminPage.waitForSelector('#resetState:not(.hidden)',{visible:true,timeout:15000});
  const partnerId=await adminPage.$eval('#partnerSelect',(el,code)=>[...el.options].find(o=>o.textContent?.includes(code))?.value||'',partnerCode);
  if(!partnerId) throw new Error('Reset UI did not expose the active Partner');
  await adminPage.select('#partnerSelect',partnerId);
  await adminPage.type('#newPassword',newPassword);
  adminPage.once('dialog',dialog=>dialog.accept());
  await adminPage.click('#resetBtn');
  await adminPage.waitForSelector('#resetMsg .ok',{visible:true,timeout:15000});

  const oldLogin=await fetch(`${API_URL}/auth/v1/token?grant_type=password`,{method:'POST',headers:{apikey:anonKey,'Content-Type':'application/json'},body:JSON.stringify({email:partnerEmail,password:initialPassword})});
  if(oldLogin.ok) throw new Error('Old Partner password still authenticates after reset');

  const partnerContext=await browser.createBrowserContext();
  const partnerPage=await partnerContext.newPage();
  await partnerPage.goto(`${WEB_URL}/partner.html`,{waitUntil:'networkidle0'});
  await partnerPage.type('#email',partnerEmail);
  await partnerPage.type('#password',newPassword);
  await partnerPage.click('#loginBtn');
  await partnerPage.waitForSelector('#dashboardState:not(.hidden)',{visible:true,timeout:15000});
  const sessionText=await partnerPage.$eval('#sessionMeta',el=>el.textContent||'');
  if(!sessionText.includes('role: partner_admin')) throw new Error(`Reset Partner login did not resolve to partner_admin: ${sessionText}`);
  await partnerContext.close();
  console.log(`Admin Partner password reset browser E2E passed for ${partnerCode}.`);
} finally {
  if(browser) await browser.close();
  server.kill('SIGTERM');
  fs.rmSync(root,{recursive:true,force:true});
}
