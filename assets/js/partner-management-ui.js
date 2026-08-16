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
      #partnerControls{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;align-items:start}
      #partnerControls>.empty{grid-column:1/-1}
      #partnerControls .partner{padding:10px!important;margin-top:0!important;min-width:0}
      #partnerControls .partnerhead{gap:7px}
      #partnerControls .partnerhead b{font-size:14px}
      #partnerControls .partnerhead .small{font-size:10px!important;line-height:1.3}
      #partnerControls .partnerhead .badge{font-size:9px!important;padding:4px 6px!important}
      .partner-control-tabs{display:grid;grid-template-columns:1fr 1fr;gap:6px;margin-top:8px}
      .partner-control-tabs button{min-height:34px!important;padding:5px 7px!important;font-size:11px!important;border-radius:10px!important}
      .partner-control-tabs button.active{border-color:rgba(101,230,181,.82)!important;background:linear-gradient(180deg,#176158,#0d3a35)!important}
      .partner-control-panel-hidden{display:none!important}
      .partner-control-panel{margin-top:8px;padding-top:8px;border-top:1px solid rgba(115,135,210,.22)}
      .partner-inner-back{width:auto!important;min-height:32px!important;padding:5px 8px!important;margin:0 0 8px!important;font-size:11px!important;border-radius:9px!important}
      #partnerControls .partner .controls{margin-top:0!important;grid-template-columns:1fr!important}
      #partnerControls .partner .controls .wide{min-height:34px!important;margin-top:6px!important;padding:6px 8px!important;font-size:11px!important}
      #partnerControls .partner .controls input,#partnerControls .partner .controls select{min-height:38px!important;padding:8px 9px!important;font-size:12px!important}
      #partnerControls .partner .claimbox{margin-top:0!important;padding:8px!important}
      #partnerControls .partner .claimbox>button{min-height:34px!important;padding:6px 8px!important;font-size:11px!important;width:auto!important}
      #partnerControls .partner .branchgrid{grid-template-columns:1fr!important}
      @media(max-width:430px){#partnerControls{grid-template-columns:1fr}}
      @media(max-width:560px){
        .partner-subnav{grid-template-columns:1fr 1fr;gap:10px}
        .partner-subnav button{min-height:68px!important;padding:10px!important;font-size:13px!important}
        .partner-setup-details>summary{padding:13px 14px}
      }
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

  function closePartnerPanels(partner){
    partner.querySelectorAll('.partner-control-panel').forEach(p=>p.classList.add('partner-control-panel-hidden'));
    partner.querySelectorAll('.partner-control-tabs [data-control-view]').forEach(b=>b.classList.remove('active'));
  }

  function setPartnerControlView(partner,view){
    const panel=partner.querySelector(`.partner-control-panel[data-panel="${view}"]`);
    const button=partner.querySelector(`.partner-control-tabs [data-control-view="${view}"]`);
    const sameOpen=!!button?.classList.contains('active');
    closePartnerPanels(partner);
    if(sameOpen)return;
    panel?.classList.remove('partner-control-panel-hidden');
    button?.classList.add('active');
  }

  function buildPanel(kind,node){
    const panel=document.createElement('div');
    panel.className='partner-control-panel partner-control-panel-hidden';
    panel.dataset.panel=kind;
    const back=document.createElement('button');
    back.type='button';
    back.className='partner-inner-back';
    back.textContent='← Back';
    back.addEventListener('click',()=>closePartnerPanels(panel.closest('.partner')));
    panel.appendChild(back);
    panel.appendChild(node);
    return panel;
  }

  function compactPartnerCard(partner){
    if(!partner||partner.dataset.compactControlsReady==='1')return;
    const head=partner.querySelector('.partnerhead');
    const basic=partner.querySelector('.controls');
    const access=partner.querySelector('.claimbox');
    if(!head||!basic||!access)return;

    partner.dataset.compactControlsReady='1';
    const tabs=document.createElement('div');
    tabs.className='partner-control-tabs';
    tabs.innerHTML='<button type="button" data-control-view="basic">Basic</button><button type="button" data-control-view="access">Access</button>';
    tabs.addEventListener('click',e=>{
      const btn=e.target.closest('[data-control-view]');
      if(btn)setPartnerControlView(partner,btn.dataset.controlView);
    });
    head.insertAdjacentElement('afterend',tabs);
    const basicPanel=buildPanel('basic',basic);
    const accessPanel=buildPanel('access',access);
    tabs.insertAdjacentElement('afterend',accessPanel);
    tabs.insertAdjacentElement('afterend',basicPanel);
  }

  function compactPartnerControls(controlsCard){
    controlsCard?.querySelectorAll('#partnerControls .partner').forEach(compactPartnerCard);
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

  function launcher(){return document.getElementById('partnerSubnavCard');}

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
    if(which==='controls')compactPartnerControls(controlsCard);
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
    compactPartnerControls(controlsCard);

    const partnerRoot=controlsCard.querySelector('#partnerControls');
    if(partnerRoot&&!partnerRoot.dataset.compactObserverReady){
      partnerRoot.dataset.compactObserverReady='1';
      const po=new MutationObserver(()=>compactPartnerControls(controlsCard));
      po.observe(partnerRoot,{childList:true});
    }

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
