(()=>{
  const cfg=window.EVOLUTION_VOUCHER_BACKEND||{};
  if(!(cfg.enabled===true&&cfg.supabaseUrl&&cfg.publishableKey&&window.supabase))return;
  const path=String(location.pathname||'').toLowerCase();
  if(!path.includes('voucher-engine'))return;

  const db=window.supabase.createClient(cfg.supabaseUrl,cfg.publishableKey,{auth:{persistSession:true}});
  const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  let rows=[];

  function installStyle(){
    if(document.getElementById('allocationManagementStyle'))return;
    const s=document.createElement('style');
    s.id='allocationManagementStyle';
    s.textContent=`
      .allocationManagerList{display:grid;gap:10px;margin-top:12px}
      .allocationManagerItem{padding:14px;border:1px solid var(--line);border-radius:14px;background:#0b1738}
      .allocationManagerHead{display:flex;justify-content:space-between;gap:10px;align-items:flex-start}
      .allocationManagerMeta{font-size:11px;color:#91a2c4;line-height:1.55;margin-top:5px}
      .allocationManagerActions{display:grid;grid-template-columns:minmax(110px,.6fr) minmax(180px,1.4fr) auto;gap:8px;margin-top:12px}
      .allocationManagerActions input{margin:0}
      .allocationManagerActions button{min-width:140px}
      .allocationManagerEmpty{font-size:12px;color:#91a2c4;padding:10px 0}
      @media(max-width:760px){.allocationManagerHead{flex-direction:column}.allocationManagerActions{grid-template-columns:1fr}.allocationManagerActions button{width:100%}}
    `;
    document.head.appendChild(s);
  }

  function validityText(r){
    if(r.validity_anchor==='allocation')return r.valid_until?`From Allocation Date • expires ${new Date(r.valid_until).toLocaleDateString()}`:'From Allocation Date';
    if(r.validity_value&&r.validity_unit)return `From Issue Date • ${r.validity_value} ${r.validity_unit}`;
    return 'Validity not configured';
  }

  function cardMarkup(r){
    const remaining=Number(r.remaining_unissued||0);
    return `<div class="allocationManagerItem" data-allocation-id="${esc(r.allocation_id)}">
      <div class="allocationManagerHead">
        <div><b>${esc(r.partner_name)} (${esc(r.partner_code)})</b><div class="allocationManagerMeta">${esc(r.version_name)}<br>${esc(validityText(r))}<br>Allocated ${Number(r.quantity_allocated||0).toLocaleString()} • Issued ${Number(r.issued_count||0).toLocaleString()} • Remaining ${remaining.toLocaleString()}</div></div>
        <span class="pill">${remaining.toLocaleString()} unissued</span>
      </div>
      <div class="allocationManagerActions">
        <input class="revokeQty" type="number" min="1" max="${remaining}" step="1" placeholder="Qty to revoke">
        <input class="revokeReason" type="text" maxlength="180" placeholder="Reason (recommended)">
        <button class="revokeBtn" type="button">Revoke Unissued</button>
      </div>
      <div class="allocationRowMsg"></div>
    </div>`;
  }

  async function refresh(){
    const root=document.getElementById('allocationManagerList');
    const msg=document.getElementById('allocationManagerMsg');
    if(!root)return;
    if(msg)msg.innerHTML='';
    root.innerHTML='<div class="allocationManagerEmpty">Loading allocations…</div>';
    const {data,error}=await db.rpc('admin_active_voucher_allocations');
    if(error){root.innerHTML='';if(msg)msg.innerHTML=`<div class="msg err">${esc(error.message||'Unable to load allocations.')}</div>`;return;}
    rows=Array.isArray(data)?data:[];
    root.innerHTML=rows.length?rows.map(cardMarkup).join(''):'<div class="allocationManagerEmpty">No active allocation has unissued stock.</div>';
  }

  async function revoke(rowEl){
    const id=rowEl?.dataset?.allocationId||'';
    const r=rows.find(x=>x.allocation_id===id);
    const qty=Number.parseInt(rowEl.querySelector('.revokeQty')?.value||'',10);
    const reason=(rowEl.querySelector('.revokeReason')?.value||'').trim();
    const out=rowEl.querySelector('.allocationRowMsg');
    const btn=rowEl.querySelector('.revokeBtn');
    const remaining=Number(r?.remaining_unissued||0);
    if(out)out.innerHTML='';
    if(!r||!Number.isInteger(qty)||qty<1||qty>remaining){if(out)out.innerHTML=`<div class="msg err">Enter a quantity from 1 to ${remaining}.</div>`;return;}
    if(!reason){if(out)out.innerHTML='<div class="msg err">Enter a reason so the audit trail is clear.</div>';return;}
    if(!window.confirm(`Revoke ${qty} unissued voucher(s) from ${r.partner_name} / ${r.version_name}? Issued vouchers will not be changed.`))return;
    btn.disabled=true;btn.textContent='Revoking…';
    try{
      const {data,error}=await db.functions.invoke('voucher-engine',{body:{action:'revoke_unissued',allocation_id:id,quantity:qty,reason}});
      if(error)throw error;
      if(!data?.success)throw new Error(data?.error||'Revoke failed.');
      if(out)out.innerHTML=`<div class="msg ok">Revoked ${qty}. Remaining unissued: ${Number(data?.result?.remaining_unissued??remaining-qty).toLocaleString()}.</div>`;
      await refresh();
      document.getElementById('refreshBtn')?.click();
    }catch(e){if(out)out.innerHTML=`<div class="msg err">${esc(e?.message||'Revoke failed.')}</div>`;}
    finally{btn.disabled=false;btn.textContent='Revoke Unissued';}
  }

  function mount(){
    if(document.getElementById('allocationManagementCard'))return;
    installStyle();
    const inventory=[...document.querySelectorAll('section.card')].find(el=>(el.querySelector('h2')?.textContent||'').trim()==='Current Engine Inventory');
    if(!inventory)return;
    const card=document.createElement('section');
    card.id='allocationManagementCard';
    card.className='card';
    card.innerHTML=`<div class="top"><div><h2>Allocation Management</h2><p class="small">Admin only. Reduce unissued stock through the audited Voucher Engine path. Issued vouchers are never changed.</p></div><button id="allocationManagerRefresh" type="button">Refresh</button></div><div id="allocationManagerList" class="allocationManagerList"></div><div id="allocationManagerMsg"></div>`;
    inventory.insertAdjacentElement('beforebegin',card);
    card.addEventListener('click',e=>{const btn=e.target?.closest?.('.revokeBtn');if(btn)revoke(btn.closest('.allocationManagerItem'));});
    document.getElementById('allocationManagerRefresh')?.addEventListener('click',refresh);
    refresh();
  }

  const start=()=>{
    if(!mount()){
      const mo=new MutationObserver(()=>{if(document.getElementById('allocationManagementCard')){mo.disconnect();return;} mount(); if(document.getElementById('allocationManagementCard'))mo.disconnect();});
      mo.observe(document.documentElement,{childList:true,subtree:true});
    }
  };
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();