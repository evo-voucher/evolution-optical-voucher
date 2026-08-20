(()=>{
  const cfg=window.EVOLUTION_VOUCHER_BACKEND||{};
  if(!(cfg.enabled===true&&cfg.supabaseUrl&&cfg.publishableKey&&window.supabase))return;

  const db=window.supabase.createClient(cfg.supabaseUrl,cfg.publishableKey,{auth:{persistSession:true}});

  function findStat(label){
    return [...document.querySelectorAll('#stats .stat')].find(card=>
      String(card.querySelector('span')?.textContent||'').trim()===label
    )||null;
  }

  function setStat(label,value){
    const card=findStat(label);
    if(!card)return;
    const out=card.querySelector('b');
    if(out)out.textContent=Number(value||0).toLocaleString();
  }

  async function applyBusinessMetrics(){
    const stats=document.getElementById('stats');
    if(!stats)return;
    try{
      const {data:sessionData}=await db.auth.getSession();
      if(!sessionData?.session)return;
      const {data:realm,error:realmError}=await db.rpc('current_operational_realm');
      if(realmError||!realm?.authenticated||realm?.realm!=='admin')return;
      const {data:s,error}=await db.rpc('admin_dashboard_summary');
      if(error||!s)return;

      setStat('Vouchers',s.vouchers_allocated);
      setStat('Active Vouchers',s.allocation_remaining);
      findStat('Completed Redemptions')?.remove();
    }catch(_){ }
  }

  const observer=new MutationObserver(()=>{
    if(document.querySelector('#stats .stat'))applyBusinessMetrics();
  });
  if(document.body)observer.observe(document.body,{childList:true,subtree:true});
  else document.addEventListener('DOMContentLoaded',()=>observer.observe(document.body,{childList:true,subtree:true}),{once:true});

  setTimeout(applyBusinessMetrics,0);
  setTimeout(applyBusinessMetrics,500);
  setTimeout(applyBusinessMetrics,1500);
})();
