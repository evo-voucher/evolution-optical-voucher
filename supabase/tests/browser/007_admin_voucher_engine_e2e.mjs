import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, execSync, spawn } from 'node:child_process';
import puppeteer from 'puppeteer-core';

const API_URL='http://127.0.0.1:54321';
const DB_URL='postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const WEB_URL='http://127.0.0.1:4178';
const password='VoucherEngineAdmin!123456';
const suffix=`${Date.now()}-${Math.floor(Math.random()*100000)}`;
const adminEmail=`voucher-engine-admin-${suffix}@example.test`;
const partnerCode=`VE_PARTNER_${String(Date.now()).slice(-8)}_${Math.floor(Math.random()*1000)}`;
const templateCode=`A_${String(Date.now()).slice(-8)}_${Math.floor(Math.random()*1000)}`;

const statusText=execSync('supabase status -o env',{encoding:'utf8'});
const anonKey=statusText.match(/^ANON_KEY="?([^"\n]+)"?/m)?.[1];
if(!anonKey) throw new Error('ANON_KEY not found from local Supabase status');

async function signup(email,pw){
  const r=await fetch(`${API_URL}/auth/v1/signup`,{method:'POST',headers:{apikey:anonKey,'Content-Type':'application/json'},body:JSON.stringify({email,password:pw})});
  const body=await r.json();
  if(!r.ok||!body?.user?.id) throw new Error(`Signup failed: ${JSON.stringify(body)}`);
  return body.user.id;
}
function lit(v){return `'${String(v).replaceAll("'","''")}'`;}
function runSql(sql){execFileSync('psql',[DB_URL,'-v','ON_ERROR_STOP=1'],{input:sql,stdio:['pipe','inherit','inherit']});}
function scalar(sql){return execFileSync('psql',[DB_URL,'-At','-v','ON_ERROR_STOP=1','-c',sql],{encoding:'utf8'}).trim();}
async function waitForMessage(page,selector,label,timeout=15000){
  await page.waitForFunction(sel=>{const el=document.querySelector(sel);return !!el&&(el.classList.contains('ok')||el.classList.contains('err'));},{timeout},`${selector} .msg`);
  const state=await page.$eval(`${selector} .msg`,el=>({text:(el.textContent||'').trim(),ok:el.classList.contains('ok'),err:el.classList.contains('err')}));
  if(!state.ok) throw new Error(`${label} failed: ${state.text||'unknown UI error'}`);
  return state.text;
}

const adminUid=await signup(adminEmail,password);
runSql(`
begin;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
insert into public.admin_users(user_id,display_name,status) values (${lit(adminUid)}::uuid,'Voucher Engine Browser Admin','active');
insert into public.partners(partner_code,partner_name,voucher_limit,staff_limit,staff_access_enabled,status)
values (${lit(partnerCode)},'Voucher Engine Test Partner',0,5,true,'active');
commit;
`);
const partnerIdSql=`(select id from public.partners where partner_code=${lit(partnerCode)})`;
const claimBefore=scalar(`select concat(coalesce((select all_branches::text from public.partner_claim_settings where partner_id=${partnerIdSql}),'NULL'),'|',(select count(*) from public.partner_claim_branches where partner_id=${partnerIdSql}))`);

const root=fs.mkdtempSync(path.join(os.tmpdir(),'evo-voucher-engine-browser-'));
fs.mkdirSync(path.join(root,'assets','js'),{recursive:true});
let html=fs.readFileSync('voucher-engine.html','utf8');
html=html.replace(/const configured=cfg\.enabled===true&&[\s\S]*?;\s*if\(!configured\)return;/,'const configured=cfg.enabled===true;if(!configured)return;');
if(!html.includes('const configured=cfg.enabled===true;if(!configured)return;')) throw new Error('Unable to patch Voucher Engine local config guard');
fs.writeFileSync(path.join(root,'voucher-engine.html'),html);
fs.writeFileSync(path.join(root,'assets','js','backend-config.js'),`window.EVOLUTION_VOUCHER_BACKEND=Object.freeze({enabled:true,environment:'test',projectId:'local-voucher-engine-browser',supabaseUrl:'${API_URL}',publishableKey:'${anonKey}',siteBase:'${WEB_URL}/'});\n`);

