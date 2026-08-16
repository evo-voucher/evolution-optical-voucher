(()=>{
  const cfg=window.EVOLUTION_VOUCHER_BACKEND||{};
  if(!(cfg.enabled===true&&cfg.supabaseUrl&&cfg.publishableKey))return;
  const db=window.supabase.createClient(cfg.supabaseUrl,cfg.publishableKey,{auth:{persistSession:true}});
  function ensureCard(){
    if(document.getElementById('adminSettingsCard'))return document.getElementById('adminSettingsCard');
    const dash=document.getElementById('dashboardState');if(!dash)return null;
    const card=document.createElement('section');card.id='adminSettingsCard';card.className='card';
    card.innerHTML=`<h2>Settings</h2><p class="small">Admin utility shortcuts. No hidden browser-only business rules are stored here.</p><div class="toolgrid"><a class="tool" href="voucher-engine.html"><b>Voucher Engine</b><span>Create Template, Publish Version, Allocate and Retire.</span></a><button id="settingsPartners" class="tool"><b>Partner Controls</b><span>Jump to Partner status, limits and claim access.</span></button><button id="settingsBranches" class="tool"><b>Branch Admin</b><span>Jump to branch contact and lifecycle management.</span></button><button id="settingsRefreshAll" class="tool"><b>Refresh All Data</b><span>Reload current Admin data from canonical backend.</span></button></div>`;
    dash.appendChild(card);
    document.getElementById('settingsPartners').onclick=()=>document.getElementById('partnerControls')?.closest('.card')?.scrollIntoView({behavior:'smooth',block:'start'});
    document.getElementById('settingsBranches').onclick=()=>document.getElementById('branchAdminCard')?.scrollIntoView({behavior:'smooth',block:'start'});
    document.getElementById('settingsRefreshAll').onclick=()=>location.reload();
    return card;
  }
  async function mount(){
    try{const {data,error}=await db.rpc('current_operational_realm');if(error)return;if(data?.authenticated===true&&data?.realm==='admin')ensureCard();}catch(_){ }
  }
  db.auth.onAuthStateChange(()=>setTimeout(mount,0));setTimeout(mount,350);
})();
