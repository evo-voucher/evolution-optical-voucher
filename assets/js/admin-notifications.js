(()=>{
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!path.endsWith('/experience/admin-v2.html'))return;

  const cfg=window.EVOLUTION_VOUCHER_BACKEND||{};
  if(!(cfg.enabled&&cfg.supabaseUrl&&cfg.publishableKey&&window.supabase))return;

  const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const timeText=v=>{if(!v)return '—';const d=new Date(v);return Number.isNaN(d.getTime())?'—':d.toLocaleString();};
  const db=window.supabase.createClient(cfg.supabaseUrl,cfg.publishableKey);
  let rows=[];

  function labelFor(kind,title){
    kind=String(kind||'').toLowerCase();
    if(kind==='voucher_issued')return 'Issued';
    if(kind==='voucher_redeemed')return 'Redeemed';
    if(kind==='redemption_reversed')return 'Reversed';
    const t=String(title||'').toLowerCase();
    if(t.includes('status'))return 'Partner';
    if(t.includes('claim'))return 'Access';
    if(t.includes('staff'))return 'Staff';
    return 'System';
  }

  function installStyle(){
    if(document.getElementById('adminNotificationStyle'))return;
    const s=document.createElement('style');
    s.id='adminNotificationStyle';
    s.textContent=`
      .stat.totalAllocated{text-align:center}
      #adminNotifyBtn{position:relative;white-space:nowrap}
      #adminNotifyBadge{display:none;min-width:18px;height:18px;padding:0 5px;border-radius:999px;background:#ff4d67;color:#fff;font-size:10px;line-height:18px;text-align:center;margin-left:4px}
      #adminNotifyBadge.show{display:inline-block}
      #adminNotifyDrawer{position:fixed;z-index:9999;top:78px;right:12px;width:min(380px,calc(100vw - 24px));max-height:70vh;overflow:auto;background:#0b1430;border:1px solid #263967;border-radius:14px;box-shadow:0 18px 50px rgba(0,0,0,.45);padding:12px}
      #adminNotifyDrawer.hidden{display:none!important}
      .adminNotifyHead{display:flex;align-items:center;gap:8px;padding-bottom:9px;border-bottom:1px solid #21325b}
      .adminNotifyHead b{flex:1;font-size:13px}.adminNotifyHead span{font-size:9px;color:#8d9aba}
      .adminNotifyItem{padding:10px 0;border-bottom:1px solid #1b294c}.adminNotifyItem:last-child{border-bottom:0}
      .adminNotifyTop{display:flex;align-items:center;gap:7px}.adminNotifyTag{font-size:8px;font-weight:900;padding:3px 6px;border:1px solid #35528c;border-radius:999px;color:#9fdfe5}
      .adminNotifyTitle{font-size:11px;font-weight:900}.adminNotifyMeta{font-size:9px;color:#8d9aba;margin-top:4px;line-height:1.45}.adminNotifyUnread{box-shadow:inset 3px 0 0 #70e4ee;padding-left:9px}
      .adminNotifyEmpty{padding:14px 2px;color:#8d9aba;font-size:10px}
      @media(max-width:620px){#adminNotifyDrawer{top:110px;max-height:68vh}}
    `;
    document.head.appendChild(s);
  }

  function installUi(){
    if(document.getElementById('adminNotifyBtn'))return true;
    const top=document.querySelector('header.top');
    if(!top)return false;
    installStyle();
    const btn=document.createElement('button');
    btn.id='adminNotifyBtn';btn.type='button';btn.innerHTML='🔔<span id="adminNotifyBadge"></span>';
    const signOut=document.getElementById('signOut');
    if(signOut)top.insertBefore(btn,signOut);else top.appendChild(btn);
    const drawer=document.createElement('div');
    drawer.id='adminNotifyDrawer';drawer.className='hidden';drawer.innerHTML='<div class="adminNotifyHead"><b>Notifications</b><span>Last 24 hours</span><button id="adminNotifyClose" type="button">×</button></div><div id="adminNotifyList"><div class="adminNotifyEmpty">Loading…</div></div>';
    document.body.appendChild(drawer);
    btn.onclick=openDrawer;
    drawer.querySelector('#adminNotifyClose').onclick=()=>drawer.classList.add('hidden');
    document.addEventListener('pointerdown',e=>{if(drawer.classList.contains('hidden'))return;if(drawer.contains(e.target)||btn.contains(e.target))return;drawer.classList.add('hidden')});
    return true;
  }

  function render(){
    const badge=document.getElementById('adminNotifyBadge');
    const list=document.getElementById('adminNotifyList');
    if(!badge||!list)return;
    const unread=rows.filter(r=>!r.is_read).length;
    badge.textContent=unread>99?'99+':String(unread);
    badge.classList.toggle('show',unread>0);
    if(!rows.length){list.innerHTML='<div class="adminNotifyEmpty">No notifications in the last 24 hours.</div>';return;}
    list.innerHTML=rows.map(r=>`<div class="adminNotifyItem ${r.is_read?'':'adminNotifyUnread'}"><div class="adminNotifyTop"><span class="adminNotifyTag">${esc(labelFor(r.event_type,r.title))}</span><span class="adminNotifyTitle">${esc(r.title||'Activity')}</span></div><div class="adminNotifyMeta">${esc(timeText(r.event_time))}${r.detail?` · ${esc(r.detail)}`:''}</div></div>`).join('');
  }

  async function refresh(){
    const{data,error}=await db.rpc('admin_notifications',{p_limit:30});
    if(error){console.warn('Notifications unavailable',error);return;}
    rows=Array.isArray(data)?data:[];
    render();
  }

  async function openDrawer(){
    const drawer=document.getElementById('adminNotifyDrawer');
    if(!drawer)return;
    drawer.classList.remove('hidden');
    await refresh();
    if(rows.some(r=>!r.is_read)){
      const{error}=await db.rpc('admin_mark_notifications_read');
      if(!error){rows=rows.map(r=>({...r,is_read:true}));render();}
    }
  }

  async function start(){
    if(!installUi())return;
    const{data}=await db.auth.getSession();
    if(!data?.session)return;
    await refresh();
    document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible')refresh()});
    setInterval(()=>{if(document.visibilityState==='visible')refresh()},60000);
  }

  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>setTimeout(start,0),{once:true});else setTimeout(start,0);
})();