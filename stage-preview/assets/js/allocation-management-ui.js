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
    if(r.validity_anchor==='allocation')return r.valid_until?`Valid From • expires ${new Date(r.valid_until).toLocaleDateString()}`:'Valid From';
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

/* Admin-style Voucher Engine navigation. Presentation only: no RPC, Auth or data-flow changes. */
(()=>{
  const path=String(location.pathname||'').toLowerCase();
  if(!path.includes('voucher-engine'))return;

  function installNavStyle(){
    if(document.getElementById('engineAdminNavStyle'))return;
    const s=document.createElement('style');
    s.id='engineAdminNavStyle';
    s.textContent=`
      #engineState.engine-admin-ready>.split,
      #engineState.engine-admin-ready>section.card,
      #engineState.engine-admin-ready>#allocationManagementCard{display:none}
      #engineState.engine-admin-ready.engine-view-setup>.split{display:grid}
      #engineState.engine-admin-ready.engine-view-allocation>section.card[data-engine-view="allocation"]{display:block}
      #engineState.engine-admin-ready.engine-view-inventory>section.card[data-engine-view="inventory"],
      #engineState.engine-admin-ready.engine-view-inventory>#allocationManagementCard{display:block}
      .engineHub{padding:22px;border-radius:22px;background:linear-gradient(155deg,#171746,#0b1b42 58%,#06132f);border:1px solid rgba(122,119,255,.55);box-shadow:0 20px 60px rgba(0,0,0,.28);margin-bottom:14px}
      .engineHubTitle{margin-bottom:6px;font-size:19px;font-weight:900}
      .engineHubText{margin:0 0 16px;color:#91a2c4;font-size:12px;line-height:1.55}
      .engineHubGrid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px}
      .engineHubBtn{min-height:112px!important;padding:15px!important;text-align:left!important;border-radius:17px!important;background:linear-gradient(155deg,#17214d,#0c1b42 65%,#081531)!important;box-shadow:0 12px 26px rgba(0,0,0,.22)!important}
      .engineHubBtn strong{display:block;font-size:15px;line-height:1.3;color:#fff}
      .engineHubBtn span{display:block;margin-top:7px;color:#aebddd;font-size:11px;line-height:1.45;font-weight:600}
      .engineHubBtn .engineHubIcon{font-size:23px;margin-bottom:9px}
      .engineNavBar{display:none;align-items:center;justify-content:space-between;gap:12px;margin:0 0 14px;padding:11px 13px;border:1px solid var(--line);border-radius:15px;background:#0b1738}
      .engine-admin-ready:not(.engine-view-menu)>.engineNavBar{display:flex}
      .engineNavBack{width:auto!important;min-height:40px!important;padding:8px 12px!important;margin:0!important}
      .engineNavLabel{font-size:12px;font-weight:900;color:#dce6ff;text-align:right}
      .engine-admin-ready:not(.engine-view-menu)>.engineHub{display:none}
      #engineState.engine-admin-ready.engine-view-setup>.split{grid-template-columns:1fr}
      #engineState.engine-admin-ready.engine-view-setup>.split>section.card{display:block}
      @media(min-width:900px){#engineState.engine-admin-ready.engine-view-setup>.split{grid-template-columns:1fr 1fr}}
      @media(max-width:760px){
        .engineHub{padding:17px}
        .engineHubGrid{grid-template-columns:1fr 1fr;gap:10px}
        .engineHubBtn{min-height:100px!important;padding:13px!important}
        .engineHubBtn:last-child{grid-column:1/-1}
        .engineNavBar{position:sticky;top:8px;z-index:20;box-shadow:0 10px 28px rgba(0,0,0,.28)}
      }
      @media(max-width:430px){.engineHubGrid{grid-template-columns:1fr}.engineHubBtn:last-child{grid-column:auto}.engineHubBtn{min-height:92px!important}}
    `;
    document.head.appendChild(s);
  }

  function findCard(title){
    return [...document.querySelectorAll('#engineState section.card')].find(el=>(el.querySelector('h2')?.textContent||'').trim()===title)||null;
  }

  function mountNav(){
    const root=document.getElementById('engineState');
    if(!root||document.getElementById('engineHub'))return false;
    const allocation=findCard('3. Allocate to Partner');
    const inventory=findCard('Current Engine Inventory');
    if(!allocation||!inventory)return false;

    installNavStyle();
    allocation.dataset.engineView='allocation';
    inventory.dataset.engineView='inventory';

    const hub=document.createElement('section');
    hub.id='engineHub';hub.className='engineHub';
    hub.innerHTML=`
      <div class="engineHubTitle">Voucher Engine</div>
      <p class="engineHubText">Choose what you want to manage. Business rules and existing Voucher logic stay unchanged.</p>
      <div class="engineHubGrid">
        <button type="button" class="engineHubBtn" data-engine-open="setup"><span class="engineHubIcon">◈</span><strong>Voucher Setup</strong><span>Create classifications and publish a new Voucher Version.</span></button>
        <button type="button" class="engineHubBtn" data-engine-open="allocation"><span class="engineHubIcon">↗</span><strong>Partner Allocation</strong><span>Allocate stock, validity and redemption branch scope to a Partner.</span></button>
        <button type="button" class="engineHubBtn" data-engine-open="inventory"><span class="engineHubIcon">▦</span><strong>Inventory & Allocation</strong><span>Review Engine inventory and manage unissued allocation stock.</span></button>
      </div>`;

    const nav=document.createElement('div');
    nav.className='engineNavBar';
    nav.innerHTML='<button type="button" class="engineNavBack">← Return</button><div class="engineNavLabel">Voucher Engine</div>';

    root.prepend(nav);root.prepend(hub);
    root.classList.add('engine-admin-ready','engine-view-menu');

    const labels={setup:'Voucher Setup',allocation:'Partner Allocation',inventory:'Inventory & Allocation'};
    function show(view){
      root.classList.remove('engine-view-menu','engine-view-setup','engine-view-allocation','engine-view-inventory');
      root.classList.add(`engine-view-${view}`);
      nav.querySelector('.engineNavLabel').textContent=labels[view]||'Voucher Engine';
      if(view==='inventory'){
        document.getElementById('allocationManagerRefresh')?.click();
        document.getElementById('refreshBtn')?.click();
      }
      window.scrollTo({top:0,behavior:'smooth'});
    }
    hub.addEventListener('click',e=>{const btn=e.target.closest('[data-engine-open]');if(btn)show(btn.dataset.engineOpen)});
    nav.querySelector('.engineNavBack').addEventListener('click',()=>show('menu'));
    return true;
  }

  const start=()=>{
    if(mountNav())return;
    const mo=new MutationObserver(()=>{if(mountNav())mo.disconnect()});
    mo.observe(document.documentElement,{childList:true,subtree:true});
  };
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();

/* Classification archive controls. */
(()=>{
  const path=String(location.pathname||'').toLowerCase();
  if(!path.includes('voucher-engine')||document.getElementById('classificationArchiveUiScript'))return;
  const script=document.createElement('script');
  script.id='classificationArchiveUiScript';
  const version=window.EVOLUTION_ASSET_VERSION||Date.now();
  script.src=`assets/js/classification-archive-ui.js?v=${encodeURIComponent(version)}`;
  document.head.appendChild(script);
})();
