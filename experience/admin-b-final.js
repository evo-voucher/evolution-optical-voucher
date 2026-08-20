(()=>{
  const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const buildCards=(tableId,containerId,kind)=>{
    const wrap=document.getElementById(tableId);if(!wrap)return;
    let cards=document.getElementById(containerId);
    if(!cards){cards=document.createElement('div');cards.id=containerId;cards.className='mobileReportCards';wrap.insertAdjacentElement('afterend',cards);}
    const table=wrap.querySelector('table');
    if(!table){cards.innerHTML='<div class="readonly">No records.</div>';return;}
    const heads=[...table.querySelectorAll('thead th')].map(x=>x.textContent.trim());
    const rows=[...table.querySelectorAll('tbody tr')];
    cards.innerHTML=rows.map((tr,i)=>{
      const vals=[...tr.querySelectorAll('td')].map(x=>x.textContent.trim());
      const title=vals[0]||'Record';
      const sub=kind==='voucher'?[vals[1],vals[2],vals[4]].filter(Boolean).join(' · '):[vals[1],vals[2],vals[4]].filter(Boolean).join(' · ');
      const detail=heads.map((h,j)=>'<div class="reportDetailRow"><b>'+esc(h)+'</b><span>'+esc(vals[j]||'—')+'</span></div>').join('');
      return '<div class="reportItem" data-report-item="'+i+'"><button type="button" class="reportCardBtn"><div class="rmain"><div class="rtitle">'+esc(title)+'</div><div class="rsub">'+esc(sub)+'</div></div><div class="rarrow">›</div></button><div class="reportDetail">'+detail+'</div></div>';
    }).join('');
    cards.querySelectorAll('.reportCardBtn').forEach(btn=>btn.addEventListener('click',()=>{
      const item=btn.closest('.reportItem');
      cards.querySelectorAll('.reportItem.open').forEach(x=>{if(x!==item)x.classList.remove('open')});
      item.classList.toggle('open');
    }));
  };
  const refresh=()=>{buildCards('voucherTable','voucherMobileCards','voucher');buildCards('redemptionTable','redemptionMobileCards','redemption')};
  const boot=()=>{
    refresh();
    ['voucherTable','redemptionTable'].forEach(id=>{const n=document.getElementById(id);if(n)new MutationObserver(refresh).observe(n,{childList:true,subtree:true})});
    if(!document.getElementById('voucherTable')||!document.getElementById('redemptionTable'))setTimeout(boot,150);
  };
  boot();
})();