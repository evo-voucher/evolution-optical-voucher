(()=>{
  const style=document.createElement('style');
  style.textContent=`
    .b-status-stack{display:grid;grid-template-columns:1fr;gap:7px;margin-top:8px}
    .b-status-btn{width:100%;min-height:42px;border-radius:11px;font-weight:900}
    .b-status-btn.active{border-color:#39d6df!important;background:linear-gradient(180deg,#0f5963,#0a3940)!important;color:#bffcff!important}
    .b-status-btn.suspended{border-color:#ff6b7d!important;background:linear-gradient(180deg,#6b1f2b,#3c1119)!important;color:#ffd2d8!important}
    .b-status-btn.archived{border-color:#a877ff!important;background:linear-gradient(180deg,#4b2b79,#2c1849)!important;color:#eadcff!important}
    .b-status-btn.is-current{box-shadow:0 0 0 2px rgba(255,255,255,.18) inset,0 0 12px rgba(255,255,255,.10)}
    .badge.b-active{border-color:#39d6df!important;color:#7ef5ff!important;background:#0c343a!important}
    .badge.b-suspended{border-color:#ff6b7d!important;color:#ff9aa8!important;background:#3a1018!important}
    .badge.b-archived{border-color:#a877ff!important;color:#c9a9ff!important;background:#281742!important}
  `;
  document.head.appendChild(style);

  function enhanceCard(card){
    const select=card.querySelector('select[id^="st-"]');
    if(!select)return;
    const field=select.closest('.field');
    if(!field||field.dataset.bStatusButtons==='1')return;
    field.dataset.bStatusButtons='1';
    const id=select.id.slice(3);
    const current=String(select.value||'').toLowerCase();
    field.innerHTML='<label>Status</label><div class="b-status-stack">'
      +'<button type="button" class="b-status-btn active '+(current==='active'?'is-current':'')+'" data-status="active">Active</button>'
      +'<button type="button" class="b-status-btn suspended '+(current==='suspended'?'is-current':'')+'" data-status="suspended">Suspend</button>'
      +'<button type="button" class="b-status-btn archived '+(current==='archived'?'is-current':'')+'" data-status="archived">Archive</button>'
      +'</div>';
    field.querySelectorAll('.b-status-btn').forEach(btn=>{
      btn.addEventListener('click',()=>{
        const status=btn.dataset.status;
        if(status===current)return;
        window.setStatus(id,status);
      });
    });
  }

  function enhanceBadges(root){
    root.querySelectorAll('.partner').forEach(card=>{
      const badge=card.querySelector('.partnerhead .badge');
      if(!badge)return;
      const s=String(badge.textContent||'').trim().toLowerCase();
      badge.classList.remove('b-active','b-suspended','b-archived');
      if(s==='active')badge.classList.add('b-active');
      else if(s==='suspended')badge.classList.add('b-suspended');
      else if(s==='archived')badge.classList.add('b-archived');
      enhanceCard(card);
    });
  }

  function boot(){
    const root=document.getElementById('partnerControls');
    if(!root){setTimeout(boot,120);return;}
    enhanceBadges(root);
    new MutationObserver(()=>enhanceBadges(root)).observe(root,{childList:true,subtree:true});
  }
  boot();
})();