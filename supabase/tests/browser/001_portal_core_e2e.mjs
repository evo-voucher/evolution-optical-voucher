import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, execSync, spawn } from 'node:child_process';
import puppeteer from 'puppeteer-core';

const API_URL='http://127.0.0.1:54321';
const DB_URL='postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const WEB_URL='http://127.0.0.1:4173';
const password='EvoBrowser!123456';
const partnerStaffPassword='PartnerStaff!123456';
const adminCreatedPartnerPassword='AdminCreated!123456';
const adminCreatedStaffPassword='AdminStaff!123456';
const suffix=`${Date.now()}-${Math.floor(Math.random()*100000)}`;
const adminEmail=`browser-admin-${suffix}@example.test`;
const partnerEmail=`browser-partner-${suffix}@example.test`;
const partnerStaffEmail=`browser-partner-staff-${suffix}@example.test`;
const adminCreatedPartnerEmail=`browser-admin-created-${suffix}@example.test`;
const adminCreatedStaffEmail=`browser-admin-staff-${suffix}@example.test`;
const staffEmail=`browser-staff-${suffix}@example.test`;
const partnerCode=`BROWSER_${String(Date.now()).slice(-8)}_${Math.floor(Math.random()*1000)}`;
const adminCreatedPartnerCode=`ADMIN_${String(Date.now()).slice(-8)}_${Math.floor(Math.random()*1000)}`;
const templateCode=`BROWSER_TEMPLATE_${String(Date.now()).slice(-8)}_${Math.floor(Math.random()*1000)}`;

const statusText=execSync('supabase status -o env',{encoding:'utf8'});
const anonKey=statusText.match(/^ANON_KEY="?([^"\n]+)"?/m)?.[1];
if(!anonKey) throw new Error('ANON_KEY not found from local Supabase status');

async function signup(email){
  const r=await fetch(`${API_URL}/auth/v1/signup`,{method:'POST',headers:{apikey:anonKey,'Content-Type':'application/json'},body:JSON.stringify({email,password})});
  const body=await r.json();
  if(!r.ok||!body?.user?.id) throw new Error(`Signup failed for ${email}: ${JSON.stringify(body)}`);
  return body.user.id;
}

function sqlLiteral(v){return `'${String(v).replaceAll("'","''")}'`;}
function runSql(sql){
  execFileSync('psql',[DB_URL,'-v','ON_ERROR_STOP=1'],{input:sql,stdio:['pipe','inherit','inherit']});
}
function queryScalar(sql){
  return execFileSync('psql',[DB_URL,'-Atqc',sql],{encoding:'utf8'}).trim();
}

function prepareWebRoot(){
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'evo-browser-'));
  fs.mkdirSync(path.join(root,'assets','js'),{recursive:true});
  for(const name of ['admin.html','admin-staff.html','partner.html','staff.html','voucher.html']){
    let html=fs.readFileSync(name,'utf8');
    html=html.replace(/const configured=cfg\.enabled===true&&[\s\S]*?;\s*if\(!configured\)return;/,'const configured=cfg.enabled===true;if(!configured)return;');
    if(!html.includes('const configured=cfg.enabled===true;if(!configured)return;')) throw new Error(`Unable to patch local test config guard in ${name}`);
    fs.writeFileSync(path.join(root,name),html);
  }
  fs.writeFileSync(path.join(root,'assets','js','backend-config.js'),`window.EVOLUTION_VOUCHER_BACKEND=Object.freeze({enabled:true,environment:'test',projectId:'local-browser-test',supabaseUrl:'${API_URL}',publishableKey:'${anonKey}',siteBase:'${WEB_URL}/'});\n`);
  return root;
}

async function loginPage(page,file,email,readySelector,loginPassword=password){
  await page.goto(`${WEB_URL}/${file}`,{waitUntil:'networkidle0'});
  await page.type('#email',email);
  await page.type('#password',loginPassword);
  await page.click('#loginBtn');
  await page.waitForSelector(readySelector,{visible:true,timeout:15000});
}

const adminUid=await signup(adminEmail);
const partnerUid=await signup(partnerEmail);
const staffUid=await signup(staffEmail);

