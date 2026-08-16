(()=>{
  const CARD_SELECTOR='#dashboardState > .card';

  function cardByTitle(title){
    return [...document.querySelectorAll(CARD_SELECTOR)].find(card=>(card.querySelector('h2')?.textContent||'').trim()===title)||null;
  }

  function installStyle(){
    if(document.getElementById('partnerManagementUiStyle'))return;
    const s=document.createElement('style');
    s.id='partnerManagementUiStyle';
    s.textContent=`
      .partner-subnav{display:grid;grid-template-columns:1fr 1fr;gap:12px}
      .partner-subnav button{min-height:76px!important;padding:14px!important;font-weight:800!important}
      .partner-sub-hidden{display:none!important}
      .partner-sub-return{width:auto!important;min-width:96px!important;min-height:40px!important;padding:8px 12px!important;margin:0 0 12px!important}
      .partner-setup-details{border:1px solid rgba(118,91,255,.5);border-radius:16px;background:#0a1736;overflow:hidden}
      .partner-setup-details>summary{list-style:none;cursor:pointer;padding:14px 16px;font-weight:800;color:#e9efff;display:flex;align-items:center;justify-content:space-between;gap:12px}
      .partner-setup-details>summary::-webkit-details-marker{display:none}
      .partner-setup-details>summary::after{content:'›';font-size:24px;line-height:1;color:#8feaff;transform:rotate(90deg);transition:transform .18s ease}
      .partner-setup-details[open]>summary::after{transform:rotate(-90deg)}
      .partner-setup-details-body{padding:0 12px 12px}
      @media(max-width:560px){.partner-subnav{grid-template-columns:1fr 1fr;gap:10px}.partner-subnav button{min-height:68px!important;padding:10px!important;font-size:13px!important}.partner-setup-details>summary{padding:13px 14px}}
    `;
    document.head.appendChild(s);
  }

  function ensureVoucherCollapse(createCard){
    const setup=createCard?.querySelector('#initialVoucherSetup');
    if(!setup||setup.dataset.partnerUiCollapsed==='1')return;
    setup.dataset.partnerUiCollapsed='1';

    const details=document.createElement('details');
    details.className='partner-setup-details';
    details.innerHTML='<summary>Voucher & Claim Setup</summary><div class="partner-setup-details-body"></div>';
    const body=details.querySelector('.partner-setup-details-body');
    while(setup.firstChild)body.appendChild(setup.firstChild);
    setup.appendChild(details);
  }

  function ensureReturn(card){
    if(!card||card.querySelector('.partner-sub-return'))return;
    const btn=document.createElement('button');
    btn.type='button';
    btn.className='partner-sub-return';
    btn.textContent='← Return';
    btn.addEventListener('click',()=>showMenu());
    const h=card.querySelector('h2');
    if(h)card.insertBefore(btn,h);else card.prepend(btn);
  }

  function launcher(){
    return document.getElementById('partnerSubnavCard');
  }

  function showMenu(){
    const createCard=cardByTitle('Create Partner');
    const controlsCard=cardByTitle('Partner Controls');
    createCard?.classList.add('partner-sub-hidden');
    controlsCard?.classList.add('partner-sub-hidden');
    launcher()?.classList.remove('partner-sub-hidden');
    window.scrollTo({top:0,behavior:'smooth'});
  }

  function showSubview(which){
    const createCard=cardByTitle('Create Partner');
    const controlsCard=cardByTitle('Partner Controls');
    launcher()?.classList.add('partner-sub-hidden');
    createCard?.classList.toggle('partner-sub-hidden',which!=='add');
    controlsCard?.classList.toggle('partner-sub-hidden',which!=='controls');
    const target=which==='add'?createCard:controlsCard;
    target?.scrollIntoView({behavior:'smooth',block:'start'});
  }

  function ensureLauncher(createCard,controlsCard){
    if(document.getElementById('partnerSubnavCard'))return;
    const card=document.createElement('section');
    card.id='partnerSubnavCard';
    card.className='card';
    card.dataset.adminSection='partners';
    card.innerHTML=`<h2>Partner Management</h2><div class="partner-subnav"><button type="button" data-partner-view="add">＋ Add Partner</button><button type="button" data-partner-view="controls">⚙ Partner Controls</button></div>`;
    card.addEventListener('click',e=>{
      const btn=e.target.closest('[data-partner-view]');
      if(btn)showSubview(btn.dataset.partnerView);
    });
    const first=createCard||controlsCard;
    first?.parentNode?.insertBefore(card,first);
  }

  function mount(){
    const createCard=cardByTitle('Create Partner');
    const controlsCard=cardByTitle('Partner Controls');
    if(!createCard||!controlsCard)return false;

    installStyle();
    ensureLauncher(createCard,controlsCard);
    ensureReturn(createCard);
    ensureReturn(controlsCard);
    ensureVoucherCollapse(createCard);

    if(!document.body.dataset.partnerSubnavReady){
      document.body.dataset.partnerSubnavReady='1';
      showMenu();
      const bodyObserver=new MutationObserver(muts=>{
        if(muts.some(m=>m.type==='attributes'&&m.attributeName==='data-admin-section')&&document.body.dataset.adminSection==='partners')showMenu();
      });
      bodyObserver.observe(document.body,{attributes:true,attributeFilter:['data-admin-section']});
    }
    return true;
  }

  const start=()=>{
    if(mount()){
      const createCard=cardByTitle('Create Partner');
      const mo=new MutationObserver(()=>ensureVoucherCollapse(createCard));
      mo.observe(createCard,{childList:true,subtree:true});
      return;
    }
    const mo=new MutationObserver(()=>{if(mount())mo.disconnect();});
    mo.observe(document.documentElement,{childList:true,subtree:true});
  };

  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();
