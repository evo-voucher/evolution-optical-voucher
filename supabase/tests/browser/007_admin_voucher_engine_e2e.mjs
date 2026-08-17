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
if(!anonKey)throw new Error('ANON_KEY not found from local Supabase status');

async function signup(email,pw){const r=await fetch(`${API_URL}/auth/v1/signup`,{method:'POST',headers:{apikey:anonKey,'Content-Type':'application/json'},body:JSON.stringify({email,password:pw})});const b=await r.json();if(!r.ok||!b?.user?.id)throw new Error(`Signup failed: ${JSON.stringify(b)}`);return b.user.id;}
function lit(v){return `'${String(v).replaceAll("'","''")}'`;}
function runSql(sql){execFileSync('psql',[DB_URL,'-v','ON_ERROR_STOP=1'],{input:sql,stdio:['pipe','inherit','inherit']});}
function scalar(sql){return execFileSync('psql',[DB_URL,'-At','-v','ON_ERROR_STOP=1','-c',sql],{encoding:'utf8'}).trim();}
async function okMessage(page,selector,label,timeout=15000){await page.waitForFunction(sel=>{const el=document.querySelector(sel);return !!el&&(el.classList.contains('ok')||el.classList.contains('err'));},{timeout},`${selector} .msg`);const s=await page.$eval(`${selector} .msg`,el=>({text:(el.textContent||'').trim(),ok:el.classList.contains('ok')}));if(!s.ok)throw new Error(`${label} failed: ${s.text||'unknown UI error'}`);return s.text;}

const adminUid=await signup(adminEmail,password);
runSql(`
begin;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
insert into public.admin_users(user_id,display_name,status) values (${lit(adminUid)}::uuid,'Voucher Engine Browser Admin','active');
insert into public.partners(partner_code,partner_name,voucher_limit,staff_limit,staff_access_enabled,status)
values (${lit(partnerCode)},'Voucher Engine Test Partner',0,5,true,'active');
insert into public.partner_claim_settings(partner_id,all_branches)
select id,true from public.partners where partner_code=${lit(partnerCode)}
on conflict(partner_id) do update set all_branches=true;
commit;
`);
const partnerId=scalar(`select id from public.partners where partner_code=${lit(partnerCode)}`);
const claimBefore=scalar(`select concat(coalesce((select all_branches::text from public.partner_claim_settings where partner_id=${lit(partnerId)}::uuid),'NULL'),'|',(select count(*) from public.partner_claim_branches where partner_id=${lit(partnerId)}::uuid))`);

const root=fs.mkdtempSync(path.join(os.tmpdir(),'evo-voucher-engine-browser-'));
fs.mkdirSync(path.join(root,'assets','js'),{recursive:true});
let html=fs.readFileSync('uat-preview/voucher-engine.html','utf8');
html=html.replace(/const configured=cfg\.enabled===true&&[\s\S]*?;\s*if\(!configured\)return;/,'const configured=cfg.enabled===true;if(!configured)return;');
if(!html.includes('const configured=cfg.enabled===true;if(!configured)return;'))throw new Error('Unable to patch local Voucher Engine config guard');
html=html.replace('</body>','<script src="assets/js/allocation-validity-ui.js"></script></body>');
fs.writeFileSync(path.join(root,'voucher-engine.html'),html);
fs.copyFileSync('uat-preview/assets/js/allocation-validity-ui.js',path.join(root,'assets','js','allocation-validity-ui.js'));
fs.writeFileSync(path.join(root,'assets','js','backend-config.js'),`window.EVOLUTION_VOUCHER_BACKEND=Object.freeze({enabled:true,environment:'test',projectId:'local-voucher-engine-browser',supabaseUrl:'${API_URL}',publishableKey:'${anonKey}',siteBase:'${WEB_URL}/'});\n`);

