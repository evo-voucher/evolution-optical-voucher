(()=>{
  const style=document.createElement('style');
  style.textContent=`
  .bback{display:inline-flex;align-items:center;text-decoration:none;color:#fff;border:1px solid rgba(115,135,210,.45);background:#0e1936;border-radius:11px;padding:9px 12px;font-size:12px;font-weight:800;margin-bottom:12px}
  .shell{max-width:760px}.card{border-radius:15px;padding:16px;box-shadow:none}.toprow{align-items:flex-start}.toprow h1{font-family:Inter,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;font-size:24px;letter-spacing:0}.toprow p{margin:4px 0 0;font-size:11px}
  #dashboardState>.card:nth-of-type(1),#dashboardState>.card:nth-of-type(2),#dashboardState>.card:nth-last-of-type(2),#dashboardState>.card:nth-last-of-type(1){display:none!important}
  .partner{position:relative;padding:14px}.partner .miniStats{grid-template-columns:repeat(3,minmax(0,1fr));gap:7px}.partner .miniStats .miniStat:nth-child(n+4){display:none!important}.partner .miniStat{padding:9px}.partner .miniStat b{font-size:18px}
  .partner .controls,.partner .claimbox,.partner .b-detail,.partner .b-stock{display:none!important}
  .partner.b-open .controls{display:grid!important}.partner.b-open .claimbox,.partner.b-open .b-detail,.partner.b-open .b-stock{display:block!important}
  .b-manage{width:100%;margin-top:10px;min-height:44px;border-radius:12px}.partner.b-open .b-manage{border-color:rgba(101,230,181,.75);background:linear-gradient(180deg,#176158,#0d3a35)}
  .partner.b-open .controls{margin-top:12px;padding-top:12px;border-top:1px solid rgba(115,135,210,.22);grid-template-columns:repeat(2,minmax(0,1fr))!important;gap:12px 14px!important;align-items:start}
  .partner.b-open .controls>*{min-width:0!important;width:100%!important;margin:0!important}
  .partner.b-open .controls label{display:block;min-height:25px;margin:0 0 7px!important;line-height:1.2}
  .partner.b-open .controls input:not([type=checkbox]):not([type=radio]),.partner.b-open .controls select{width:100%!important;min-height:58px!important;height:58px!important;margin:0!important}
  .partner.b-open .controls button{width:100%!important;min-height:52px!important;height:52px!important;margin:0!important;align-self:end}
  .partner.b-open .controls .miniStat,.partner.b-open .controls .stat{width:100%!important;min-height:58px!important;margin:0!important;display:flex!important;flex-direction:column;justify-content:center}
  #partnerControls{display:grid;grid-template-columns:1fr 1fr;gap:10px;align-items:start}#partnerControls .partner{margin-top:0}.partner.b-open{grid-column:1/-1}.partner.b-open .claimbox{margin-top:12px;width:100%}.partner.b-open .claimbox button{min-height:52px}.partnerhead .badge{white-space:nowrap}
  .b-partner-list-body{display:none}.b-partner-section.b-list-open .b-partner-list-body{display:block}.b-partner-list-toggle{width:100%;min-height:52px;border-radius:14px;font-size:16px;font-weight:900}.b-partner-section.b-list-open .b-partner-list-toggle{border-color:rgba(101,230,181,.75);background:linear-gradient(180deg,#176158,#0d3a35)}
  .b-stock{margin-top:12px;padding:12px;border:1px solid rgba(115,135,210,.28);border-radius:13px;background:#0a1635}.b-stock-title{font-weight:900;font-size:13px}.b-stock-sub{color:#91a2c4;font-size:10px;margin:4px 0 10px}.b-allocation{padding:10px 0;border-top:1px solid rgba(115,135,210,.2)}.b-allocation-grid{display:grid;grid-template-columns:1.4fr repeat(3,.7fr);gap:6px}.b-cell{padding:7px;border:1px solid rgba(115,135,210,.22);border-radius:9px}.b-cell span{display:block;color:#91a2c4;font-size:8px}.b-cell b{display:block;margin-top:2px;font-size:12px}.b-revoke-row{display:grid;grid-template-columns:90px 1fr auto;gap:7px;margin-top:8px}.b-revoke-row input{min-height:38px}.b-revoke{border-color:#a43b55!important;background:#451320!important;color:#ffdce3!important}.b-empty{color:#91a2c4;font-size:10px;padding:8px 0}
  input:not([type=checkbox]):not([type=radio]),select,textarea{background:#fff7a3!important;color:#24211b!important;border-color:#b9a85b!important}input::placeholder,textarea::placeholder{color:#746d53!important}
  @media(max-width:620px){body{padding:12px}.formgrid{grid-template-columns:1fr}.card{padding:14px}#partnerControls{grid-template-columns:1fr}.partner.b-open{grid-column:auto}.partner.b-open .controls{grid-template-columns:repeat(2,minmax(0,1fr))!important}.partner .miniStats{grid-template-columns:repeat(3,minmax(0,1fr))}}
  @media(max-width:420px){.partner.b-open .controls{grid-template-columns:repeat(2,minmax(0,1fr))!important;gap:10px!important}.partner.b-open .controls label{font-size:12px}.partner.b-open .controls input:not([type=checkbox]):not([type=radio]),.partner.b-open .controls select{min-height:54px!important;height:54px!important}.partner.b-open .controls button{min-height:50px!important;height:50px!important;font-size:12px!important}.partner .miniStat{padding:8px 6px}.partner .miniStat span{font-size:9px}.partner .miniStat b{font-size:17px}.b-allocation-grid{grid-template-columns:1fr 1fr}.b-revoke-row{grid-template-columns:1fr}.b-revoke-row button{width:100%}}
  `;
  document.head.appendChild(style);

  let allocationRows=null,stockDb=null;
  const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const partnerCodeOf=card=>{const t=(card.querySelector('.partnerhead')?.textContent||'').trim();const m=t.match(/\b([A-Z0-9_-]{2,})\b/i);return m?m[1].toUpperCase():'';};
  async function loadAllocations(){
    if(allocationRows)return allocationRows;
    const cfg=window.EVOLUTION_VOUCHER_BACKEND||{};
    if(!(cfg.enabled&&cfg.supabaseUrl&&cfg.publishableKey&&window.supabase))throw new Error('Backend unavailable');
    stockDb=stockDb||window.supabase.createClient(cfg.supabaseUrl,cfg.publishableKey);
    const{data,error}=await stockDb.rpc('admin_active_voucher_allocations');if(error)throw error;
    allocationRows=data||[];return allocationRows;
  }
  async function renderStock(card){
    let box=card.querySelector('.b-stock');
    if(!box){box=document.createElement('div');box.className='b-stock';card.appendChild(box);}
    box.innerHTML='<div class="b-stock-title">Allocated Voucher Stock</div><div class="b-stock-sub">Revoke only unissued stock. Issued customer vouchers are not changed.</div><div class="b-empty">Loading…</div>';
    try{
      const code=partnerCodeOf(card);const rows=(await loadAllocations()).filter(x=>String(x.partner_code||'').toUpperCase()===code);
      if(!rows.length){box.innerHTML='<div class="b-stock-title">Allocated Voucher Stock</div><div class="b-stock-sub">Revoke only unissued stock.</div><div class="b-empty">No active allocations.</div>';return;}
      box.innerHTML='<div class="b-stock-title">Allocated Voucher Stock</div><div class="b-stock-sub">Revoke only unissued stock. Issued customer vouchers are not changed.</div>'+rows.map(r=>{const rem=Number(r.remaining_unissued||0);return '<div class="b-allocation" data-allocation="'+esc(r.allocation_id)+'"><div class="b-allocation-grid"><div class="b-cell"><span>Voucher Version</span><b>'+esc(r.version_name||r.version_id)+'</b></div><div class="b-cell"><span>Allocated</span><b>'+Number(r.quantity_allocated||0)+'</b></div><div class="b-cell"><span>Issued</span><b>'+Number(r.issued_count||0)+'</b></div><div class="b-cell"><span>Unissued</span><b>'+rem+'</b></div></div>'+(rem>0?'<div class="b-revoke-row"><input class="b-qty" type="number" min="1" max="'+rem+'" placeholder="Qty"><input class="b-reason" placeholder="Reason"><button type="button" class="b-revoke">Revoke</button></div>':'<div class="b-empty">No unissued stock to revoke.</div>')+'</div>';}).join('');
      box.querySelectorAll('.b-revoke').forEach(btn=>btn.onclick=async()=>{
        const row=btn.closest('.b-allocation'),qtyInput=row.querySelector('.b-qty'),qty=Number(qtyInput.value),max=Number(qtyInput.max),reason=row.querySelector('.b-reason').value.trim();
        if(!Number.isInteger(qty)||qty<1||qty>max){alert('Enter a quantity from 1 to '+max+'.');return;}if(!reason){alert('Revoke reason is required.');return;}if(!confirm('Revoke '+qty+' unissued voucher(s)?\n\nIssued customer vouchers will remain unchanged.'))return;
        btn.disabled=true;btn.textContent='Revoking…';
        try{const{error}=await stockDb.rpc('admin_engine_revoke_unissued',{p_allocation_id:row.dataset.allocation,p_quantity:qty,p_reason:reason,p_actor_user_id:null});if(error)throw error;allocationRows=null;await renderStock(card);alert('Unissued voucher stock revoked.');}catch(e){alert(String(e?.message||e));btn.disabled=false;btn.textContent='Revoke';}
      });
    }catch(e){box.innerHTML='<div class="b-stock-title">Allocated Voucher Stock</div><div class="b-empty">'+esc(e?.message||e)+'</div>';}
  }

  const enhance=()=>{
    const root=document.getElementById('partnerControls');if(!root)return;

    const section=root.closest('.card');
    if(section&&!section.dataset.bListToggle){
      section.dataset.bListToggle='1';section.classList.add('b-partner-section');
      const body=document.createElement('div');body.className='b-partner-list-body';
      const children=[...section.childNodes];
      children.forEach(node=>body.appendChild(node));
      const toggle=document.createElement('button');toggle.type='button';toggle.className='b-partner-list-toggle';toggle.textContent='Partner Controls';
      section.appendChild(toggle);section.appendChild(body);
      toggle.addEventListener('click',()=>{
        const open=!section.classList.contains('b-list-open');section.classList.toggle('b-list-open',open);toggle.textContent=open?'Close Partner Controls':'Partner Controls';
        if(!open){root.querySelectorAll('.partner.b-open').forEach(card=>{card.classList.remove('b-open');const mb=card.querySelector('.b-manage');if(mb)mb.textContent='Manage';});}
      });
    }

    root.querySelectorAll('.partner').forEach(card=>{
      if(card.dataset.bAccordion==='1')return;card.dataset.bAccordion='1';
      const metrics=card.querySelector('.miniStats');
      if(metrics){const labels=metrics.querySelectorAll('.miniStat span');if(labels[0])labels[0].textContent='Limit';if(labels[1])labels[1].textContent='Issued';if(labels[2])labels[2].textContent='Available';let n=metrics.nextElementSibling;while(n&&!n.classList.contains('controls')&&!n.classList.contains('claimbox')){n.classList.add('b-detail');n=n.nextElementSibling;}}
      const manage=document.createElement('button');manage.type='button';manage.className='b-manage';manage.textContent='Manage';
      (metrics||card.querySelector('.partnerhead')||card).insertAdjacentElement('afterend',manage);
      manage.addEventListener('click',async()=>{
        const opening=!card.classList.contains('b-open');
        root.querySelectorAll('.partner.b-open').forEach(other=>{other.classList.remove('b-open');const mb=other.querySelector('.b-manage');if(mb)mb.textContent='Manage';});
        if(opening){card.classList.add('b-open');manage.textContent='Close';await renderStock(card);card.scrollIntoView({behavior:'smooth',block:'start'});}else{card.classList.remove('b-open');manage.textContent='Manage';}
      });
    });
  };
  const boot=()=>{enhance();const root=document.getElementById('partnerControls');if(root)new MutationObserver(enhance).observe(root,{childList:true,subtree:true});else setTimeout(boot,120);};boot();
})();