const fixtureSql=`
begin;
select set_config('request.jwt.claims','{"role":"service_role"}',true);

insert into public.admin_users(user_id,display_name,status)
values (${sqlLiteral(adminUid)}::uuid,'Browser E2E Admin','active');

insert into public.partners(partner_code,partner_name,contact_person,contact_phone,voucher_limit,vouchers_issued,staff_limit,staff_access_enabled,status)
values (${sqlLiteral(partnerCode)},'Browser E2E Partner','Browser Partner Admin','0123456789',0,0,5,true,'active');

insert into public.partner_users(user_id,partner_id,role,status,staff_name,login_email)
select ${sqlLiteral(partnerUid)}::uuid,p.id,'partner_admin','active','Browser Partner Admin',${sqlLiteral(partnerEmail)}
from public.partners p where p.partner_code=${sqlLiteral(partnerCode)};

insert into public.partner_claim_settings(partner_id,all_branches,updated_by)
select p.id,true,${sqlLiteral(adminUid)}::uuid from public.partners p where p.partner_code=${sqlLiteral(partnerCode)};

insert into public.staff_users(user_id,branch_id,staff_name,role,status)
select ${sqlLiteral(staffUid)}::uuid,b.id,'Browser E2E Staff','staff','active'
from public.branches b where b.branch_code='MINES';

insert into public.voucher_templates(template_code,template_name,voucher_category,status,theme_code,created_by)
values (${sqlLiteral(templateCode)},'Browser E2E RM60','test','active','default',${sqlLiteral(adminUid)}::uuid);

insert into public.voucher_versions(template_id,version_no,version_name,face_value,validity_mode,valid_months,usage_limit,supply_limit,all_branches,status,effective_from,created_by)
select vt.id,1,'Browser E2E v1',60,'months',3,1,10,true,'active',now(),${sqlLiteral(adminUid)}::uuid
from public.voucher_templates vt where vt.template_code=${sqlLiteral(templateCode)};

update public.voucher_templates vt
set current_version_id=vv.id
from public.voucher_versions vv
where vv.template_id=vt.id and vt.template_code=${sqlLiteral(templateCode)} and vv.version_no=1;

insert into public.partner_voucher_access(partner_id,template_id,status,quota_type,created_by)
select p.id,vt.id,'active','allocation',${sqlLiteral(adminUid)}::uuid
from public.partners p cross join public.voucher_templates vt
where p.partner_code=${sqlLiteral(partnerCode)} and vt.template_code=${sqlLiteral(templateCode)};

insert into public.partner_voucher_allocations(partner_id,version_id,quantity_allocated,status,created_by)
select p.id,vv.id,5,'active',${sqlLiteral(adminUid)}::uuid
from public.partners p
join public.voucher_templates vt on vt.template_code=${sqlLiteral(templateCode)}
join public.voucher_versions vv on vv.template_id=vt.id and vv.version_no=1
where p.partner_code=${sqlLiteral(partnerCode)};

commit;
`;
runSql(fixtureSql);

