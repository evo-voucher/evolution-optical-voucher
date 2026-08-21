(()=>{
  const cfg=window.EVOLUTION_VOUCHER_BACKEND||{};
  if(!(cfg.enabled===true&&cfg.supabaseUrl&&cfg.publishableKey&&window.supabase))return;
  const path=String(location.pathname||'').toLowerCase();
  const db=window.supabase.createClient(cfg.supabaseUrl,cfg.publishableKey,{auth:{persistSession:true}});
  const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot',"'":'&#39;'}[c]));
  const siteBase=String(cfg.siteBase||'').replace(/\/?$/,'/');

  function installStyle(){
    if(document.getElementById('allocationValidityStyle'))return;
    const s=document.createElement('style');s.id='allocationValidityStyle';
    s.textContent=`.allocation-validity-grid{display:grid;grid-template-columns:1.2fr .7fr .8fr;gap:10px;grid-column:1/-1}.initial-voucher-row{grid-template-columns:minmax(0,1.4fr) minmax(130px,.6fr) auto!important}.allocation-validity-grid .field{margin:0}.validity-note{grid-column:1/-1;font-size:11px;color:#91a2c4;margin-top:-2px}.partner-login-share{margin-top:12px;padding:14px;border:1px solid rgba(101,230,181,.42);border-radius:14px;background:#0d2438}.partner-login-share b{display:block;color:#e9fff7}.partner-login-secret{margin-top:8px;padding:10px;border-radius:10px;background:#101b44;font-family:ui-monospace,monospace;word-break:break-all}.partner-login-actions{display:flex;gap:8px;flex-wrap:wrap;margin-top:10px}@media(max-width:780px){.allocation-validity-grid{grid-template-columns:1fr}.initial-voucher-row{grid-template-columns:1fr!important}.partner-login-actions button{flex:1}}`;
    document.head.appendChild(s);
  }

  function setCreateMsg(text,ok=false){
    const n=document.getElementById('createPartnerMsg');
    if(n)n.innerHTML=text?`<div class="msg ${ok?'ok':'err'}">${esc(text)}</div>`:'';
  }

  async function copyText(text,node){
    try{await navigator.clipboard.writeText(text);if(node)node.textContent='Copied ✓';}
    catch(_){const ta=document.createElement('textarea');ta.value=text;ta.style.position='fixed';ta.style.opacity='0';document.body.appendChild(ta);ta.select();document.execCommand('copy');ta.remove();if(node)node.textContent='Copied ✓';}
  }

  function renderPartnerLoginShare(partnerName,email,password){
    const out=document.getElementById('createPartnerMsg');if(!out||!password)return;
    const url=`${siteBase}partner.html`;
    const text=[`Evolution Optical Partner Portal`,partnerName?`Account: ${partnerName}`:'',`Login Email: ${email}`,`Temporary Password: ${password}`,`Login: ${url}`].filter(Boolean).join('\n');
    const box=document.createElement('div');box.id='partnerAccessShare';box.className='partner-login-share';
    box.innerHTML=`<b>Share Partner Login</b><div class="small">${esc(partnerName)}<br>${esc(email)}<br>${esc(url)}</div><div class="small" style="margin-top:8px">Temporary Password (shown once)</div><div class="partner-login-secret">${esc(password)}</div><div class="partner-login-actions"><button type="button" data-wa>Share via WhatsApp</button><button type="button" data-copy>Copy Login</button></div><div class="small" data-copy-status></div>`;
    box.querySelector('[data-wa]').onclick=()=>window.open(`https://wa.me/?text=${encodeURIComponent(text)}`,'_blank','noopener');
    box.querySelector('[data-copy]').onclick=()=>copyText(text,box.querySelector('[data-copy-status]'));
    out.appendChild(box);
    setTimeout(()=>box.scrollIntoView({block:'center',behavior:'smooth'}),80);
  }

  async function handleCreatePartner(btn){
    const g=id=>document.getElementById(id);
    const partner_code=(g('newPartnerCode')?.value||'').trim().toUpperCase();
    const partner_name=(g('newPartnerName')?.value||'').trim();
    const contact_person=(g('newPartnerContact')?.value||'').trim();
    const contact_phone=(g('newPartnerPhone')?.value||'').trim();
    const email=(g('newPartnerEmail')?.value||'').trim().toLowerCase();
    const staff_limit=Number(g('newPartnerStaffLimit')?.value||0);
    const allocations=[...document.querySelectorAll('.initial-voucher-row')].map(row=>({
      version_id:row.querySelector('.initial-voucher-version')?.value||'',
      quantity:Number(row.querySelector('.initial-voucher-qty')?.value||0)
    }));
    setCreateMsg('');
    if(!partner_code||!partner_name||!email){setCreateMsg('Partner code, name and login email are required.');return;}
    if(!/^[A-Z0-9_-]+$/.test(partner_code)){setCreateMsg('Partner code may use A-Z, 0-9, underscore and hyphen only.');return;}
    if(!Number.isInteger(staff_limit)||staff_limit<0||staff_limit>1000){setCreateMsg('Staff Limit must be 0 to 1000.');return;}
    if(!allocations.length||allocations.some(x=>!x.version_id)){setCreateMsg('Select a Voucher for every Initial Voucher row.');return;}
    if(allocations.some(x=>!Number.isInteger(x.quantity)||x.quantity<1)){setCreateMsg('Each Initial Allocation Quantity must be at least 1.');return;}
    if(new Set(allocations.map(x=>x.version_id)).size!==allocations.length){setCreateMsg('The same Voucher cannot be selected twice during initial setup. Add more later through Voucher Engine.');return;}
    btn.disabled=true;btn.textContent='Creating Partner…';
    try{
      const {data,error}=await db.functions.invoke('create-partner',{body:{partner_code,partner_name,contact_person:contact_person||null,contact_phone:contact_phone||null,email,staff_limit,allocations}});
      if(error)throw error;if(!data?.success||!data?.temporary_password)throw new Error(data?.details||data?.error||'Partner creation failed.');
      setCreateMsg(`Partner ${partner_name} created with ${allocations.length} initial allocation${allocations.length===1?'':'s'}. Voucher validity follows each published Voucher Version.`,true);
      renderPartnerLoginShare(partner_name,email,data.temporary_password);
    }catch(e){setCreateMsg(e?.message||'Partner creation failed.');}
    finally{btn.disabled=false;btn.textContent='Create Partner';}
  }

  function mountAdmin(){
    installStyle();
    document.getElementById('newPartnerPassword')?.closest('.field')?.remove();
    document.querySelectorAll('.initial-voucher-row .allocation-validity-grid').forEach(x=>x.remove());
    const mo=new MutationObserver(()=>document.querySelectorAll('.initial-voucher-row .allocation-validity-grid').forEach(x=>x.remove()));
    mo.observe(document.documentElement,{childList:true,subtree:true});
    document.addEventListener('click',e=>{
      const btn=e.target?.closest?.('#createPartnerBtn');if(!btn)return;
      e.preventDefault();e.stopPropagation();e.stopImmediatePropagation();handleCreatePartner(btn);
    },true);
  }

  function mountEngine(){
    installStyle();

    const titleCaseTheme=value=>String(value||'classic').replace(/_/g,' ').replace(/\b\w/g,c=>c.toUpperCase());
    let decoratingVersionLabels=false;

    async function decorateAllocationVersionLabels(){
      if(decoratingVersionLabels)return;
      const select=document.getElementById('allocationVersion');
      if(!select)return;
      const options=[...select.options].filter(option=>option.value);
      const versionIds=options.map(option=>option.value);
      if(!versionIds.length)return;
      decoratingVersionLabels=true;
      try{
        const {data:versionRows,error:versionError}=await db.from('voucher_versions').select('id,template_id,theme_override_code,status').in('id',versionIds).eq('status','active');
        if(versionError||!Array.isArray(versionRows))return;
        const templateIds=[...new Set(versionRows.map(row=>row.template_id).filter(Boolean))];
        let templateThemes=new Map();
        if(templateIds.length){
          const {data:templateRows,error:templateError}=await db.from('voucher_templates').select('id,theme_code').in('id',templateIds);
          if(!templateError&&Array.isArray(templateRows))templateThemes=new Map(templateRows.map(row=>[row.id,row.theme_code]));
        }
        const versionsById=new Map(versionRows.map(row=>[row.id,row]));
        options.forEach(option=>{
          const row=versionsById.get(option.value);if(!row)return;
          const baseLabel=option.dataset.baseLabel||option.textContent;
          option.dataset.baseLabel=baseLabel;
          const theme=titleCaseTheme(row.theme_override_code||templateThemes.get(row.template_id)||'classic');
          const desired=`${baseLabel} · ${theme}`;
          if(option.textContent!==desired)option.textContent=desired;
        });
      }finally{decoratingVersionLabels=false;}
    }

    async function syncValidityFromSelectedVersion(force=false){
      const wrap=document.getElementById('engineValidityControls');
      const versionId=document.getElementById('allocationVersion')?.value||'';
      if(!wrap||!versionId)return;
      if(!force&&wrap.dataset.validityDirty==='1')return;
      const {data,error}=await db.from('voucher_versions').select('validity_mode,valid_days,valid_months,status').eq('id',versionId).eq('status','active').maybeSingle();
      if(error||!data)return;
      const anchor=document.getElementById('allocationValidityAnchor');
      const value=document.getElementById('allocationValidityValue');
      const unit=document.getElementById('allocationValidityUnit');
      if(!anchor||!value||!unit)return;
      anchor.value='issue';
      if(data.validity_mode==='days'&&Number.isInteger(data.valid_days)&&data.valid_days>0){value.value=String(data.valid_days);unit.value='days';}
      else if(data.validity_mode==='months'&&Number.isInteger(data.valid_months)&&data.valid_months>0){value.value=String(data.valid_months);unit.value='months';}
      else if(data.validity_mode==='days_after_issue'&&Number.isInteger(data.valid_days)&&data.valid_days>0){value.value=String(data.valid_days);unit.value='days';}
      else if(data.validity_mode==='calendar_months_after_issue'&&Number.isInteger(data.valid_months)&&data.valid_months>0){value.value=String(data.valid_months);unit.value='months';}
      else return;
      wrap.dataset.validityDirty='0';wrap.dataset.validitySource='version';
      const note=wrap.querySelector('.validity-note');if(note)note.textContent='Defaults from the selected Voucher Version. Change them only when this allocation lot needs an intentional override.';
    }

    const tryMount=()=>{
      const qty=document.getElementById('allocationQty');if(!qty||document.getElementById('engineValidityControls'))return false;
      const grid=qty.closest('.grid3');if(!grid)return false;
      const wrap=document.createElement('div');wrap.id='engineValidityControls';wrap.className='allocation-validity-grid';wrap.dataset.validityDirty='0';wrap.innerHTML=`
        <div class="field"><label>Validity Start</label><select id="allocationValidityAnchor"><option value="issue">From Issue Date</option><option value="allocation">Valid From</option></select></div>
        <div class="field"><label>Validity Value</label><input id="allocationValidityValue" type="number" min="1" step="1" value="3"></div>
        <div class="field"><label>Validity Unit</label><select id="allocationValidityUnit"><option value="months">Months</option><option value="days">Days</option></select></div>
        <div class="validity-note">Defaults from the selected Voucher Version. Change them only when this allocation lot needs an intentional override.</div>`;
      grid.insertAdjacentElement('afterend',wrap);
      ['allocationValidityAnchor','allocationValidityValue','allocationValidityUnit'].forEach(id=>{const el=document.getElementById(id);if(!el)return;const markDirty=()=>{wrap.dataset.validityDirty='1';wrap.dataset.validitySource='override';};el.addEventListener('change',markDirty);if(id==='allocationValidityValue')el.addEventListener('input',markDirty);});
      const versionSelect=document.getElementById('allocationVersion');if(versionSelect){versionSelect.addEventListener('change',()=>{wrap.dataset.validityDirty='0';syncValidityFromSelectedVersion(true);});decorateAllocationVersionLabels();const labelObserver=new MutationObserver(()=>decorateAllocationVersionLabels());labelObserver.observe(versionSelect,{childList:true});if(versionSelect.value)syncValidityFromSelectedVersion(true);}
      return true;
    };
    if(!tryMount()){const mo=new MutationObserver(()=>{if(tryMount())mo.disconnect()});mo.observe(document.documentElement,{childList:true,subtree:true});}

    document.addEventListener('click',async e=>{
      const btn=e.target?.closest?.('#allocateBtn');if(!btn||!document.getElementById('allocationValidityAnchor'))return;
      e.preventDefault();e.stopPropagation();e.stopImmediatePropagation();
      const msgNode=document.getElementById('allocationMsg');const show=(text,ok=false)=>{if(msgNode)msgNode.innerHTML=text?`<div class="msg ${ok?'ok':'err'}">${esc(text)}</div>`:'';};
      const partner=document.getElementById('allocationPartner')?.value||'';const version=document.getElementById('allocationVersion')?.value||'';const qty=Number.parseInt(document.getElementById('allocationQty')?.value||'',10);const all=!!document.getElementById('allocationAllBranches')?.checked;const branch_codes=[...document.querySelectorAll('.allocationBranchCheck:checked')].map(x=>x.value);const validity_anchor=document.getElementById('allocationValidityAnchor')?.value||'issue';const validity_value=Number.parseInt(document.getElementById('allocationValidityValue')?.value||'',10);const validity_unit=document.getElementById('allocationValidityUnit')?.value||'';
      show('');if(!partner||!version||!Number.isInteger(qty)||qty<1){show('Partner, Version and positive Quantity are required.');return;}if(!['issue','allocation'].includes(validity_anchor)||!Number.isInteger(validity_value)||validity_value<1||!['days','months'].includes(validity_unit)){show('Select a valid Validity Start, Value and Unit.');return;}if(!all&&!branch_codes.length){show('Select at least one Allocation branch or enable All Branches.');return;}
      btn.disabled=true;btn.textContent='Allocating…';
      try{const {data:preview,error:previewError}=await db.rpc('admin_preview_allocation_effective_branches',{p_partner_id:partner,p_version_id:version,p_all_branches:all,p_branch_codes:all?[]:branch_codes});if(previewError)throw previewError;if(!Array.isArray(preview)||preview.length===0)throw new Error('No effective redemption branch remains after Partner ∩ Version ∩ Allocation.');const {data,error}=await db.functions.invoke('voucher-engine',{body:{action:'allocate',partner_id:partner,version_id:version,quantity:qty,all_branches:all,branch_codes:all?[]:branch_codes,validity_anchor,validity_value,validity_unit}});if(error)throw error;if(!data?.success)throw new Error(data?.error||'Allocation failed.');show(`Allocation created: ${qty} Voucher(s), ${validity_value} ${validity_unit} · ${validity_anchor==='issue'?'From Issue Date':'Valid From'}.`,true);document.getElementById('refreshBtn')?.click();}
      catch(err){show(err?.message||'Allocation failed.');}finally{btn.disabled=false;btn.textContent='Allocate Voucher Stock';}
    },true);
  }

  const start=()=>{if(/\/admin\.html$/i.test(path))mountAdmin();if(path.includes('voucher-engine'))mountEngine();};
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();