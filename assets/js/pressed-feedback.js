(()=>{
  if(window.__evoPressedFeedbackInstalled)return;
  window.__evoPressedFeedbackInstalled=true;
  const selector='button,.btn,.tool,a.card,.moduleBtn,.listToggle,.directoryToggle,.reportCardBtn,.shareLink,.tile,.refresh';
  const style=document.createElement('style');
  style.id='evoPressedFeedbackStyle';
  style.textContent=`
    ${selector}{touch-action:manipulation;-webkit-tap-highlight-color:transparent;-webkit-user-select:none;user-select:none;will-change:transform,filter}
    ${selector}.evo-pressed{transform:translateY(2px) scale(.972)!important;filter:brightness(1.16)!important;box-shadow:0 1px 2px rgba(0,0,0,.16)!important}
  `;
  document.head.appendChild(style);
  let active=null;
  const release=()=>{if(active){active.classList.remove('evo-pressed');active=null;}};
  const press=e=>{
    const el=e.target?.closest?.(selector);
    if(!el||el.matches(':disabled,[aria-disabled="true"]'))return;
    release();active=el;el.classList.add('evo-pressed');
  };
  document.addEventListener('pointerdown',press,{passive:true,capture:true});
  document.addEventListener('pointerup',release,{passive:true,capture:true});
  document.addEventListener('pointercancel',release,{passive:true,capture:true});
  document.addEventListener('pointerleave',e=>{if(active&&e.target===active)release();},{passive:true,capture:true});
  window.addEventListener('blur',release,{passive:true});
})();

(()=>{
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!path.endsWith('/voucher.html'))return;
  const key='evolution-public-voucher-token';
  let token='';
  try{token=String(new URL(location.href).searchParams.get('v')||'').trim();}catch(_){}
  if(token){
    try{sessionStorage.setItem(key,token);}catch(_){}
    window.__EVOLUTION_PUBLIC_VOUCHER_TOKEN=token;
    return;
  }
  try{token=String(sessionStorage.getItem(key)||'').trim();}catch(_){}
  if(!token)return;
  window.__EVOLUTION_PUBLIC_VOUCHER_TOKEN=token;
  try{
    const url=new URL(location.href);
    url.searchParams.set('v',token);
    history.replaceState(null,'',url.pathname+url.search+url.hash);
  }catch(_){}
})();

(()=>{
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!path.endsWith('/voucher-engine.html')&&!path.endsWith('/voucher.html'))return;
  if(document.getElementById('voucherThemeIntegrationScript'))return;
  const script=document.createElement('script');
  script.id='voucherThemeIntegrationScript';
  const version=window.EVOLUTION_ASSET_VERSION||'';
  script.src=`assets/js/voucher-theme-integration.js${version?`?v=${encodeURIComponent(version)}`:''}`;
  document.head.appendChild(script);
})();

(()=>{
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!path.endsWith('/voucher.html'))return;
  if(document.getElementById('publicVoucherCardUiScript'))return;
  const script=document.createElement('script');
  script.id='publicVoucherCardUiScript';
  const version=window.EVOLUTION_ASSET_VERSION||'';
  script.src=`assets/js/public-voucher-card-ui.js${version?`?v=${encodeURIComponent(version)}`:''}`;
  document.head.appendChild(script);
})();

// Partner Staff lifecycle hotfix.
// partner.html renders Staff action buttons dynamically. Keep all privileged
// mutations behind the existing manage-partner-staff Edge Function and resolve
// the canonical partner_users.staff_id before sending an action.
(()=>{
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!path.endsWith('/partner.html')||window.__evoPartnerStaffLifecycleInstalled)return;
  window.__evoPartnerStaffLifecycleInstalled=true;

  const cfg=window.EVOLUTION_VOUCHER_BACKEND||{};
  if(!window.supabase?.createClient||!cfg.supabaseUrl||!cfg.publishableKey)return;
  const db=window.supabase.createClient(cfg.supabaseUrl,cfg.publishableKey);
  const staffMsg=()=>document.getElementById('staffMsg');
  const show=(text,ok=false)=>{
    const node=staffMsg();
    if(!node)return;
    node.innerHTML=text?`<div class="msg ${ok?'ok':'err'}"></div>`:'';
    const box=node.firstElementChild;
    if(box)box.textContent=String(text||'');
  };
  const partnerId=()=>String(document.getElementById('adminPartnerSelect')?.value||'').trim();
  const partnerArgs=()=>partnerId()?{p_partner_id:partnerId()}:{};
  const partnerBody=payload=>partnerId()?{...payload,partner_id:partnerId()}:payload;

  async function invokeStaff(payload){
    const {data,error}=await db.functions.invoke('manage-partner-staff',{body:partnerBody(payload)});
    if(error){
      let details='';
      try{details=(await error.context?.json?.())?.details||'';}catch(_){}
      throw new Error(details||error.message||'Partner Staff action failed.');
    }
    if(!data?.success)throw new Error(data?.details||data?.error||'Partner Staff action failed.');
    return data;
  }
  // partner.html also calls invokeStaff() for Create Staff Account.
  window.invokeStaff=invokeStaff;

  async function resolveStaffId(userId){
    const {data,error}=await db.rpc('partner_staff_directory',partnerArgs());
    if(error)throw error;
    const row=(Array.isArray(data)?data:[]).find(r=>String(r.user_id||'')===String(userId||''));
    if(!row?.staff_id)throw new Error('Unable to resolve Staff account. Refresh and try again.');
    return row.staff_id;
  }

  document.addEventListener('click',async e=>{
    const btn=e.target?.closest?.('#staffDirectory [data-staff-action]');
    if(!btn||btn.disabled)return;
    e.preventDefault();
    e.stopPropagation();
    const action=String(btn.dataset.staffAction||'');
    const userId=String(btn.dataset.userId||'');
    if(!action||!userId)return;

    let payload=null;
    try{
      const staffId=await resolveStaffId(userId);
      if(action==='status'){
        const next=btn.dataset.nextStatus==='active'?'activate':'suspend';
        if(!confirm(`${next==='activate'?'Activate':'Deactivate'} this Staff account?`))return;
        payload={action:next,staff_id:staffId};
      }else if(action==='password'){
        const password=prompt('Enter a new password for this Staff account (minimum 6 characters):','');
        if(password===null)return;
        if(password.length<6){show('New password must be at least 6 characters.');return;}
        payload={action:'reset_password',staff_id:staffId,new_password:password};
      }else if(action==='delete'){
        if(!confirm('Delete this Staff account? This removes Staff access and signs out existing sessions.'))return;
        payload={action:'remove',staff_id:staffId};
      }else return;

      btn.disabled=true;
      show('');
      const result=await invokeStaff(payload);
      show(result?.message||'Partner Staff updated successfully.',true);
      setTimeout(()=>location.reload(),350);
    }catch(err){
      show(err?.message||'Partner Staff action failed.');
      btn.disabled=false;
    }
  },true);
})();
