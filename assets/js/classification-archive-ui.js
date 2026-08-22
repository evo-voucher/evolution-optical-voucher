(()=>{
  const cfg=window.EVOLUTION_VOUCHER_BACKEND||{};
  if(!(cfg.enabled===true&&cfg.supabaseUrl&&cfg.publishableKey&&window.supabase))return;
  if(!String(location.pathname||'').toLowerCase().includes('voucher-engine'))return;

  const db=window.supabase.createClient(cfg.supabaseUrl,cfg.publishableKey,{auth:{persistSession:true}});
  const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot',"'":'&#39;'}[c]));

  function installStyle(){
    if(document.getElementById('classificationArchiveStyle'))return;
    const style=document.createElement('style');
    style.id='classificationArchiveStyle';
    style.textContent=`
      .classificationArchiveList{display:grid;gap:9px;margin-top:12px}
      .classificationArchiveRow{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:10px;align-items:center;padding:12px;border:1px solid var(--line);border-radius:13px;background:#0b1738}
      .classificationArchiveMeta{font-size:11px;color:#91a2c4;margin-top:4px}
      .classificationArchiveRow button{min-width:110px}
      .classificationArchiveRow button:disabled{opacity:.5}
      @media(max-width:760px){.classificationArchiveRow{grid-template-columns:1fr}.classificationArchiveRow button{width:100%}}
    `;
    document.head.appendChild(style);
  }

  async function refresh(){
    const list=document.getElementById('classificationArchiveList');
    const msg=document.getElementById('classificationArchiveMsg');
    if(!list)return;
    if(msg)msg.innerHTML='';
    list.innerHTML='<div class="small">Loading classifications…</div>';
    const {data,error}=await db.from('voucher_templates')
      .select('id,template_code,template_name,status,current_version_id,created_at')
      .order('created_at',{ascending:false});
    if(error){list.innerHTML='';if(msg)msg.innerHTML=`<div class="msg err">${esc(error.message||'Unable to load classifications.')}</div>`;return;}
    const rows=(Array.isArray(data)?data:[]).slice().sort((a,b)=>{
      const aArchived=a.status==='archived'?1:0;
      const bArchived=b.status==='archived'?1:0;
      if(aArchived!==bArchived)return aArchived-bArchived;
      return String(b.created_at||'').localeCompare(String(a.created_at||''));
    });
    list.innerHTML=rows.length?rows.map(r=>`<div class="classificationArchiveRow" data-template-id="${esc(r.id)}" data-template-code="${esc(r.template_code)}">
      <div><b>${esc(r.template_code)} — ${esc(r.template_name)}</b><div class="classificationArchiveMeta">Status: ${esc(r.status)}</div></div>
      <button type="button" class="classificationArchiveBtn" ${r.status==='archived'?'disabled':''}>${r.status==='archived'?'Archived':'Archive'}</button>
    </div>`).join(''):'<div class="small">No classifications found.</div>';
  }

  async function archive(row){
    const id=row?.dataset?.templateId||'';
    const code=row?.dataset?.templateCode||'this classification';
    const btn=row?.querySelector('.classificationArchiveBtn');
    const msg=document.getElementById('classificationArchiveMsg');
    if(!id||!btn)return;
    const reason=window.prompt(`Archive ${code}?\n\nThis will stop future versions/allocations for this classification. Existing issued vouchers and history are preserved.\n\nReason (recommended):`,'Retired classification');
    if(reason===null)return;
    if(!window.confirm(`Confirm archive ${code}?\n\nActive versions will become inactive and active allocations for this classification will be closed. Existing issued vouchers remain valid according to their saved snapshot.`))return;
    btn.disabled=true;btn.textContent='Archiving…';
    if(msg)msg.innerHTML='';
    try{
      const {data,error}=await db.rpc('admin_archive_voucher_template',{p_template_id:id,p_reason:(reason||'').trim()||null});
      if(error)throw error;
      if(!data?.success)throw new Error(data?.error||'Archive failed.');
      if(msg)msg.innerHTML=`<div class="msg ok">${esc(code)} archived. Active Versions retired: ${Number(data.versions_retired||0)} • Allocations closed: ${Number(data.allocations_closed||0)}. Issued vouchers were not changed.</div>`;
      await refresh();
      setTimeout(()=>location.reload(),700);
    }catch(e){if(msg)msg.innerHTML=`<div class="msg err">${esc(e?.message||'Archive failed.')}</div>`;btn.disabled=false;btn.textContent='Archive';}
  }

  function mount(){
    if(document.getElementById('classificationArchiveCard'))return true;
    const page=document.getElementById('page-classification');
    if(!page)return false;
    const createCard=page.querySelector(':scope > section.card')||page.querySelector('section.card');
    if(!createCard)return false;
    installStyle();
    const card=document.createElement('section');
    card.id='classificationArchiveCard';card.className='card';
    card.innerHTML=`<div class="top"><div><h2>Manage Classifications</h2><p class="small">Archive classifications you no longer want to use. Historical and already-issued vouchers are preserved.</p></div><button id="classificationArchiveRefresh" type="button">Refresh</button></div><div id="classificationArchiveList" class="classificationArchiveList"></div><div id="classificationArchiveMsg"></div>`;
    createCard.insertAdjacentElement('afterend',card);
    card.addEventListener('click',e=>{const btn=e.target?.closest?.('.classificationArchiveBtn');if(btn)archive(btn.closest('.classificationArchiveRow'));});
    document.getElementById('classificationArchiveRefresh')?.addEventListener('click',refresh);
    refresh();
    return true;
  }

  const start=()=>{
    if(mount())return;
    const observer=new MutationObserver(()=>{if(mount())observer.disconnect();});
    observer.observe(document.documentElement,{childList:true,subtree:true});
  };
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();
