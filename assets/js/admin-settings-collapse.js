(()=>{
  'use strict';
  const path=String(location.pathname||'').toLowerCase();
  if(!path.endsWith('/admin.html'))return;

  function makeCollapsible(card,buttonId,label){
    if(!card||document.getElementById(buttonId))return false;
    const children=[...card.children];
    const heading=children.find(el=>el.tagName==='H2');
    const body=document.createElement('div');
    body.className='hidden';
    body.dataset.collapsibleBody='1';
    const btn=document.createElement('button');
    btn.id=buttonId;btn.type='button';btn.className='wide';btn.textContent=label;
    if(heading)heading.insertAdjacentElement('afterend',btn);else card.prepend(btn);
    children.filter(el=>el!==heading).forEach(el=>body.appendChild(el));
    btn.insertAdjacentElement('afterend',body);
    btn.onclick=()=>{
      const isHidden=body.classList.toggle('hidden');
      btn.textContent=isHidden?label:`− Close ${label.replace(/^＋\s*/,'')}`;
    };
    return true;
  }

  function installAvailable(){
    const customer=document.getElementById('adminCustomerDatabaseCard');
    const district=document.getElementById('districtMasterCard');
    if(customer)makeCollapsible(customer,'openCustomerDatabaseBtn','＋ Customer Database');
    if(district)makeCollapsible(district,'openDistrictManagerBtn','＋ District Manager');
    return !!(document.getElementById('openCustomerDatabaseBtn')&&document.getElementById('openDistrictManagerBtn'));
  }

  function loadVoucherPdfExport(){
    if(document.getElementById('adminVoucherPdfExportScript'))return;
    const script=document.createElement('script');
    script.id='adminVoucherPdfExportScript';
    const version=encodeURIComponent(window.EVOLUTION_ASSET_VERSION||'20260820-01');
    script.src=`assets/js/admin-voucher-pdf-export.js?v=${version}`;
    document.head.appendChild(script);
  }

  installAvailable();
  loadVoucherPdfExport();
  let tries=0;
  const timer=setInterval(()=>{
    tries++;
    if(installAvailable()||tries>240)clearInterval(timer);
  },250);
})();