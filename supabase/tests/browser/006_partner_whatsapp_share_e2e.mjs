import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, execSync, spawn } from 'node:child_process';
import puppeteer from 'puppeteer-core';

const API_URL='http://127.0.0.1:54321';
const DB_URL='postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const WEB_URL='http://127.0.0.1:4177';
const password='ShareBrowser!123456';
const suffix=`${Date.now()}-${Math.floor(Math.random()*100000)}`;
const email=`share-partner-${suffix}@example.test`;
const partnerCode=`SHARE_${String(Date.now()).slice(-8)}_${Math.floor(Math.random()*1000)}`;
const templateCode=`SHARE_TEMPLATE_${String(Date.now()).slice(-8)}_${Math.floor(Math.random()*1000)}`;

const statusText=execSync('supabase status -o env',{encoding:'utf8'});
const anonKey=statusText.match(/^ANON_KEY="?([^"\n]+)"?/m)?.[1];
if(!anonKey) throw new Error('ANON_KEY not found from local Supabase status');

async function signup(){
  const r=await fetch(`${API_URL}/auth/v1/signup`,{method:'POST',headers:{apikey:anonKey,'Content-Type':'application/json'},body:JSON.stringify({email,password})});
  const body=await r.json();
  if(!r.ok||!body?.user?.id) throw new Error(`Signup failed: ${JSON.stringify(body)}`);
  return body.user.id;
}
function lit(v){return `'${String(v).replaceAll("'","''")}'`;}
function runSql(sql){execFileSync('psql',[DB_URL,'-v','ON_ERROR_STOP=1'],{input:sql,stdio:['pipe','inherit','inherit']});}

const uid=await signup();
runSql(`
begin;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
insert into public.partners(partner_code,partner_name,voucher_limit,staff_limit,staff_access_enabled,status)
values (${lit(partnerCode)},'WhatsApp Share Partner',0,5,true,'active');
insert into public.partner_users(user_id,partner_id,role,status,staff_name,login_email)
select ${lit(uid)}::uuid,p.id,'partner_admin','active','Share Partner Admin',${lit(email)} from public.partners p where p.partner_code=${lit(partnerCode)};
insert into public.partner_claim_settings(partner_id,all_branches,updated_by)
select p.id,false,${lit(uid)}::uuid from public.partners p where p.partner_code=${lit(partnerCode)};
insert into public.partner_claim_branches(partner_id,branch_id)
select p.id,b.id from public.partners p cross join public.branches b where p.partner_code=${lit(partnerCode)} and b.branch_code='MINES';
insert into public.voucher_templates(template_code,template_name,voucher_category,status,theme_code,created_by)
values (${lit(templateCode)},'Share RM60 Voucher','test','active','birthday',${lit(uid)}::uuid);
insert into public.voucher_versions(template_id,version_no,version_name,face_value,validity_mode,valid_months,usage_limit,all_branches,greeting_text,status,effective_from,created_by)
select vt.id,1,'Birthday Share v1',60,'months',3,1,true,'Happy Birthday! 🎂','active',now(),${lit(uid)}::uuid from public.voucher_templates vt where vt.template_code=${lit(templateCode)};
update public.voucher_templates vt set current_version_id=vv.id from public.voucher_versions vv where vv.template_id=vt.id and vt.template_code=${lit(templateCode)} and vv.version_no=1;
insert into public.partner_voucher_access(partner_id,template_id,status,quota_type,created_by)
select p.id,vt.id,'active','allocation',${lit(uid)}::uuid from public.partners p cross join public.voucher_templates vt where p.partner_code=${lit(partnerCode)} and vt.template_code=${lit(templateCode)};
insert into public.partner_voucher_allocations(partner_id,version_id,quantity_allocated,status,created_by)
select p.id,vv.id,2,'active',${lit(uid)}::uuid from public.partners p join public.voucher_templates vt on vt.template_code=${lit(templateCode)} join public.voucher_versions vv on vv.template_id=vt.id and vv.version_no=1 where p.partner_code=${lit(partnerCode)};
commit;
`);

const root=fs.mkdtempSync(path.join(os.tmpdir(),'evo-share-browser-'));
fs.mkdirSync(path.join(root,'assets','js'),{recursive:true});
let html=fs.readFileSync('partner.html','utf8');
html=html.replace(/const configured=cfg\.enabled===true&&[\s\S]*?;\s*if\(!configured\)return;/,'const configured=cfg.enabled===true;if(!configured)return;');
if(!html.includes('const configured=cfg.enabled===true;if(!configured)return;')) throw new Error('Unable to patch Partner local config guard');
fs.writeFileSync(path.join(root,'partner.html'),html);
fs.writeFileSync(path.join(root,'assets','js','backend-config.js'),`window.EVOLUTION_VOUCHER_BACKEND=Object.freeze({enabled:true,environment:'test',projectId:'local-share-browser',supabaseUrl:'${API_URL}',publishableKey:'${anonKey}',siteBase:'${WEB_URL}/'});\n`);

const server=spawn('python3',['-m','http.server','4177','--bind','127.0.0.1'],{cwd:root,stdio:['ignore','ignore','inherit']});
let browser;
try{
  await new Promise(r=>setTimeout(r,500));
  browser=await puppeteer.launch({headless:true,executablePath:process.env.CHROME_PATH||'/usr/bin/google-chrome',args:['--no-sandbox','--disable-dev-shm-usage']});
  const page=await browser.newPage();
  await page.goto(`${WEB_URL}/partner.html`,{waitUntil:'networkidle0'});
  await page.type('#email',email);
  await page.type('#password',password);
  await page.click('#loginBtn');
  await page.waitForSelector('#dashboardState:not(.hidden)',{visible:true,timeout:15000});
  await page.waitForFunction(()=>document.querySelectorAll('#issueVersion option').length>1,{timeout:15000});
  const version=await page.$eval('#issueVersion',el=>[...el.options].find(o=>o.value)?.value||'');
  if(!version) throw new Error('No issuable Voucher Version found');
  await page.select('#issueVersion',version);
  await page.type('#issueName','WhatsApp Customer');
  await page.type('#issuePhone','0121112222');
  await page.click('#issueBtn');
  await page.waitForSelector('#shareWhatsApp',{visible:true,timeout:15000});
  const href=await page.$eval('#shareWhatsApp',el=>el.href);
  const wa=new URL(href);
  if(wa.hostname!=='wa.me') throw new Error(`Unexpected WhatsApp host: ${wa.hostname}`);
  const message=wa.searchParams.get('text')||'';
  const required=['Hi 👋','A little gift for you 🎁✨','Here is your Evolution Optical Voucher.','Happy Birthday! 🎂','The Mines','L3-56, Level 3, The Mines Shopping Mall, Seri Kembangan','012-4732881','Voucher: http://127.0.0.1:4177/voucher.html?v='];
  for(const text of required){if(!message.includes(text)) throw new Error(`WhatsApp share missing ${text}: ${message}`);}
  if(message.includes('Bahau')||message.includes('06-4540984')) throw new Error(`WhatsApp share leaked non-snapshotted BAHAU branch: ${message}`);
  console.log('Partner WhatsApp share browser E2E passed.');
} finally {
  if(browser) await browser.close();
  server.kill('SIGTERM');
}
