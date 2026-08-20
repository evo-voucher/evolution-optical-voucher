(()=>{
  const cfg=window.EVOLUTION_VOUCHER_BACKEND||{};
  if(!(cfg.enabled===true&&cfg.supabaseUrl&&cfg.publishableKey))return;

  function installPartnerShareRecovery(){
    const pendingKey='evo_pending_partner_access_share',readyKey='evo_ready_partner_access_share';
    const btn=document.getElementById('createPartnerBtn'),out=document.getElementById('createPartnerMsg');
    if(btn&&out&&!btn.dataset.partnerShareRecovery){
      btn.dataset.partnerShareRecovery='1';
      btn.addEventListener('click',()=>{
        const name=(document.getElementById('newPartnerName')?.value||'').trim();
        const email=(document.getElementById('newPartnerEmail')?.value||'').trim().toLowerCase();
        try{sessionStorage.removeItem(readyKey);sessionStorage.setItem(pendingKey,JSON.stringify({name,email}))}catch(_){}
      },true);
      new MutationObserver(()=>{
        if(!out.querySelector('.msg.ok'))return;
        try{
          const pending=JSON.parse(sessionStorage.getItem(pendingKey)||'null');
          if(pending?.email){sessionStorage.setItem(readyKey,JSON.stringify(pending));sessionStorage.removeItem(pendingKey)}
        }catch(_){}
      }).observe(out,{childList:true,subtree:true});
    }
    let ready=null;
    try{ready=JSON.parse(sessionStorage.getItem(readyKey)||'null')}catch(_){}
    if(!ready?.email)return;
    let tries=0;
    const timer=setInterval(()=>{
      tries++;
      const openPartners=document.querySelector('[data-admin-open="partners"]');
      if(openPartners)openPartners.click();
      const addPartner=document.querySelector('[data-partner-view="add"]');
      if(addPartner){addPartner.click();clearInterval(timer);setTimeout(()=>document.getElementById('partnerAccessShare')?.scrollIntoView({block:'center',behavior:'smooth'}),150)}
      else if(tries>80)clearInterval(timer);
    },100);
  }

  installPartnerShareRecovery();
  if(!document.querySelector('script[data-portal-access-share]')){
    const shareScript=document.createElement('script');
    shareScript.dataset.portalAccessShare='1';
    shareScript.src='assets/js/portal-access-share.js?v=20260818-26';
    document.head.appendChild(shareScript);
  }
  if(!document.querySelector('script[data-admin-summary-business-metrics]')){
    const summaryScript=document.createElement('script');
    summaryScript.dataset.adminSummaryBusinessMetrics='1';
    summaryScript.src='assets/js/admin-summary-business-metrics.js?v=20260821-1';
    document.head.appendChild(summaryScript);
  }
  const db=window.supabase.createClient(cfg.supabaseUrl,cfg.publishableKey,{auth:{persistSession:true}});
  const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const num=v=>Number(v||0);
  const pct=(a,b)=>b>0?`${((a/b)*100).toFixed(1)}%`:'0.0%';
  const within=(value,days)=>{if(!days)return true;if(!value)return false;const d=new Date(value);return Number.isFinite(d.getTime())&&d>=new Date(Date.now()-days*86400000)};
  let mounted=false;

  function ensureCard(){
    if(document.getElementById('partnerPerformanceCard'))return document.getElementById('partnerPerformanceCard');
    const anchor=document.querySelector('#partnerControls')?.closest('.card');
    if(!anchor)return null;
    const card=document.createElement('section');
    card.id='partnerPerformanceCard';card.className='card';
    card.innerHTML=`<div class="toprow"><div><h2>Partner Performance</h2><p class="small">Canonical issued and redemption activity by Partner.</p></div><select id="performanceRange" style="max-width:190px"><option value="0">All time</option><option value="30">Last 30 days</option><option value="90">Last 90 days</option><option value="365">Last 365 days</option></select></div><div id="performanceSummary" class="miniStats"></div><div id="performanceTable" class="tablewrap"><div class="empty">Loading Partner performance…</div></div><div id="performanceMsg"></div>`;
    anchor.insertAdjacentElement('afterend',card);
    document.getElementById('performanceRange').addEventListener('change',load);
    return card;
  }

  async function rpc(name,args={}){const{data,error}=await db.rpc(name,args);if(error)throw error;return data}

  async function load(){
    const card=ensureCard();if(!card)return;
    const table=document.getElementById('performanceTable'),summary=document.getElementById('performanceSummary'),msg=document.getElementById('performanceMsg');
    msg.innerHTML='';
    try{
      const realm=await rpc('current_operational_realm');
      if(!realm||realm.authenticated!==true||realm.realm!=='admin'){card.classList.add('hidden');return;}
      card.classList.remove('hidden');
      const [partners,vouchers,reds]=await Promise.all([
        rpc('admin_partner_directory'),
        rpc('admin_voucher_report',{p_partner_id:null,p_limit:500}),
        rpc('admin_redemption_report',{p_partner_id:null,p_limit:500})
      ]);
      const days=num(document.getElementById('performanceRange').value);
      const vv=(vouchers||[]).filter(v=>within(v.issued_at,days));
      const rr=(reds||[]).filter(r=>within(r.redeemed_at,days));
      const by=new Map();
      for(const p of partners||[])by.set(p.partner_id,{...p,issued:0,active:0,redeemed:0,expired:0,revoked:0,completed:0,reversed:0});
      for(const v of vv){if(!by.has(v.partner_id))continue;const x=by.get(v.partner_id);x.issued++;if(['active','redeemed','expired','revoked'].includes(v.voucher_status))x[v.voucher_status]++;}
      for(const r of rr){if(!by.has(r.partner_id))continue;const x=by.get(r.partner_id);if(r.redemption_status==='completed')x.completed++;if(r.redemption_status==='reversed')x.reversed++;}
      const rows=[...by.values()].filter(x=>x.partner_status!=='archived').sort((a,b)=>b.completed-a.completed||b.issued-a.issued||String(a.partner_name).localeCompare(String(b.partner_name)));
      const totalIssued=rows.reduce((s,x)=>s+x.issued,0), totalCompleted=rows.reduce((s,x)=>s+x.completed,0), totalActive=rows.reduce((s,x)=>s+x.active,0);
      summary.innerHTML=[['Partners',rows.length],['Issued',totalIssued],['Active',totalActive],['Completed Redemptions',totalCompleted]].map(([k,v])=>`<div class="miniStat"><span>${esc(k)}</span><b>${num(v).toLocaleString()}</b></div>`).join('');
      table.innerHTML=!rows.length?'<div class="empty">No Partner performance data in this range.</div>':`<table class="list"><thead><tr><th>#</th><th>Partner</th><th>Issued</th><th>Active</th><th>Redeemed</th><th>Completed</th><th>Redemption Rate</th><th>Capacity Left</th><th>Staff</th></tr></thead><tbody>${rows.map((x,i)=>{const limit=num(x.voucher_limit),used=num(x.vouchers_issued),left=limit===0?'Unlimited':Math.max(0,limit-used).toLocaleString();return `<tr><td>${i+1}</td><td>${esc(x.partner_name)}<div class="small">${esc(x.partner_code)}</div></td><td>${x.issued}</td><td>${x.active}</td><td>${x.redeemed}</td><td>${x.completed}</td><td>${pct(x.completed,x.issued)}</td><td>${left}</td><td>${num(x.partner_staff_count)} / ${num(x.staff_limit)}</td></tr>`}).join('')}</tbody></table>`;
    }catch(e){msg.innerHTML=`<div class="msg err">${esc(e.message||'Partner performance failed to load.')}</div>`;}
  }

  async function tryMount(){
    if(mounted)return;
    const {data}=await db.auth.getSession();
    if(!data?.session)return;
    mounted=true;ensureCard();await load();
  }
  db.auth.onAuthStateChange((_event,session)=>{if(session){mounted=false;setTimeout(tryMount,0)}else{document.getElementById('partnerPerformanceCard')?.classList.add('hidden')}});
  setTimeout(tryMount,0);
})();
