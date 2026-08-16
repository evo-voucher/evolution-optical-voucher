(()=>{
  function installStyle(){
    if(document.getElementById('partnerSetupCollapseStyle'))return;
    const s=document.createElement('style');
    s.id='partnerSetupCollapseStyle';
    s.textContent=`
      .partner-setup-details{grid-column:1/-1;border:1px solid rgba(118,91,255,.5);border-radius:16px;background:#0a1736;overflow:hidden}
      .partner-setup-details>summary{list-style:none;cursor:pointer;padding:14px 16px;font-weight:800;color:#e9efff;display:flex;align-items:center;justify-content:space-between;gap:12px}
      .partner-setup-details>summary::-webkit-details-marker{display:none}
      .partner-setup-details>summary::after{content:'›';font-size:24px;line-height:1;color:#8feaff;transform:rotate(90deg);transition:transform .18s ease}
      .partner-setup-details[open]>summary::after{transform:rotate(-90deg)}
      .partner-setup-details-body{padding:0 14px 14px}
      .partner-setup-details .initial-voucher-field,.partner-setup-details .initial-branch-field{grid-column:1/-1}
      @media(max-width:780px){.partner-setup-details{grid-column:auto}.partner-setup-details>summary{padding:13px 14px}.partner-setup-details-body{padding:0 10px 10px}}
    `;
    document.head.appendChild(s);
  }

  function mount(){
    const setup=document.getElementById('initialVoucherSetup');
    if(!setup||setup.dataset.collapseReady==='1')return false;
    setup.dataset.collapseReady='1';
    installStyle();

    const details=document.createElement('details');
    details.className='partner-setup-details';
    details.id='partnerVoucherClaimSetup';
    details.innerHTML='<summary>Voucher & Claim Setup</summary><div class="partner-setup-details-body"></div>';

    const body=details.querySelector('.partner-setup-details-body');
    const parent=setup.parentNode;
    parent.insertBefore(details,setup);

    while(setup.firstChild)body.appendChild(setup.firstChild);
    setup.remove();
    return true;
  }

  const start=()=>{
    if(mount())return;
    const mo=new MutationObserver(()=>{if(mount())mo.disconnect();});
    mo.observe(document.documentElement,{childList:true,subtree:true});
  };
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();
