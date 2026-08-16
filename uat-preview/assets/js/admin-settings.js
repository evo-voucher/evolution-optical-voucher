(()=>{
  const cfg=window.EVOLUTION_VOUCHER_BACKEND||{};
  if(!(cfg.enabled===true&&cfg.supabaseUrl&&cfg.publishableKey))return;
  const db=window.supabase.createClient(cfg.supabaseUrl,cfg.publishableKey,{auth:{persistSession:true}});
  const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const SECTIONS={
    home:{title:'Admin Dashboard',sub:'Overview and quick access.'},
    partners:{title:'Partner Management',sub:'Create Partners, manage status, staff, claim access and passwords.'},
    vouchers:{title:'Voucher Management',sub:'Voucher Engine, allocation and voucher activity.'},
    operations:{title:'Branch & Staff',sub:'Manage Evolution branches and Staff access.'},
    reports:{title:'Redeem & Reports',sub:'Redemption history, reversals, performance and exports.'},
    settings:{title:'System Settings',sub:'Administrative tools and system shortcuts.'}
  };
  let currentSection='home';
  let initialVoucherVersions=[];
  let initialSetupPromise=null;

  function retireVoucherLimitUI(){
    const createInput=document.getElementById('newPartnerVoucherLimit');
    if(createInput){createInput.value='0';createInput.type='hidden';const field=createInput.closest('.field');if(field)field.style.display='none';}
    document.querySelectorAll('#partnerControls .field').forEach(field=>{const label=(field.querySelector('label')?.textContent||'').trim();if(label==='Voucher Limit')field.remove();});
  }

  function voucherOptions(selected=''){
    return '<option value="">Select published Voucher</option>'+initialVoucherVersions.map(v=>`<option value="${esc(v.version_id)}" ${v.version_id===selected?'selected':''}>${esc(v.voucher_label)} · ${esc(v.version_name||('Version '+v.version_no))}</option>`).join('');
  }

  function addInitialVoucherRow(selected='',quantity=1){
    const list=document.getElementById('initialVoucherRows');if(!list)return;
    const row=document.createElement('div');row.className='initial-voucher-row';
    row.innerHTML=`<div class="field"><label>Voucher</label><select class="initial-voucher-version">${voucherOptions(selected)}</select></div><div class="field"><label>Initial Allocation Quantity</label><input class="initial-voucher-qty" type="number" min="1" step="1" value="${Number.isInteger(quantity)&&quantity>0?quantity:1}"></div><button type="button" class="initial-voucher-remove">Remove</button>`;
    row.querySelector('.initial-voucher-remove').onclick=()=>{row.remove();if(!document.querySelector('.initial-voucher-row'))addInitialVoucherRow();};
    list.appendChild(row);
  }

  async function ensureInitialSetupUI(){
    if(document.getElementById('initialVoucherRows'))return;
    if(initialSetupPromise)return initialSetupPromise;
    initialSetupPromise=(async()=>{
      const code=document.getElementById('newPartnerCode');
      const form=code?.closest('.card')?.querySelector('.formgrid');
      if(!form)return;

      const [versionsRes,branchesRes]=await Promise.all([db.rpc('admin_active_voucher_versions'),db.rpc('admin_active_branches')]);
      if(versionsRes.error)throw versionsRes.error;if(branchesRes.error)throw branchesRes.error;
      if(document.getElementById('initialVoucherRows'))return;
      initialVoucherVersions=versionsRes.data||[];const branches=branchesRes.data||[];

      const wrap=document.createElement('div');wrap.id='initialVoucherSetup';wrap.className='partner-initial-setup';
      wrap.innerHTML=`<div class="initial-voucher-field"><div class="initial-voucher-head"><div><label>Initial Vouchers</label><div class="small">Choose one or more published Vouchers. Each Voucher has its own initial allocation.</div></div><button id="addInitialVoucherBtn" type="button">+ Add Voucher</button></div><div id="initialVoucherRows"></div></div><div class="field initial-branch-field"><label>Claim Branch</label><label class="check"><input id="initialAllBranches" type="checkbox"><span>All active branches</span></label><div id="initialBranchChoices" class="branchgrid"></div></div>`;
      form.appendChild(wrap);

      if(!document.getElementById('initialSetupStyle')){
        const style=document.createElement('style');style.id='initialSetupStyle';
        style.textContent=`.partner-initial-setup{display:contents}.initial-voucher-field,.initial-branch-field{grid-column:1/-1}.initial-voucher-head{display:flex;justify-content:space-between;gap:12px;align-items:flex-end;margin-bottom:8px}.initial-voucher-head label{margin:0}.initial-voucher-head button{width:auto!important;min-width:126px!important}.initial-voucher-row{display:grid;grid-template-columns:minmax(0,1.4fr) minmax(150px,.6fr) auto;gap:10px;align-items:end;padding:12px;margin:8px 0;border:1px solid rgba(118,91,255,.5);border-radius:16px;background:#0a1736}.initial-voucher-row .field{margin:0}.initial-voucher-remove{min-width:88px!important;background:linear-gradient(180deg,#8a3e50,#5e2132)!important;border-color:#c45a6c!important}.initial-branch-field>.check{margin:6px 0 10px}.initial-branch-field .branchgrid{padding:12px;border:1px solid rgba(118,91,255,.5);border-radius:16px;background:#0a1736}.initial-branch-field .check{font-size:13px}.initial-branch-field input[type=checkbox]{min-height:0!important;width:auto!important}@media(max-width:780px){.initial-voucher-field,.initial-branch-field{grid-column:auto}.initial-voucher-head{align-items:flex-start;flex-direction:column}.initial-voucher-row{grid-template-columns:1fr}.initial-voucher-remove{width:100%!important}}`;
        document.head.appendChild(style);
      }

      document.getElementById('initialBranchChoices').innerHTML=branches.map(b=>`<label class="check"><input type="checkbox" class="initial-branch" value="${esc(b.branch_code)}"><span>${esc(b.branch_name)} (${esc(b.branch_code)})</span></label>`).join('')||'<div class="empty">No active branches.</div>';
      const all=document.getElementById('initialAllBranches');
      const sync=()=>document.querySelectorAll('.initial-branch').forEach(x=>x.disabled=all.checked);
      all.onchange=sync;sync();
      document.getElementById('addInitialVoucherBtn').onclick=()=>addInitialVoucherRow();
      addInitialVoucherRow();
    })();
    try{return await initialSetupPromise;}finally{initialSetupPromise=null;}
  }

  function setCreateMsg(text,ok=false){const n=document.getElementById('createPartnerMsg');if(n)n.innerHTML=text?`<div class="msg ${ok?'ok':'err'}">${esc(text)}</div>`:'';}

  function installCreatePartnerV4(){
    const btn=document.getElementById('createPartnerBtn');if(!btn||btn.__multiInitialInstalled)return;
    btn.__multiInitialInstalled=true;
    btn.onclick=async()=>{
      const g=id=>document.getElementById(id);
      const partner_code=(g('newPartnerCode')?.value||'').trim().toUpperCase();
      const partner_name=(g('newPartnerName')?.value||'').trim();
      const contact_person=(g('newPartnerContact')?.value||'').trim();
      const contact_phone=(g('newPartnerPhone')?.value||'').trim();
      const email=(g('newPartnerEmail')?.value||'').trim().toLowerCase();
      const password=g('newPartnerPassword')?.value||'';
      const staff_limit=Number(g('newPartnerStaffLimit')?.value||0);
      const all_branches=!!g('initialAllBranches')?.checked;
      const branch_codes=[...document.querySelectorAll('.initial-branch:checked')].map(x=>x.value);
      const allocations=[...document.querySelectorAll('.initial-voucher-row')].map(row=>({version_id:row.querySelector('.initial-voucher-version')?.value||'',quantity:Number(row.querySelector('.initial-voucher-qty')?.value||0)}));
      setCreateMsg('');
      if(!partner_code||!partner_name||!email||!password){setCreateMsg('Partner code, name, login email and password are required.');return;}
      if(!/^[A-Z0-9_-]+$/.test(partner_code)){setCreateMsg('Partner code may use A-Z, 0-9, underscore and hyphen only.');return;}
      if(password.length<6){setCreateMsg('Password must be at least 6 characters.');return;}
      if(!Number.isInteger(staff_limit)||staff_limit<0||staff_limit>1000){setCreateMsg('Staff Limit must be 0 to 1000.');return;}
      if(!allocations.length||allocations.some(x=>!x.version_id)){setCreateMsg('Select a Voucher for every Initial Voucher row.');return;}
      if(allocations.some(x=>!Number.isInteger(x.quantity)||x.quantity<1)){setCreateMsg('Each Initial Allocation Quantity must be a whole number of at least 1.');return;}
      if(new Set(allocations.map(x=>x.version_id)).size!==allocations.length){setCreateMsg('The same Voucher cannot be selected twice.');return;}
      if(!all_branches&&!branch_codes.length){setCreateMsg('Select at least one Claim Branch.');return;}
      btn.disabled=true;btn.textContent='Creating Partner…';
      try{
        const {data,error}=await db.functions.invoke('create-partner',{body:{partner_code,partner_name,contact_person:contact_person||null,contact_phone:contact_phone||null,email,password,staff_limit,allocations,all_branches,branch_codes}});
        if(error)throw error;if(!data?.success)throw new Error(data?.details||data?.error||'Partner creation failed.');
        setCreateMsg(`Partner ${partner_name} created with ${allocations.length} initial Voucher allocation${allocations.length===1?'':'s'}.`,true);
        setTimeout(()=>location.reload(),900);
      }catch(e){setCreateMsg(e?.message||'Partner creation failed.');btn.disabled=false;btn.textContent='Create Partner';}
    };
  }

  async function purgeExpiredUnredeemed(){
    try{await db.rpc('admin_purge_expired_unredeemed_vouchers',{});}catch(_){ }
  }

  function ensureSettingsCard(){
    if(document.getElementById('adminSettingsCard'))return document.getElementById('adminSettingsCard');
    const dash=document.getElementById('dashboardState');if(!dash)return null;
    const card=document.createElement('section');card.id='adminSettingsCard';card.className='card';
    card.innerHTML=`<h2>System Settings</h2><p class="small">Administrative utilities. Core permissions and business rules remain enforced by Supabase.</p><div class="toolgrid"><a class="tool" href="voucher-engine.html"><b>Voucher Engine</b><span>Create Template, Publish Version and Allocate.</span></a><a class="tool" href="admin-staff.html"><b>Evolution Staff</b><span>Create and manage Staff accounts.</span></a><a class="tool" href="admin-partner-password.html"><b>Partner Password</b><span>Reset Partner Admin passwords.</span></a><button id="settingsRefreshAll" class="tool"><b>Refresh All Data</b><span>Reload current Admin data from the canonical backend.</span></button></div>`;
    dash.appendChild(card);document.getElementById('settingsRefreshAll').onclick=()=>location.reload();return card;
  }

  function ensureHub(){
    const dash=document.getElementById('dashboardState');if(!dash)return;
    let head=document.getElementById('adminPageHead');
    if(!head){head=document.createElement('section');head.id='adminPageHead';head.className='admin-page-head';head.innerHTML=`<button id="adminBackBtn" type="button" class="admin-back hidden">← Back</button><div><div class="admin-eyebrow">EVOLUTION OPTICAL</div><h2 id="adminPageTitle">Admin Dashboard</h2><p id="adminPageSub">Overview and quick access.</p></div>`;dash.prepend(head);document.getElementById('adminBackBtn').onclick=()=>navigate('home');}
    let hub=document.getElementById('adminHubCard');
    if(!hub){hub=document.createElement('section');hub.id='adminHubCard';hub.className='card admin-hub-card';hub.dataset.adminSection='home';hub.innerHTML=`<h2>Management</h2><div class="admin-hub-grid"><button type="button" data-admin-open="partners" class="admin-hub-btn"><span class="admin-hub-icon">◎</span><span><b>Partner Management</b><small>Create Partner, claim access, staff & password.</small></span><span class="admin-hub-arrow">›</span></button><button type="button" data-admin-open="vouchers" class="admin-hub-btn"><span class="admin-hub-icon">▣</span><span><b>Voucher Management</b><small>Engine, allocation & voucher records.</small></span><span class="admin-hub-arrow">›</span></button><button type="button" data-admin-open="operations" class="admin-hub-btn"><span class="admin-hub-icon">◇</span><span><b>Branch & Staff</b><small>Branches and Evolution Staff accounts.</small></span><span class="admin-hub-arrow">›</span></button><button type="button" data-admin-open="reports" class="admin-hub-btn"><span class="admin-hub-icon">▥</span><span><b>Redeem & Reports</b><small>Redemptions, reversals, performance & export.</small></span><span class="admin-hub-arrow">›</span></button><button type="button" data-admin-open="settings" class="admin-hub-btn"><span class="admin-hub-icon">⚙</span><span><b>System Settings</b><small>Admin utilities and system shortcuts.</small></span><span class="admin-hub-arrow">›</span></button></div>`;const summary=[...dash.children].find(el=>el.classList?.contains('card')&&(el.querySelector('h2')?.textContent||'').trim()==='Authoritative Summary');if(summary)summary.insertAdjacentElement('afterend',hub);else dash.appendChild(hub);hub.addEventListener('click',e=>{const b=e.target.closest('[data-admin-open]');if(b)navigate(b.dataset.adminOpen);});}
    if(!document.getElementById('adminHubStyle')){const style=document.createElement('style');style.id='adminHubStyle';style.textContent=`#adminBottomNav{display:none!important}.admin-page-head{display:flex;gap:12px;align-items:center;margin:4px 2px 14px}.admin-page-head>div{flex:1}.admin-eyebrow{font-size:10px;font-weight:900;letter-spacing:.18em;color:#8feaff;margin-bottom:4px}.admin-page-head h2{margin:0 0 4px!important}.admin-page-head p{margin:0!important}.admin-back{width:auto!important;min-width:88px!important;min-height:40px!important;padding:8px 12px!important}.admin-hub-grid{display:grid;gap:12px}.admin-hub-btn{width:100%!important;display:grid!important;grid-template-columns:44px 1fr 24px!important;gap:12px!important;align-items:center!important;text-align:left!important;padding:16px!important;min-height:82px!important}.admin-hub-btn b{display:block;font-size:16px;margin-bottom:4px}.admin-hub-btn small{display:block;color:#bcc3e3;font-size:12px;line-height:1.4;font-weight:600}.admin-hub-icon{display:grid;place-items:center;width:42px;height:42px;border-radius:14px;background:rgba(141,92,255,.18);border:1px solid rgba(34,207,231,.32);font-size:20px}.admin-hub-arrow{font-size:30px;line-height:1;color:#8feaff;text-align:right}.admin-section-hidden{display:none!important}@media(max-width:560px){.admin-page-head{align-items:flex-start}.admin-page-head h2{font-size:22px!important}.admin-hub-btn{grid-template-columns:40px 1fr 18px!important;padding:14px!important}.admin-hub-icon{width:38px;height:38px}}`;document.head.appendChild(style);}
  }

  function classify(card){if(card.id==='adminHubCard')return'home';if(card.id==='branchAdminCard')return'operations';if(card.id==='partnerPerformanceCard')return'reports';if(card.id==='adminSettingsCard')return'settings';const h=(card.querySelector('h2')?.textContent||'').trim();if(h==='Authoritative Summary')return'home';if(['Create Partner','Partner Controls'].includes(h))return'partners';if(h==='Admin Tools')return'settings';if(h==='Voucher Report')return'vouchers';if(h==='Redemption Report')return'reports';return null;}
  function applySections(){const dash=document.getElementById('dashboardState');if(!dash)return;[...dash.children].forEach(card=>{if(!card.classList?.contains('card'))return;const section=classify(card);if(section)card.dataset.adminSection=section;});retireVoucherLimitUI();navigate(currentSection,false);}
  function navigate(section,scroll=true){if(!SECTIONS[section])section='home';currentSection=section;document.body.dataset.adminSection=section;document.querySelectorAll('#dashboardState > .card[data-admin-section]').forEach(card=>card.classList.toggle('admin-section-hidden',card.dataset.adminSection!==section));const m=SECTIONS[section],t=document.getElementById('adminPageTitle'),s=document.getElementById('adminPageSub'),back=document.getElementById('adminBackBtn');if(t)t.textContent=m.title;if(s)s.textContent=m.sub;if(back)back.classList.toggle('hidden',section==='home');try{sessionStorage.setItem('evo-admin-section',section)}catch(_){ }if(scroll){if(section==='partners')window.scrollTo({top:0,left:0,behavior:'auto'});else document.getElementById('adminPageHead')?.scrollIntoView({behavior:'smooth',block:'start'});}}window.evoAdminNavigate=navigate;

  function installClaimSaveFeedback(){if(typeof window.saveClaim!=='function'||window.saveClaim.__evolutionFeedbackWrapped)return;const original=window.saveClaim;const wrapped=async id=>{const box=document.getElementById('claim-'+id),button=box?.querySelector('button[onclick^="saveClaim"]'),previous=button?.textContent||'Save Claim Access';if(button){button.disabled=true;button.textContent='Saving...';}await original(id);const ok=!!document.querySelector('#partnerMsg .msg.ok');if(button){button.textContent=ok?'Saved ✓':previous;if(ok)setTimeout(()=>{if(button.isConnected){button.textContent='Save Claim Access';button.disabled=false;}},1800);else button.disabled=false;}if(ok){const target=document.getElementById('partnerMsg');if(target)target.innerHTML='<div class="msg ok">Claim access updated successfully.</div>';}};wrapped.__evolutionFeedbackWrapped=true;window.saveClaim=wrapped;}

  async function mount(){
    try{
      const {data,error}=await db.rpc('current_operational_realm');if(error)return;
      if(data?.authenticated===true&&data?.realm==='admin'){
        await purgeExpiredUnredeemed();
        ensureSettingsCard();ensureHub();installClaimSaveFeedback();retireVoucherLimitUI();
        await ensureInitialSetupUI();installCreatePartnerV4();
        try{currentSection=sessionStorage.getItem('evo-admin-section')||'home'}catch(_){currentSection='home'}
        applySections();
        const dash=document.getElementById('dashboardState');if(dash&&!dash.__adminHubObserved){const o=new MutationObserver(()=>applySections());o.observe(dash,{childList:true,subtree:false});dash.__adminHubObserved=true;}
        const pc=document.getElementById('partnerControls');if(pc&&!pc.__voucherLimitObserved){const o2=new MutationObserver(()=>retireVoucherLimitUI());o2.observe(pc,{childList:true,subtree:true});pc.__voucherLimitObserved=true;}
        setTimeout(applySections,450);
      }
    }catch(e){setCreateMsg(e?.message||'Unable to load Partner setup options.');}
  }
  db.auth.onAuthStateChange(()=>setTimeout(mount,0));setTimeout(mount,350);
})();