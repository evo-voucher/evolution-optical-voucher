(()=>{
  const style=document.createElement('style');
  style.textContent=`
  .bback{display:inline-flex;align-items:center;text-decoration:none;color:#fff;border:1px solid rgba(115,135,210,.45);background:#0e1936;border-radius:11px;padding:9px 12px;font-size:12px;font-weight:800;margin-bottom:12px}
  .shell{max-width:760px}.card{border-radius:15px;padding:16px;box-shadow:none}.toprow{align-items:flex-start}.toprow h1{font-family:Inter,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;font-size:24px;letter-spacing:0}.toprow p{margin:4px 0 0;font-size:11px}
  #dashboardState>.card:nth-of-type(1),#dashboardState>.card:nth-of-type(2),#dashboardState>.card:nth-last-of-type(2),#dashboardState>.card:nth-last-of-type(1){display:none!important}
  .partner{position:relative;padding:14px}.partner .miniStats{grid-template-columns:repeat(3,minmax(0,1fr));gap:7px}.partner .miniStats .miniStat:nth-child(n+4){display:none!important}.partner .miniStat{padding:9px}.partner .miniStat b{font-size:18px}
  .partner .controls,.partner .claimbox,.partner .b-detail,.partner .b-stock,.partner .b-controls-toggle{display:none!important}
  .partner.b-open .b-stock,.partner.b-open .b-controls-toggle{display:block!important}
  .partner.b-open.b-controls-open .controls{display:grid!important}
  .partner.b-open.b-controls-open .claimbox,.partner.b-open.b-controls-open .b-detail{display:block!important}
  .b-manage,.b-controls-toggle{width:100%;margin-top:10px;min-height:44px;border-radius:12px}
  .partner.b-open .b-manage{border-color:rgba(101,230,181,.75);background:linear-gradient(180deg,#176158,#0d3a35)}
  .b-controls-toggle{border-color:rgba(111,147,255,.7)!important;background:linear-gradient(180deg,#3149a8,#172c72)!important}
  .partner.b-controls-open .b-controls-toggle{border-color:rgba(85,231,237,.8)!important;background:linear-gradient(180deg,#244b78,#123350)!important}
  .partner.b-controls-open .controls{margin-top:12px;padding-top:12px;border-top:1px solid rgba(115,135,210,.22)}
  #partnerControls{display:grid;grid-template-columns:1fr 1fr;gap:10px;align-items:start}#partnerControls .partner{margin-top:0}.partner.b-open{grid-column:1/-1}.partner.b-controls-open .controls{grid-template-columns:repeat(2,minmax(0,1fr))}.partner.b-controls-open .claimbox{margin-top:10px}.partnerhead .badge{white-space:nowrap}
  .b-stock{margin-top:12px;padding:12px;border:1px solid rgba(115,135,210,.28);border-radius:13px;background:#0a1635}.b-stock-title{font-weight:900;font-size:13px}.b-stock-sub{color:#91a2c4;font-size:10px;margin:4px 0 10px}.b-allocation{padding:10px 0;border-top:1px solid rgba(115,135,210,.2)}.b-allocation-grid{display:grid;grid-template-columns:1.4fr repeat(3,.7fr);gap:6px}.b-cell{padding:7px;border:1px solid rgba(115,135,210,.22);border-radius:9px}.b-cell span{display:block;color:#91a2c4;font-size:8px}.b-cell b{display:block;margin-top:2px;font-size:12px}.b-revoke-row{display:grid;grid-template-columns:90px 1fr auto;gap:7px;margin-top:8px}.b-revoke-row input{min-height:38px}.b-revoke{border-color:#a43b55!important;background:#451320!important;color:#ffdce3!important}.b-empty{color:#91a2c4;font-size:10px;padding:8px 0}
  input:not([type=checkbox]):not([type=radio]),select,textarea{background:#fff7a3!important;color:#24211b!important;border-color:#b9a85b!important}input::placeholder,textarea::placeholder{color:#746d53!important}
  @media(max-width:620px){body{padding:12px}.formgrid{grid-template-columns:1fr}.card{padding:14px}#partnerControls{grid-template-columns:1fr}.partner.b-open{grid-column:auto}.partner.b-controls-open .controls{grid-template-columns:1fr 1fr}.partner .miniStats{grid-template-columns:repeat(3,minmax(0,1fr))}}
  @media(max-width:420px){.partner.b-controls-open .controls{grid-template-columns:1fr}.partner .miniStat{padding:8px 6px}.partner .miniStat span{font-size:9px}.partner .miniStat b{font-size:17px}.b-allocation-grid{grid-template-columns:1fr 1fr}.b-revoke-row{grid-template-columns:1fr}.b-revoke-row button{width:100%}}
  `;
  document.head.appendChild(style);

  let allocationRows=null,stockDb=null;
  const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot',"'":'&#39;'}[c]));
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
    root.querySelectorAll('.partner').forEach(card=>{
      if(card.dataset.bAccordion==='1')return;card.dataset.bAccordion='1';
      const metrics=card.querySelector('.miniStats');
      if(metrics){const labels=metrics.querySelectorAll('.miniStat span');if(labels[0])labels[0].textContent='Limit';if(labels[1])labels[1].textContent='Issued';if(labels[2])labels[2].textContent='Available';let n=metrics.nextElementSibling;while(n&&!n.classList.contains('controls')&&!n.classList.contains('claimbox')){n.classList.add('b-detail');n=n.nextElementSibling;}}
      const manage=document.createElement('button');manage.type='button';manage.className='b-manage';manage.textContent='Manage';
      (metrics||card.querySelector('.partnerhead')||card).insertAdjacentElement('afterend',manage);
      const control=document.createElement('button');control.type='button';control.className='b-controls-toggle';control.textContent='Partner Controls';manage.insertAdjacentElement('afterend',control);
      control.addEventListener('click',()=>{const open=!card.classList.contains('b-controls-open');card.classList.toggle('b-controls-open',open);control.textContent=open?'Close Partner Controls':'Partner Controls';});
      manage.addEventListener('click',async()=>{
        const opening=!card.classList.contains('b-open');
        root.querySelectorAll('.partner.b-open').forEach(other=>{other.classList.remove('b-open','b-controls-open');const mb=other.querySelector('.b-manage'),cb=other.querySelector('.b-controls-toggle');if(mb)mb.textContent='Manage';if(cb)cb.textContent='Partner Controls';});
        if(opening){card.classList.add('b-open');manage.textContent='Close';await renderStock(card);card.scrollIntoView({behavior:'smooth',block:'start'});}else{card.classList.remove('b-open','b-controls-open');manage.textContent='Manage';control.textContent='Partner Controls';}
      });
    });
  };
  const boot=()=>{enhance();const root=document.getElementById('partnerControls');if(root)new MutationObserver(enhance).observe(root,{childList:true,subtree:true});else setTimeout(boot,120);};boot();
})();