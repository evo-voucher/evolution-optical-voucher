import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, execSync, spawn } from 'node:child_process';
import puppeteer from 'puppeteer-core';

const API_URL='http://127.0.0.1:54321';
const DB_URL='postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const WEB_URL='http://127.0.0.1:4179';
const password='PublicVoucher!123456';
const suffix=`${Date.now()}-${Math.floor(Math.random()*100000)}`;
const email=`public-voucher-${suffix}@example.test`;
const partnerCode=`PUBLIC_${String(Date.now()).slice(-8)}_${Math.floor(Math.random()*1000)}`;
const templateCode=`PUBLIC_TEMPLATE_${String(Date.now()).slice(-8)}_${Math.floor(Math.random()*1000)}`;

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
function runSql(sql){return execFileSync('psql',[DB_URL,'-At','-v','ON_ERROR_STOP=1'],{input:sql,encoding:'utf8'}).trim();}

const uid=await signup();
const token=runSql(`
begin;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
insert into public.partners(partner_code,partner_name,voucher_limit,staff_limit,staff_access_enabled,status)
values (${lit(partnerCode)},'Public Presentation Partner',0,5,true,'active');
insert into public.partner_users(user_id,partner_id,role,status,staff_name,login_email)
select ${lit(uid)}::uuid,p.id,'partner_admin','active','Public Partner Admin',${lit(email)} from public.partners p where p.partner_code=${lit(partnerCode)};
insert into public.partner_claim_settings(partner_id,all_branches,updated_by)
select p.id,false,${lit(uid)}::uuid from public.partners p where p.partner_code=${lit(partnerCode)};
insert into public.partner_claim_branches(partner_id,branch_id)
select p.id,b.id from public.partners p cross join public.branches b where p.partner_code=${lit(partnerCode)} and b.branch_code='MINES';
insert into public.voucher_templates(template_code,template_name,voucher_category,status,theme_code,theme_config,created_by)
values (${lit(templateCode)},'Birthday Presentation Voucher','test','active','birthday','{"accent_color":"#cc3366","accent_soft_color":"#331122","unsafe_html":"<script>alert(1)</script>"}'::jsonb,${lit(uid)}::uuid);
insert into public.voucher_versions(template_id,version_no,version_name,face_value,validity_mode,valid_months,usage_limit,all_branches,greeting_text,terms_text,status,effective_from,created_by)
select vt.id,1,'Birthday Presentation v1',60,'months',3,1,true,'Happy Birthday! 🎂','One voucher per customer. Present before redemption.','active',now(),${lit(uid)}::uuid from public.voucher_templates vt where vt.template_code=${lit(templateCode)};
update public.voucher_templates vt set current_version_id=vv.id from public.voucher_versions vv where vv.template_id=vt.id and vt.template_code=${lit(templateCode)} and vv.version_no=1;
insert into public.partner_voucher_access(partner_id,template_id,status,quota_type,created_by)
select p.id,vt.id,'active','allocation',${lit(uid)}::uuid from public.partners p cross join public.voucher_templates vt where p.partner_code=${lit(partnerCode)} and vt.template_code=${lit(templateCode)};
insert into public.partner_voucher_allocations(partner_id,version_id,quantity_allocated,status,created_by)
select p.id,vv.id,2,'active',${lit(uid)}::uuid from public.partners p join public.voucher_templates vt on vt.template_code=${lit(templateCode)} join public.voucher_versions vv on vv.template_id=vt.id and vv.version_no=1 where p.partner_code=${lit(partnerCode)};
commit;
select '';
`);

const login=await fetch(`${API_URL}/auth/v1/token?grant_type=password`,{method:'POST',headers:{apikey:anonKey,'Content-Type':'application/json'},body:JSON.stringify({email,password})});
const loginBody=await login.json();
if(!login.ok||!loginBody.access_token) throw new Error(`Partner login failed: ${JSON.stringify(loginBody)}`);
const issue=await fetch(`${API_URL}/rest/v1/rpc/issue_engine_voucher`,{method:'POST',headers:{apikey:anonKey,Authorization:`Bearer ${loginBody.access_token}`,'Content-Type':'application/json'},body:JSON.stringify({p_version_id:null,p_customer_name:'Presentation Customer',p_customer_phone:'0123334444'})});
let issueBody=await issue.json();
if(!issue.ok){
  const versionId=runSql(`select vv.id from public.voucher_versions vv join public.voucher_templates vt on vt.id=vv.template_id where vt.template_code=${lit(templateCode)} and vv.version_no=1;`);
  const retry=await fetch(`${API_URL}/rest/v1/rpc/issue_engine_voucher`,{method:'POST',headers:{apikey:anonKey,Authorization:`Bearer ${loginBody.access_token}`,'Content-Type':'application/json'},body:JSON.stringify({p_version_id:versionId,p_customer_name:'Presentation Customer',p_customer_phone:'0123334444'})});
  issueBody=await retry.json();
  if(!retry.ok||!issueBody?.public_token) throw new Error(`Voucher issue failed: ${JSON.stringify(issueBody)}`);
}
if(!issueBody?.public_token) throw new Error(`Voucher public token missing: ${JSON.stringify(issueBody)}`);
const publicToken=issueBody.public_token;

