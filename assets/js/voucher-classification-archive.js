(()=>{
  const cfg=window.EVOLUTION_VOUCHER_BACKEND||{};
  if(!(cfg.enabled===true&&cfg.supabaseUrl&&cfg.publishableKey))return;
  if(!String(window.location?.pathname||'').toLowerCase().includes('voucher-engine'))return;

  const db=window.supabase.createClient(cfg.supabaseUrl,cfg.publishableKey,{auth:{storageKey:'evolution-voucher-auth-admin-v2',persistSession:true,autoRefreshToken:true}});
  const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  let busy=false;

  function ensurePanel(){
    if(document.getElementById('classificationArchivePanel'))return document.getElementById('classificationArchivePanel');
    const page=document.getElementById('page-classification');
    const card=page?.querySelector('.card');
    if(!card)return null;
    const panel=document.createElement('div');
    panel.id='classificationArchivePanel';
    panel.innerHTML=`<h3>Existing Classifications</h3><div class="sectionNote">Archive removes a Classification from future use without deleting historical Vouchers. Active Versions will be retired and active allocations for this Classification will be closed.</div><div id="classificationArchiveList" class="tableWrap"><div class="small" style="padding:12px">Loading classifications…</div></div><div id="classificationArchiveMsg"></div>`;
    card.appendChild(panel);
    return panel;
  }

  async function load(){
    const panel=ensurePanel();if(!panel)return;
    const list=document.getElementById('classificationArchiveList');
    const msg=document.getElementById('classificationArchiveMsg');
    if(msg)msg.innerHTML='';
    try{
      const {data:realm,error:realmError}=await db.rpc('current_operational_realm');
      if(realmError)throw realmError;
      if(!realm||realm.authenticated!==true||realm.realm!=='admin'){panel.classList.add('hidden');return;}
      panel.classList.remove('hidden');
      const {data,error}=await db.from('voucher_templates').select('id,template_code,template_name,voucher_category,status,created_at').order('created_at',{ascending:false});
      if(error)throw error;
      const rows=data||[];
      list.innerHTML=!rows.length?'<div class="small" style="padding:12px">No classifications.</div>':`<table><thead><tr><th>Code</th><th>Name</th><th>Category</th><th>Status</th><th>Action</th></tr></thead><tbody>${rows.map(r=>`<tr><td><b>${esc(r.template_code)}</b></td><td>${esc(r.template_name)}</td><td>${esc(r.voucher_category||'')}</td><td><span class="pill">${esc(r.status)}</span></td><td>${r.status==='archived'?'<span class="small">Archived</span>':`<button type="button" data-archive-template="${esc(r.id)}" data-archive-code="${esc(r.template_code)}">Archive</button>`}</td></tr>`).join('')}</tbody></table>`;
    }catch(e){list.innerHTML=`<div class="msg err">${esc(e.message||'Failed to load classifications.')}</div>`;}
  }

  async function archiveTemplate(id,code,button){
    if(busy)return;
    const ok=window.confirm(`Archive ${code}?\n\nThis keeps all historical Vouchers, but retires active Versions and closes active allocations for this Classification.`);
    if(!ok)return;
    busy=true;button.disabled=true;
    const msg=document.getElementById('classificationArchiveMsg');
    if(msg)msg.innerHTML='';
    try{
      const {data,error}=await db.rpc('admin_archive_voucher_template',{p_template_id:id,p_reason:'Archived from Voucher Engine UI'});
      if(error)throw error;
      if(!data?.success)throw new Error(data?.error||'Archive failed.');
      if(msg)msg.innerHTML=`<div class="msg ok">${esc(code)} archived. Historical Vouchers are preserved. Retired Versions: ${Number(data.versions_retired||0)}. Closed allocations: ${Number(data.allocations_closed||0)}.</div>`;
      await load();
      // Refresh the main page selectors/inventory by reloading once the archive succeeds.
      setTimeout(()=>window.location.reload(),350);
    }catch(e){if(msg)msg.innerHTML=`<div class="msg err">${esc(e.message||'Archive failed.')}</div>`;button.disabled=false;}
    finally{busy=false;}
  }

  document.addEventListener('click',e=>{
    const btn=e.target?.closest?.('[data-archive-template]');
    if(!btn)return;
    archiveTemplate(btn.dataset.archiveTemplate,btn.dataset.archiveCode||'Classification',btn);
  });

  const boot=()=>{ensurePanel();load();};
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
  db.auth.onAuthStateChange((_event,session)=>{if(session)setTimeout(load,0);});
})();
