(()=>{
  const cfg=window.EVOLUTION_VOUCHER_BACKEND||{};
  if(!(cfg.enabled===true&&cfg.supabaseUrl&&cfg.publishableKey&&window.supabase))return;
  const path=String(location.pathname||'').toLowerCase();
  const db=window.supabase.createClient(cfg.supabaseUrl,cfg.publishableKey,{auth:{persistSession:true}});
  const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

  function installStyle(){
    if(document.getElementById('allocationValidityStyle'))return;
    const s=document.createElement('style');s.id='allocationValidityStyle';
    s.textContent=`.allocation-validity-grid{display:grid;grid-template-columns:1.2fr .7fr .8fr;gap:10px;grid-column:1/-1}.initial-voucher-row{grid-template-columns:minmax(0,1.4fr) minmax(130px,.6fr) auto!important}.initial-voucher-row .allocation-validity-grid{margin-top:2px}.allocation-validity-grid .field{margin:0}.validity-note{grid-column:1/-1;font-size:11px;color:#91a2c4;margin-top:-2px}@media(max-width:780px){.allocation-validity-grid{grid-template-columns:1fr}.initial-voucher-row{grid-template-columns:1fr!important}}`;
    document.head.appendChild(s);
  }

  function validityMarkup(prefix='initial'){
    return `<div class="allocation-validity-grid">
      <div class="field"><label>Validity Start</label><select class="${prefix}-validity-anchor"><option value="issue">From Issue Date</option><option value="allocation">From Allocation Date</option></select></div>
      <div class="field"><label>Validity Value</label><input class="${prefix}-validity-value" type="number" min="1" step="1" value="3"></div>
      <div class="field"><label>Validity Unit</label><select class="${prefix}-validity-unit"><option value="months">Months</option><option value="days">Days</option></select></div>
      <div class="validity-note">Each allocation lot keeps its own validity rule.</div>
    </div>`;
  }

  function enhanceInitialRows(){
    document.querySelectorAll('.initial-voucher-row').forEach(row=>{
      if(row.dataset.validityReady==='1')return;
      row.dataset.validityReady='1';
      row.insertAdjacentHTML('beforeend',validityMarkup('initial'));
      const remove=row.querySelector('.initial-voucher-remove');if(remove)row.appendChild(remove);
    });
  }

  function setCreateMsg(text,ok=false){
    const n=document.getElementById('createPartnerMsg');
    if(n)n.innerHTML=text?`<div class="msg ${ok?'ok':'err'}">${esc(text)}</div>`:'';
  }

  async function handleCreatePartner(btn){
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
    const allocations=[...document.querySelectorAll('.initial-voucher-row')].map(row=>({
      version_id:row.querySelector('.initial-voucher-version')?.value||'',
      quantity:Number(row.querySelector('.initial-voucher-qty')?.value||0),
      validity_anchor:row.querySelector('.initial-validity-anchor')?.value||'issue',
      validity_value:Number(row.querySelector('.initial-validity-value')?.value||0),
      validity_unit:row.querySelector('.initial-validity-unit')?.value||''
    }));
    setCreateMsg('');
    if(!partner_code||!partner_name||!email||!password){setCreateMsg('Partner code, name, login email and password are required.');return;}
    if(!/^[A-Z0-9_-]+$/.test(partner_code)){setCreateMsg('Partner code may use A-Z, 0-9, underscore and hyphen only.');return;}
    if(password.length<6){setCreateMsg('Password must be at least 6 characters.');return;}
    if(!Number.isInteger(staff_limit)||staff_limit<0||staff_limit>1000){setCreateMsg('Staff Limit must be 0 to 1000.');return;}
    if(!allocations.length||allocations.some(x=>!x.version_id)){setCreateMsg('Select a Voucher for every Initial Voucher row.');return;}
    if(allocations.some(x=>!Number.isInteger(x.quantity)||x.quantity<1)){setCreateMsg('Each Initial Allocation Quantity must be at least 1.');return;}
    if(allocations.some(x=>!['issue','allocation'].includes(x.validity_anchor)||!Number.isInteger(x.validity_value)||x.validity_value<1||!['days','months'].includes(x.validity_unit))){setCreateMsg('Every Voucher needs a valid Start, Value and Unit.');return;}
    if(new Set(allocations.map(x=>x.version_id)).size!==allocations.length){setCreateMsg('The same Voucher cannot be selected twice during initial setup. Add more later through Voucher Engine.');return;}
    if(!all_branches&&!branch_codes.length){setCreateMsg('Select at least one Claim Branch.');return;}
    btn.disabled=true;btn.textContent='Creating Partner…';
    try{
      const {data,error}=await db.functions.invoke('create-partner',{body:{partner_code,partner_name,contact_person:contact_person||null,contact_phone:contact_phone||null,email,password,staff_limit,allocations,all_branches,branch_codes}});
      if(error)throw error;if(!data?.success)throw new Error(data?.details||data?.error||'Partner creation failed.');
      setCreateMsg(`Partner ${partner_name} created with ${allocations.length} initial allocation${allocations.length===1?'':'s'} and validity rules.`,true);
      setTimeout(()=>location.reload(),900);
    }catch(e){setCreateMsg(e?.message||'Partner creation failed.');btn.disabled=false;btn.textContent='Create Partner';}
  }

  function mountAdmin(){
    installStyle();
    const scan=()=>enhanceInitialRows();scan();
    const mo=new MutationObserver(scan);mo.observe(document.documentElement,{childList:true,subtree:true});
    document.addEventListener('click',e=>{
      const btn=e.target?.closest?.('#createPartnerBtn');if(!btn)return;
      if(!document.querySelector('.initial-voucher-row .initial-validity-anchor'))return;
      e.preventDefault();e.stopPropagation();e.stopImmediatePropagation();handleCreatePartner(btn);
    },true);
  }

  function mountEngine(){
    installStyle();
    const tryMount=()=>{
      const qty=document.getElementById('allocationQty');if(!qty||document.getElementById('engineValidityControls'))return false;
      const grid=qty.closest('.grid3');if(!grid)return false;
      const wrap=document.createElement('div');wrap.id='engineValidityControls';wrap.className='allocation-validity-grid';wrap.innerHTML=`
        <div class="field"><label>Validity Start</label><select id="allocationValidityAnchor"><option value="issue">From Issue Date</option><option value="allocation">From Allocation Date</option></select></div>
        <div class="field"><label>Validity Value</label><input id="allocationValidityValue" type="number" min="1" step="1" value="3"></div>
        <div class="field"><label>Validity Unit</label><select id="allocationValidityUnit"><option value="months">Months</option><option value="days">Days</option></select></div>
        <div class="validity-note">This rule belongs to this allocation lot only. The same Voucher can be allocated again later with a different validity rule.</div>`;
      grid.insertAdjacentElement('afterend',wrap);return true;
    };
    if(!tryMount()){const mo=new MutationObserver(()=>{if(tryMount())mo.disconnect()});mo.observe(document.documentElement,{childList:true,subtree:true});}

    document.addEventListener('click',async e=>{
      const btn=e.target?.closest?.('#allocateBtn');if(!btn||!document.getElementById('allocationValidityAnchor'))return;
      e.preventDefault();e.stopPropagation();e.stopImmediatePropagation();
      const msgNode=document.getElementById('allocationMsg');
      const show=(text,ok=false)=>{if(msgNode)msgNode.innerHTML=text?`<div class="msg ${ok?'ok':'err'}">${esc(text)}</div>`:'';};
      const partner=document.getElementById('allocationPartner')?.value||'';
      const version=document.getElementById('allocationVersion')?.value||'';
      const qty=Number.parseInt(document.getElementById('allocationQty')?.value||'',10);
      const all=!!document.getElementById('allocationAllBranches')?.checked;
      const branch_codes=[...document.querySelectorAll('.allocationBranchCheck:checked')].map(x=>x.value);
      const validity_anchor=document.getElementById('allocationValidityAnchor')?.value||'issue';
      const validity_value=Number.parseInt(document.getElementById('allocationValidityValue')?.value||'',10);
      const validity_unit=document.getElementById('allocationValidityUnit')?.value||'';
      show('');
      if(!partner||!version||!Number.isInteger(qty)||qty<1){show('Partner, Version and positive Quantity are required.');return;}
      if(!['issue','allocation'].includes(validity_anchor)||!Number.isInteger(validity_value)||validity_value<1||!['days','months'].includes(validity_unit)){show('Select a valid Validity Start, Value and Unit.');return;}
      if(!all&&!branch_codes.length){show('Select at least one Allocation branch or enable All Branches.');return;}
      btn.disabled=true;btn.textContent='Allocating…';
      try{
        const {data:preview,error:previewError}=await db.rpc('admin_preview_allocation_effective_branches',{p_partner_id:partner,p_version_id:version,p_all_branches:all,p_branch_codes:all?[]:branch_codes});
        if(previewError)throw previewError;if(!Array.isArray(preview)||preview.length===0)throw new Error('No effective redemption branch remains after Partner ∩ Version ∩ Allocation.');
        const {data,error}=await db.functions.invoke('voucher-engine',{body:{action:'allocate',partner_id:partner,version_id:version,quantity:qty,all_branches:all,branch_codes:all?[]:branch_codes,validity_anchor,validity_value,validity_unit}});
        if(error)throw error;if(!data?.success)throw new Error(data?.error||'Allocation failed.');
        show(`Allocation created: ${qty} Voucher(s), ${validity_value} ${validity_unit} from ${validity_anchor==='issue'?'Issue Date':'Allocation Date'}.`,true);
        document.getElementById('refreshBtn')?.click();
      }catch(err){show(err?.message||'Allocation failed.');}
      finally{btn.disabled=false;btn.textContent='Allocate Voucher Stock';}
    },true);
  }

  const start=()=>{
    if(/\/admin\.html$/i.test(path))mountAdmin();
    if(path.includes('voucher-engine'))mountEngine();
  };
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();