const root=fs.mkdtempSync(path.join(os.tmpdir(),'evo-public-voucher-'));
fs.mkdirSync(path.join(root,'assets','js'),{recursive:true});
let html=fs.readFileSync('voucher.html','utf8');
html=html.replace(/const configured=cfg\.enabled===true&&[\s\S]*?;\s*if\(!configured\)return;/,'const configured=cfg.enabled===true;if(!configured)return;');
if(!html.includes('const configured=cfg.enabled===true;if(!configured)return;')) throw new Error('Unable to patch Voucher local config guard');
fs.writeFileSync(path.join(root,'voucher.html'),html);
fs.writeFileSync(path.join(root,'assets','js','backend-config.js'),`window.EVOLUTION_VOUCHER_BACKEND=Object.freeze({enabled:true,environment:'test',projectId:'local-public-voucher',supabaseUrl:'${API_URL}',publishableKey:'${anonKey}',siteBase:'${WEB_URL}/'});\n`);

const server=spawn('python3',['-m','http.server','4179','--bind','127.0.0.1'],{cwd:root,stdio:['ignore','ignore','inherit']});
let browser;
try{
  await new Promise(r=>setTimeout(r,500));
  browser=await puppeteer.launch({headless:true,executablePath:process.env.CHROME_PATH||'/usr/bin/google-chrome',args:['--no-sandbox','--disable-dev-shm-usage']});
  const page=await browser.newPage();
  let dialogSeen=false;
  page.on('dialog',async dialog=>{dialogSeen=true;await dialog.dismiss();});
  await page.goto(`${WEB_URL}/voucher.html?v=${publicToken}`,{waitUntil:'networkidle0'});
  await page.waitForSelector('#voucherState:not(.hidden)',{visible:true,timeout:15000});
  const presentation=await page.evaluate(()=>({
    theme:document.querySelector('#voucherCard')?.dataset.theme,
    kicker:document.querySelector('#themeKicker')?.textContent,
    greeting:document.querySelector('#greeting')?.textContent,
    terms:document.querySelector('#termsText')?.textContent,
    branch:document.querySelector('#branches')?.textContent,
    accent:getComputedStyle(document.documentElement).getPropertyValue('--accent').trim(),
    soft:getComputedStyle(document.documentElement).getPropertyValue('--accent-soft').trim(),
    scripts:[...document.scripts].map(s=>s.textContent||'').filter(t=>t.includes('alert(1)')).length
  }));
  if(presentation.theme!=='birthday') throw new Error(`Expected frozen birthday theme, got ${presentation.theme}`);
  if(presentation.kicker!=='Birthday Gift') throw new Error(`Unexpected theme label: ${presentation.kicker}`);
  for(const text of ['A little gift for you 🎁✨','Happy Birthday! 🎂']) if(!presentation.greeting?.includes(text)) throw new Error(`Greeting missing ${text}: ${presentation.greeting}`);
  if(presentation.terms!=='One voucher per customer. Present before redemption.') throw new Error(`Terms not rendered from snapshot: ${presentation.terms}`);
  if(!presentation.branch?.includes('The Mines')||!presentation.branch?.includes('012-4732881')) throw new Error(`Frozen branch presentation missing: ${presentation.branch}`);
  if(presentation.accent!=='#cc3366'||presentation.soft!=='#331122') throw new Error(`Whitelisted theme colors not applied: ${presentation.accent} / ${presentation.soft}`);
  if(dialogSeen||presentation.scripts!==0) throw new Error('Unsafe theme_config content was executed or injected as script');
  console.log('Public Voucher presentation browser E2E passed.');
} finally {
  if(browser) await browser.close();
  server.kill('SIGTERM');
  fs.rmSync(root,{recursive:true,force:true});
}