const server=spawn('python3',['-m','http.server','4178','--bind','127.0.0.1'],{cwd:root,stdio:['ignore','ignore','inherit']});
let browser;
try{
  await new Promise(r=>setTimeout(r,500));
  browser=await puppeteer.launch({headless:true,executablePath:process.env.CHROME_PATH||'/usr/bin/google-chrome',args:['--no-sandbox','--disable-dev-shm-usage']});
  const page=await browser.newPage();
  page.on('console',msg=>console.log(`[browser:${msg.type()}] ${msg.text()}`));
  page.on('pageerror',err=>console.error(`[browser:pageerror] ${err.message}`));
  await page.goto(`${WEB_URL}/voucher-engine.html`,{waitUntil:'networkidle0'});
  await page.type('#email',adminEmail);
  await page.type('#password',password);
  await page.click('#loginBtn');
  await page.waitForSelector('#engineState:not(.hidden)',{visible:true,timeout:15000});

  await page.type('#templateCode',templateCode);
  await page.type('#templateName','RM60 Birthday Voucher');
  await page.select('#templateTheme','birthday');
  await page.click('#createTemplateBtn');
  await waitForMessage(page,'#templateMsg','Create classification');

  const templateId=await page.$eval('#versionTemplate',(el,code)=>[...el.options].find(o=>o.textContent?.startsWith(code+' —'))?.value||'',templateCode);
  if(!templateId) throw new Error('New Voucher classification not available for Version publish');
  await page.select('#versionTemplate',templateId);
  await page.type('#versionName','Birthday v1');
  await page.$eval('#faceValue',el=>el.value='60');
  await page.select('#validityMode','calendar_months_after_issue');
  await page.$eval('#validMonths',el=>el.value='3');
  await page.select('#versionTheme','birthday');
  await page.type('#greetingText','Happy Birthday! 🎂');

  await page.click('#versionAllBranches');
  await page.waitForSelector('.versionBranchCheck:not([disabled])');
  for(const code of ['MINES','BAHAU']){
    const box=await page.$(`.versionBranchCheck[value="${code}"]`);
    if(!box) throw new Error(`${code} Version branch checkbox not rendered`);
    await box.click();
  }
  await page.click('#publishBtn');
  await waitForMessage(page,'#publishMsg','Publish version');

  const partnerId=await page.$eval('#allocationPartner',(el,code)=>[...el.options].find(o=>o.textContent?.includes(`(${code})`))?.value||'',partnerCode);
  if(!partnerId) throw new Error('Test Partner not available in allocation selector');
  await page.select('#allocationPartner',partnerId);
  const versionId=await page.$eval('#allocationVersion',(el,code)=>[...el.options].find(o=>o.textContent?.startsWith(code+' v1'))?.value||'',templateCode);
  if(!versionId) throw new Error('Published Version not available in allocation selector');
  await page.select('#allocationVersion',versionId);
  await page.$eval('#allocationQty',el=>el.value='12');
  await page.select('#allocationAnchor','allocation');
  await page.waitForSelector('#allocationDaysField:not(.hidden)');
  await page.$eval('#allocationDays',el=>el.value='100');

  await page.click('#allocationAllBranches');
  await page.waitForSelector('.allocationBranchCheck:not([disabled])');
  const mines=await page.$('.allocationBranchCheck[value="MINES"]');
  if(!mines) throw new Error('MINES Allocation branch checkbox not rendered');
  await mines.click();
  await page.click('#allocateBtn');
  await waitForMessage(page,'#allocationMsg','Allocate voucher stock');

  const versionCheck=scalar(`select concat(vv.validity_mode,'|',vv.valid_months,'|',coalesce(vv.theme_override_code,''),'|',coalesce(vv.greeting_text,''),'|',vv.all_branches) from public.voucher_versions vv where vv.id=${lit(versionId)}::uuid`);
  if(versionCheck!==`months|3|birthday|Happy Birthday! 🎂|f`) throw new Error(`Published Version mismatch: ${versionCheck}`);
  const versionBranches=scalar(`select string_agg(b.branch_code,',' order by b.branch_code) from public.voucher_version_branches vvb join public.branches b on b.id=vvb.branch_id where vvb.version_id=${lit(versionId)}::uuid`);
  if(versionBranches!=='BAHAU,MINES') throw new Error(`Version branch scope mismatch: ${versionBranches}`);

  const allocationId=scalar(`select a.id from public.partner_voucher_allocations a where a.partner_id=${lit(partnerId)}::uuid and a.version_id=${lit(versionId)}::uuid order by a.created_at desc limit 1`);
  if(!allocationId) throw new Error('Allocation not persisted');
  const allocationCheck=scalar(`select concat(a.quantity_allocated,'|',a.validity_anchor,'|',a.allocation_valid_days,'|',a.all_branches) from public.partner_voucher_allocations a where a.id=${lit(allocationId)}::uuid`);
  if(allocationCheck!=='12|allocation|100|f') throw new Error(`Allocation mismatch: ${allocationCheck}`);
  const allocationBranches=scalar(`select string_agg(b.branch_code,',' order by b.branch_code) from public.partner_voucher_allocation_branches ab join public.branches b on b.id=ab.branch_id where ab.allocation_id=${lit(allocationId)}::uuid`);
  if(allocationBranches!=='MINES') throw new Error(`Allocation branch scope mismatch: ${allocationBranches}`);

  const claimAfter=scalar(`select concat(coalesce((select all_branches::text from public.partner_claim_settings where partner_id=${lit(partnerId)}::uuid),'NULL'),'|',(select count(*) from public.partner_claim_branches where partner_id=${lit(partnerId)}::uuid))`);
  if(claimAfter!==claimBefore) throw new Error(`Allocation UI unexpectedly rewrote Partner claim scope: before=${claimBefore} after=${claimAfter}`);

  console.log(`Admin Voucher Engine browser E2E passed for ${templateCode}, including immutable Version scope and Allocation-level branch scope.`);
} finally {
  if(browser) await browser.close();
  server.kill('SIGTERM');
  fs.rmSync(root,{recursive:true,force:true});
}
