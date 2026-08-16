(()=>{
  const cfg=window.EVOLUTION_VOUCHER_BACKEND||{};
  if(!(cfg.enabled===true&&cfg.supabaseUrl&&cfg.publishableKey))return;
  const db=window.supabase.createClient(cfg.supabaseUrl,cfg.publishableKey,{auth:{persistSession:true}});
  const PAGES={
    dashboard:{title:'Dashboard',sub:'Overview of your voucher system.'},
    partners:{title:'Partners',sub:'Create and manage Partner accounts.'},
    branches:{title:'Branches',sub:'Manage branch contact details and lifecycle.'},
    vouchers:{title:'Vouchers',sub:'Search and review voucher activity.'},
    reports:{title:'Reports',sub:'Redemption and Partner performance.'},
    settings:{title:'Settings',sub:'Admin tools and system shortcuts.'}
  };
  let currentPage='dashboard';

  function ensureCard(){
    if(document.getElementById('adminSettingsCard'))return document.getElementById('adminSettingsCard');
    const dash=document.getElementById('dashboardState');if(!dash)return null;
    const card=document.createElement('section');card.id='adminSettingsCard';card.className='card';
    card.innerHTML=`<h2>Settings</h2><p class="small">Admin utility shortcuts. Core permissions and business rules remain enforced by Supabase.</p><div class="toolgrid"><a class="tool" href="voucher-engine.html"><b>Voucher Engine</b><span>Create Template, Publish Version and Allocate.</span></a><a class="tool" href="admin-staff.html"><b>Evolution Staff</b><span>Create and manage Staff accounts.</span></a><a class="tool" href="admin-partner-password.html"><b>Partner Password</b><span>Reset Partner Admin passwords.</span></a><button id="settingsPartners" class="tool"><b>Partner Controls</b><span>Status, limits and claim access.</span></button><button id="settingsBranches" class="tool"><b>Branch Admin</b><span>Branch contact and lifecycle management.</span></button><button id="settingsRefreshAll" class="tool"><b>Refresh All Data</b><span>Reload current Admin data.</span></button></div>`;
    dash.appendChild(card);
    document.getElementById('settingsPartners').onclick=()=>navigate('partners');
    document.getElementById('settingsBranches').onclick=()=>navigate('branches');
    document.getElementById('settingsRefreshAll').onclick=()=>location.reload();
    return card;
  }

  function ensureShell(){
    const dash=document.getElementById('dashboardState');if(!dash)return;
    let head=document.getElementById('adminPageHead');
    if(!head){
      head=document.createElement('section');head.id='adminPageHead';head.className='admin-page-head';
      head.innerHTML='<div><div class="admin-eyebrow">EVOLUTION OPTICAL</div><h2 id="adminPageTitle">Dashboard</h2><p id="adminPageSub">Overview of your voucher system.</p></div>';
      dash.prepend(head);
    }
    if(!document.getElementById('adminBottomNav')){
      const nav=document.createElement('nav');nav.id='adminBottomNav';nav.className='admin-bottom-nav';nav.setAttribute('aria-label','Admin sections');
      const items=[['dashboard','⌂','Home'],['partners','◎','Partners'],['branches','◇','Branches'],['vouchers','▣','Vouchers'],['reports','▥','Reports'],['settings','⚙','Settings']];
      nav.innerHTML=items.map(([p,i,l])=>`<button type="button" data-page="${p}" aria-label="${l}"><span class="admin-nav-icon">${i}</span><span>${l}</span></button>`).join('');
      nav.addEventListener('click',e=>{const b=e.target.closest('button[data-page]');if(b)navigate(b.dataset.page)});
      document.body.appendChild(nav);
    }
  }

  function classify(card){
    if(card.id==='branchAdminCard')return'branches';
    if(card.id==='partnerPerformanceCard')return'reports';
    if(card.id==='adminSettingsCard')return'settings';
    const h=(card.querySelector('h2')?.textContent||'').trim();
    if(['Authoritative Summary','Admin Tools'].includes(h))return'dashboard';
    if(['Create Partner','Partner Controls'].includes(h))return'partners';
    if(h==='Voucher Report')return'vouchers';
    if(h==='Redemption Report')return'reports';
    return null;
  }

  function applySections(){
    const dash=document.getElementById('dashboardState');if(!dash)return;
    [...dash.children].forEach(card=>{
      if(!card.classList?.contains('card'))return;
      const page=classify(card);if(page)card.dataset.adminPage=page;
    });
    navigate(currentPage,false);
  }

  function navigate(page,scroll=true){
    if(!PAGES[page])page='dashboard';currentPage=page;
    document.body.dataset.adminPage=page;
    document.querySelectorAll('#dashboardState > .card[data-admin-page]').forEach(card=>card.classList.toggle('admin-page-hidden',card.dataset.adminPage!==page));
    const m=PAGES[page],t=document.getElementById('adminPageTitle'),s=document.getElementById('adminPageSub');if(t)t.textContent=m.title;if(s)s.textContent=m.sub;
    document.querySelectorAll('#adminBottomNav button[data-page]').forEach(b=>b.classList.toggle('active',b.dataset.page===page));
    try{sessionStorage.setItem('evo-admin-page',page)}catch(_){ }
    if(scroll)document.getElementById('adminPageHead')?.scrollIntoView({behavior:'smooth',block:'start'});
  }
  window.evoAdminNavigate=navigate;

  function installClaimSaveFeedback(){
    if(typeof window.saveClaim!=='function'||window.saveClaim.__evolutionFeedbackWrapped)return;
    const original=window.saveClaim;
    const wrapped=async id=>{
      const box=document.getElementById('claim-'+id),button=box?.querySelector('button[onclick^="saveClaim"]'),previous=button?.textContent||'Save Claim Access';
      if(button){button.disabled=true;button.textContent='Saving...';}
      await original(id);
      const ok=!!document.querySelector('#partnerMsg .msg.ok');
      if(button){button.textContent=ok?'Saved ✓':previous;if(ok)setTimeout(()=>{if(button.isConnected){button.textContent='Save Claim Access';button.disabled=false;}},1800);else button.disabled=false;}
      if(ok){const target=document.getElementById('partnerMsg');if(target)target.innerHTML='<div class="msg ok">Claim access updated successfully.</div>';}
    };
    wrapped.__evolutionFeedbackWrapped=true;window.saveClaim=wrapped;
  }

  async function mount(){
    try{
      const {data,error}=await db.rpc('current_operational_realm');if(error)return;
      if(data?.authenticated===true&&data?.realm==='admin'){
        ensureCard();ensureShell();installClaimSaveFeedback();
        try{currentPage=sessionStorage.getItem('evo-admin-page')||'dashboard'}catch(_){currentPage='dashboard'}
        applySections();
        const dash=document.getElementById('dashboardState');
        if(dash&&!dash.__adminShellObserved){const o=new MutationObserver(()=>applySections());o.observe(dash,{childList:true,subtree:false});dash.__adminShellObserved=true;}
        setTimeout(applySections,450);
      }
    }catch(_){ }
  }
  db.auth.onAuthStateChange(()=>setTimeout(mount,0));setTimeout(mount,350);
})();