const server=spawn('python3',['-m','http.server','4178','--bind','127.0.0.1'],{cwd:root,stdio:['ignore','ignore','inherit']});
let browser;
try{
  await new Promise(r=>setTimeout(r,500));
  browser=await puppeteer.launch({headless:true,executablePath:process.env.CHROME_PATH||'/usr/bin/google-chrome',args:['--no-sandbox','--disable-dev-shm-usage']});
  const page=await browser.newPage();
  page.on('console',m=>console.log(`[browser:${m.type()}] ${m.text()}`));
  page.on('pageerror',e=>console.error(`[browser:pageerror] ${e.message}`));
  await page.goto(`${WEB_URL}/voucher-engine.html`,{waitUntil:'networkidle0'});
  await page.type('#email',adminEmail);await page.type('#password',password);await page.click('#loginBtn');
  await page.waitForSelector('#engineState:not(.hidden)',{visible:true,timeout:15000});

  await page.type('#templateCode',templateCode);await page.type('#templateName','RM60 Birthday Voucher');await page.select('#templateTheme','birthday');await page.click('#createTemplateBtn');
  await okMessage(page,'#templateMsg','Create classification');

  const templateId=await page.$eval('#versionTemplate',(el,code)=>[...el.options].find(o=>o.textContent?.startsWith(code+' —'))?.value||'',templateCode);
  if(!templateId)throw new Error('New classification not available for Version publish');
  await page.select('#versionTemplate',templateId);await page.type('#versionName','Birthday v1');await page.$eval('#faceValue',el=>el.value='60');await page.select('#validityMode','calendar_months_after_issue');await page.$eval('#validMonths',el=>el.value='3');await page.select('#versionTheme','birthday');await page.type('#greetingText','Happy Birthday! 🎂');
  await page.click('#versionAllBranches');await page.waitForSelector('.versionBranchCheck:not([disabled])');
  for(const code of ['MINES','BAHAU']){const box=await page.$(`.versionBranchCheck[value="${code}"]`);if(!box)throw new Error(`${code} Version branch checkbox not rendered`);await box.click();}
  await page.click('#publishBtn');await okMessage(page,'#publishMsg','Publish version');

  const versionId=await page.$eval('#allocationVersion',(el,code)=>[...el.options].find(o=>o.textContent?.startsWith(code+' v1'))?.value||'',templateCode);
  if(!versionId)throw new Error('Published Version not available in allocation selector');
  await page.select('#allocationPartner',partnerId);await page.select('#allocationVersion',versionId);await page.$eval('#allocationQty',el=>el.value='12');
  await page.waitForSelector('#allocationValidityAnchor',{timeout:5000});await page.select('#allocationValidityAnchor','allocation');await page.$eval('#allocationValidityValue',el=>el.value='100');await page.select('#allocationValidityUnit','days');
  await page.click('#allocationAllBranches');await page.waitForSelector('.allocationBranchCheck:not([disabled])');const mines=await page.$('.allocationBranchCheck[value="MINES"]');if(!mines)throw new Error('MINES Allocation branch checkbox not rendered');await mines.click();
  await page.click('#allocateBtn');await okMessage(page,'#allocationMsg','Allocate voucher stock');

  const versionCheck=scalar(`select concat(vv.validity_mode,'|',vv.valid_months,'|',coalesce(vv.theme_override_code,''),'|',coalesce(vv.greeting_text,''),'|',vv.all_branches) from public.voucher_versions vv where vv.id=${lit(versionId)}::uuid`);
  if(versionCheck!==`months|3|birthday|Happy Birthday! 🎂|f`)throw new Error(`Published Version mismatch: ${versionCheck}`);
  const versionBranches=scalar(`select string_agg(b.branch_code,',' order by b.branch_code) from public.voucher_version_branches vvb join public.branches b on b.id=vvb.branch_id where vvb.version_id=${lit(versionId)}::uuid`);
  if(versionBranches!=='BAHAU,MINES')throw new Error(`Version branch scope mismatch: ${versionBranches}`);
  const allocationId=scalar(`select id from public.partner_voucher_allocations where partner_id=${lit(partnerId)}::uuid and version_id=${lit(versionId)}::uuid order by created_at desc limit 1`);
  const allocationCheck=scalar(`select concat(quantity_allocated,'|',validity_anchor,'|',validity_value,'|',validity_unit,'|',all_branches) from public.partner_voucher_allocations where id=${lit(allocationId)}::uuid`);
  if(allocationCheck!=='12|allocation|100|days|f')throw new Error(`Allocation mismatch: ${allocationCheck}`);
  const allocationBranches=scalar(`select string_agg(b.branch_code,',' order by b.branch_code) from public.partner_voucher_allocation_branches ab join public.branches b on b.id=ab.branch_id where ab.allocation_id=${lit(allocationId)}::uuid`);
  if(allocationBranches!=='MINES')throw new Error(`Allocation branch scope mismatch: ${allocationBranches}`);
  const claimAfter=scalar(`select concat(coalesce((select all_branches::text from public.partner_claim_settings where partner_id=${lit(partnerId)}::uuid),'NULL'),'|',(select count(*) from public.partner_claim_branches where partner_id=${lit(partnerId)}::uuid))`);
  if(claimAfter!==claimBefore)throw new Error(`Allocation unexpectedly rewrote Partner claim scope: before=${claimBefore} after=${claimAfter}`);
  console.log(`Canonical UAT Voucher Engine browser E2E passed for ${templateCode}, including Version scope, per-lot validity and Allocation branch scope.`);
} finally {if(browser)await browser.close();server.kill('SIGTERM');fs.rmSync(root,{recursive:true,force:true});}
