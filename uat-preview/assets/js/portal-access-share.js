(()=>{
  const cfg=window.EVOLUTION_VOUCHER_BACKEND||{};
  const siteBase=String(cfg.siteBase||'').replace(/\/?$/,'/');
  if(!siteBase)return;
  const portalUrl=`${siteBase}partner.html`;
  const path=String(window.location?.pathname||'').toLowerCase();
  const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

  function ensureStyle(){
    if(document.getElementById('portalAccessShareStyle'))return;
    const style=document.createElement('style');
    style.id='portalAccessShareStyle';
    style.textContent=`.portal-share-box{margin-top:12px;padding:12px;border:1px solid rgba(101,230,181,.42);border-radius:14px;background:#0d2438}.portal-share-box b{display:block;color:#e9fff7}.portal-share-meta{margin-top:5px;color:#a9bddc;font-size:11px;line-height:1.45;word-break:break-word}.portal-share-actions{display:flex;gap:8px;flex-wrap:wrap;margin-top:10px}.portal-share-actions button{min-height:40px;padding:8px 12px}.portal-share-copy-ok{margin-top:7px;color:#65e6b5;font-size:11px}@media(max-width:560px){.portal-share-actions button{flex:1}}`;
    document.head.appendChild(style);
  }

  function shareText(role,name,email){
    return [`Evolution Optical ${role} Portal`,name?`Account: ${name}`:'',email?`Login Email: ${email}`:'',`Login: ${portalUrl}`].filter(Boolean).join('\n');
  }

  async function shareAccess(role,name,email){
    const text=shareText(role,name,email);
    if(navigator.share){
      try{await navigator.share({title:`Evolution Optical ${role} Portal`,text,url:portalUrl});return}catch(e){if(e?.name==='AbortError')return}
    }
    window.open(`https://wa.me/?text=${encodeURIComponent(text)}`,'_blank','noopener');
  }

  async function copyLink(statusNode){
    try{
      await navigator.clipboard.writeText(portalUrl);
      if(statusNode){statusNode.textContent='Link copied ✓';setTimeout(()=>{if(statusNode.isConnected)statusNode.textContent=''},1800)}
    }catch(_){
      const ta=document.createElement('textarea');ta.value=portalUrl;ta.style.position='fixed';ta.style.opacity='0';document.body.appendChild(ta);ta.select();document.execCommand('copy');ta.remove();
      if(statusNode){statusNode.textContent='Link copied ✓';setTimeout(()=>{if(statusNode.isConnected)statusNode.textContent=''},1800)}
    }
  }

  function renderShare(target,{role,name,email,id}){
    if(!target)return;
    ensureStyle();
    target.querySelector(`#${id}`)?.remove();
    const box=document.createElement('div');box.id=id;box.className='portal-share-box';
    box.innerHTML=`<b>Share ${esc(role)} Login</b><div class="portal-share-meta">${name?`${esc(name)}<br>`:''}${email?`${esc(email)}<br>`:''}${esc(portalUrl)}</div><div class="portal-share-actions"><button type="button" data-share>Share Link</button><button type="button" data-copy>Copy Link</button></div><div class="portal-share-copy-ok"></div>`;
    box.querySelector('[data-share]').onclick=()=>shareAccess(role,name,email);
    box.querySelector('[data-copy]').onclick=()=>copyLink(box.querySelector('.portal-share-copy-ok'));
    target.appendChild(box);
  }

  function installAdminShare(){
    const btn=document.getElementById('createPartnerBtn'),out=document.getElementById('createPartnerMsg');
    if(!btn||!out)return;
    const pendingKey='evo_pending_partner_access_share',readyKey='evo_ready_partner_access_share';
    try{
      const ready=JSON.parse(sessionStorage.getItem(readyKey)||'null');
      if(ready?.email)renderShare(out,{role:'Partner',name:ready.name||'',email:ready.email,id:'partnerAccessShare'});
    }catch(_){ }
    btn.addEventListener('click',()=>{
      const name=(document.getElementById('newPartnerName')?.value||'').trim();
      const email=(document.getElementById('newPartnerEmail')?.value||'').trim().toLowerCase();
      try{sessionStorage.removeItem(readyKey);sessionStorage.setItem(pendingKey,JSON.stringify({name,email}))}catch(_){ }
      document.getElementById('partnerAccessShare')?.remove();
    },true);
    const observer=new MutationObserver(()=>{
      const ok=out.querySelector('.msg.ok');
      if(!ok)return;
      let pending=null;try{pending=JSON.parse(sessionStorage.getItem(pendingKey)||'null')}catch(_){ }
      if(!pending?.email)return;
      try{sessionStorage.setItem(readyKey,JSON.stringify(pending));sessionStorage.removeItem(pendingKey)}catch(_){ }
      renderShare(out,{role:'Partner',name:pending.name||'',email:pending.email,id:'partnerAccessShare'});
    });
    observer.observe(out,{childList:true,subtree:true});
  }

  function installPartnerStaffShare(){
    const btn=document.getElementById('createStaffBtn'),out=document.getElementById('staffMsg');
    if(!btn||!out)return;
    let pending=null;
    btn.addEventListener('click',()=>{
      pending={name:(document.getElementById('staffName')?.value||'').trim(),email:(document.getElementById('staffEmail')?.value||'').trim().toLowerCase()};
      document.getElementById('staffAccessShare')?.remove();
    },true);
    const observer=new MutationObserver(()=>{
      const ok=out.querySelector('.msg.ok');
      if(!ok||!pending?.email||!ok.textContent.includes('Partner Staff account created'))return;
      renderShare(out,{role:'Partner Staff',name:pending.name||'',email:pending.email,id:'staffAccessShare'});
      pending=null;
    });
    observer.observe(out,{childList:true,subtree:true});
  }

  function mount(){
    if(path.endsWith('/admin.html'))installAdminShare();
    if(path.endsWith('/partner.html'))installPartnerStaffShare();
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',mount,{once:true});else mount();
})();