const webRoot=prepareWebRoot();
const server=spawn('python3',['-m','http.server','4173','--bind','127.0.0.1'],{cwd:webRoot,stdio:['ignore','ignore','inherit']});
let browser;
try{
  await new Promise(r=>setTimeout(r,500));
  browser=await puppeteer.launch({headless:true,executablePath:process.env.CHROME_PATH||'/usr/bin/google-chrome',args:['--no-sandbox','--disable-dev-shm-usage']});

  const partnerPage=await browser.newPage();
  await loginPage(partnerPage,'partner.html',partnerEmail,'#dashboardState:not(.hidden)');
  await partnerPage.waitForSelector('#staffManagementCard:not(.hidden)',{visible:true,timeout:15000});
  await partnerPage.type('#staffName','Browser Partner Staff');
  await partnerPage.type('#staffEmail',partnerStaffEmail);
  await partnerPage.type('#staffPassword',partnerStaffPassword);
  await partnerPage.click('#createStaffBtn');
  await partnerPage.waitForSelector('#staffMsg .ok',{visible:true,timeout:15000});
  await partnerPage.waitForFunction(email=>(document.querySelector('#staffDirectory')?.textContent||'').includes(email),{},partnerStaffEmail);
  const partnerStaffCount=queryScalar(`select count(*) from public.partner_users where login_email=${sqlLiteral(partnerStaffEmail)} and role='partner_staff' and status='active' and removed_at is null`);
  if(partnerStaffCount!=='1') throw new Error(`Partner Staff browser creation did not persist canonical active membership. Got ${partnerStaffCount}`);

  await partnerPage.waitForFunction(()=>document.querySelectorAll('#issueVersion option').length>1,{timeout:15000});
  await partnerPage.select('#issueVersion',await partnerPage.$eval('#issueVersion',el=>[...el.options].find(o=>o.value)?.value||''));
  await partnerPage.type('#issueName','Browser Customer');
  await partnerPage.type('#issuePhone','0120001111');
  await partnerPage.click('#issueBtn');
  await partnerPage.waitForSelector('#issueResult .resultLink',{visible:true,timeout:15000});
  const issueText=await partnerPage.$eval('#issueResult',el=>el.textContent||'');
  const publicUrl=await partnerPage.$eval('#issueResult .resultLink',el=>el.href);
  if(!publicUrl) throw new Error(`Partner browser issuance did not return public URL: ${issueText}`);

  const publicToken=new URL(publicUrl).searchParams.get('v')||'';
  if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(publicToken)) {
    throw new Error(`Partner browser returned invalid public token: ${publicToken}`);
  }
  const voucherCode=queryScalar(`select voucher_code from public.vouchers where public_token=${sqlLiteral(publicToken)}::uuid`);
  if(!voucherCode) throw new Error('Canonical voucher row was not found for issued public token');
  if(!issueText.includes(voucherCode)) throw new Error(`Partner UI did not render canonical voucher code ${voucherCode}: ${issueText}`);

  const publicPage=await browser.newPage();
  await publicPage.goto(publicUrl,{waitUntil:'networkidle0'});
  await publicPage.waitForSelector('#voucherState:not(.hidden)',{visible:true,timeout:15000});
  const beforeStatus=await publicPage.$eval('#voucherStatus',el=>el.textContent||'');
  if(!beforeStatus.includes('Valid')) throw new Error(`Public voucher was not valid before redemption: ${beforeStatus}`);
  const shownCode=await publicPage.$eval('#voucherCode',el=>el.textContent||'');
  if(shownCode!==voucherCode) throw new Error(`Public voucher code mismatch. Expected ${voucherCode}, got ${shownCode}`);

  const staffPage=await browser.newPage();
  await loginPage(staffPage,'staff.html',staffEmail,'#operationState:not(.hidden)');
  await staffPage.type('#voucherCode',voucherCode);
  await staffPage.click('#verifyBtn');
  await staffPage.waitForSelector('#verifiedVoucher .msg.ok',{visible:true,timeout:15000});
  await staffPage.click('#redeemBtn');
  await staffPage.waitForSelector('#redeemMsg .ok',{visible:true,timeout:15000});
  await staffPage.waitForFunction(code=>(document.querySelector('#history')?.textContent||'').includes(code),{},voucherCode);

  await publicPage.reload({waitUntil:'networkidle0'});
  await publicPage.waitForSelector('#voucherState:not(.hidden)',{visible:true,timeout:15000});
  const afterStatus=await publicPage.$eval('#voucherStatus',el=>el.textContent||'');
  if(!afterStatus.includes('Redeemed')) throw new Error(`Public voucher did not reflect redeemed status: ${afterStatus}`);

  const adminPage=await browser.newPage();
  await loginPage(adminPage,'admin.html',adminEmail,'#dashboardState:not(.hidden)');
  await adminPage.waitForFunction(code=>(document.querySelector('#voucherReport')?.textContent||'').includes(code),{},voucherCode);
  await adminPage.waitForFunction(code=>(document.querySelector('#redemptionReport')?.textContent||'').includes(code),{},voucherCode);

  await adminPage.type('#newPartnerCode',adminCreatedPartnerCode);
  await adminPage.type('#newPartnerName','Browser Admin Created Partner');
  await adminPage.type('#newPartnerContact','Browser Created Admin');
  await adminPage.type('#newPartnerPhone','0129998888');
  await adminPage.type('#newPartnerEmail',adminCreatedPartnerEmail);
  await adminPage.type('#newPartnerPassword',adminCreatedPartnerPassword);
  await adminPage.$eval('#newPartnerVoucherLimit',el=>el.value='12');
  await adminPage.$eval('#newPartnerStaffLimit',el=>el.value='3');
  await adminPage.click('#createPartnerBtn');
  await adminPage.waitForSelector('#createPartnerMsg .ok',{visible:true,timeout:15000});
  await adminPage.waitForFunction(code=>(document.querySelector('#partnerControls')?.textContent||'').includes(code),{},adminCreatedPartnerCode);

  const adminCreatedPartnerCount=queryScalar(`select count(*) from public.partners p join public.partner_users pu on pu.partner_id=p.id where p.partner_code=${sqlLiteral(adminCreatedPartnerCode)} and p.status='active' and p.voucher_limit=12 and p.staff_limit=3 and pu.login_email=${sqlLiteral(adminCreatedPartnerEmail)} and pu.role='partner_admin' and pu.status='active' and pu.removed_at is null`);
  if(adminCreatedPartnerCount!=='1') throw new Error(`Admin browser Partner provisioning did not persist one canonical active Partner realm. Got ${adminCreatedPartnerCount}`);

  const adminStaffPage=await browser.newPage();
  await adminStaffPage.goto(`${WEB_URL}/admin-staff.html`,{waitUntil:'networkidle0'});
  await adminStaffPage.waitForSelector('#provisionState:not(.hidden)',{visible:true,timeout:15000});
  const minesBranchId=await adminStaffPage.$eval('#staffBranch',el=>[...el.options].find(o=>o.textContent?.includes('(MINES)'))?.value||'');
  if(!minesBranchId) throw new Error('Admin Staff provisioning UI did not expose active MINES branch');
  await adminStaffPage.type('#staffName','Browser Admin Staff');
  await adminStaffPage.type('#staffEmail',adminCreatedStaffEmail);
  await adminStaffPage.type('#staffPassword',adminCreatedStaffPassword);
  await adminStaffPage.select('#staffBranch',minesBranchId);
  await adminStaffPage.select('#staffRole','staff');
  await adminStaffPage.click('#createBtn');
  await adminStaffPage.waitForSelector('#createMsg .ok',{visible:true,timeout:15000});

  const adminCreatedStaffCount=queryScalar(`select count(*) from public.staff_users su join public.branches b on b.id=su.branch_id join auth.users au on au.id=su.user_id where lower(au.email)=lower(${sqlLiteral(adminCreatedStaffEmail)}) and su.staff_name='Browser Admin Staff' and su.role='staff' and su.status='active' and b.branch_code='MINES'`);
  if(adminCreatedStaffCount!=='1') throw new Error(`Admin Staff browser provisioning did not persist one canonical active MINES Staff. Got ${adminCreatedStaffCount}`);

  const adminCreatedPartnerPage=await browser.newPage();
  await loginPage(adminCreatedPartnerPage,'partner.html',adminCreatedPartnerEmail,'#dashboardState:not(.hidden)',adminCreatedPartnerPassword);
  const createdPartnerSessionText=await adminCreatedPartnerPage.$eval('#sessionMeta',el=>el.textContent||'');
  if(!createdPartnerSessionText.includes('role: partner_admin')) throw new Error(`Admin-created Partner login did not resolve to partner_admin realm: ${createdPartnerSessionText}`);

  const adminCreatedStaffPage=await browser.newPage();
  await adminCreatedStaffPage.goto(`${WEB_URL}/staff.html`,{waitUntil:'networkidle0'});
  await adminCreatedStaffPage.waitForSelector('#loginState:not(.hidden)',{visible:true,timeout:15000});
  await adminCreatedStaffPage.type('#email',adminCreatedStaffEmail);
  await adminCreatedStaffPage.type('#password',adminCreatedStaffPassword);
  await adminCreatedStaffPage.click('#loginBtn');
  await adminCreatedStaffPage.waitForSelector('#operationState:not(.hidden)',{visible:true,timeout:15000});

  console.log(`Browser portal core E2E passed for ${voucherCode}, including Partner Staff creation ${partnerStaffEmail}, Admin Partner provisioning ${adminCreatedPartnerEmail}, and Admin Staff provisioning ${adminCreatedStaffEmail}.`);
} finally {
  if(browser) await browser.close();
  server.kill('SIGTERM');
  fs.rmSync(webRoot,{recursive:true,force:true});
}
