(()=>{
  const CARD_SELECTOR='#dashboardState > .card';

  function cardByTitle(title){
    return [...document.querySelectorAll(CARD_SELECTOR)].find(card=>(card.querySelector('h2')?.textContent||'').trim()===title)||null;
  }

  function preserveViewport(change){
    const x=window.scrollX||0;
    const y=window.scrollY||0;
    change();
    const restore=()=>window.scrollTo({left:x,top:y,behavior:'auto'});
    restore();
    requestAnimationFrame(()=>{
      restore();
      requestAnimationFrame(restore);
    });
  }

  function installStyle(){
    if(document.getElementById('partnerManagementUiStyle'))return;
    const s=document.createElement('style');
    s.id='partnerManagementUiStyle';
    s.textContent=`
      #partnerSubnavCard,#partnerControls,#partnerDirectory{overflow-anchor:none}
      .partner-subnav{display:grid;grid-template-columns:1fr 1fr;gap:12px}
      .partner-subnav button{min-height:76px!important;padding:14px!important;font-weight:800!important;transform:none!important;transition:filter .08s ease,box-shadow .08s ease!important}
      .partner-subnav button:active{transform:none!important;filter:brightness(.88);box-shadow:inset 0 4px 12px rgba(0,0,0,.34),0 8px 16px rgba(0,0,0,.22)!important}
      .partner-sub-hidden{display:none!important}
      .partner-sub-return{width:auto!important;min-width:96px!important;min-height:40px!important;padding:8px 12px!important;margin:0 0 12px!important}
      .partner-setup-details{border:1px solid rgba(118,91,255,.5);border-radius:16px;background:#0a1736;overflow:hidden}
      .partner-setup-details>summary{list-style:none;cursor:pointer;padding:14px 16px;font-weight:800;color:#e9efff;display:flex;align-items:center;justify-content:space-between;gap:12px}
      .partner-setup-details>summary::-webkit-details-marker{display:none}
      .partner-setup-details>summary::after{content:'›';font-size:24px;line-height:1;color:#8feaff;transform:rotate(90deg);transition:transform .18s ease}
      .partner-setup-details[open]>summary::after{transform:rotate(-90deg)}
      .partner-setup-details-body{padding:0 12px 12px}

      .partner-directory{display:block;margin-top:10px}
      .partner-directory-group{margin:12px 0 16px}
      .partner-directory-letter{font-size:12px;font-weight:900;letter-spacing:.14em;color:#8feaff;margin:0 0 7px;padding:0 2px}
      .partner-directory-group.suspended-group{margin-top:22px;padding-top:14px;border-top:1px solid rgba(115,135,210,.22)}
      .partner-directory-group.suspended-group .partner-directory-letter{color:#ffb4c0;letter-spacing:.08em}
      .partner-directory-list{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}
      .partner-directory-name{min-height:40px!important;padding:8px 10px!important;font-size:12px!important;text-align:left!important;border-radius:11px!important;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
      .partner-directory-group.suspended-group .partner-directory-name{opacity:.78}
      .partner-directory-empty{padding:14px 4px;color:#91a2c4;font-size:12px}
      .partner-directory-hidden{display:none!important}

      #partnerControls.partner-directory-list-hidden{display:none!important}
      #partnerControls.partner-detail-mode{display:block!important}
      #partnerControls.partner-detail-mode>.partner{display:none!important}
      #partnerControls.partner-detail-mode>.partner.partner-detail-active{display:block!important}
      #partnerControls>.empty{grid-column:1/-1}
      #partnerControls .partner{padding:12px!important;margin-top:0!important;min-width:0}
      #partnerControls .partnerhead{gap:7px}
      #partnerControls .partnerhead b{font-size:15px}
      #partnerControls .partnerhead .small{font-size:10px!important;line-height:1.3}
      #partnerControls .partnerhead .badge{font-size:9px!important;padding:4px 6px!important}
      .partner-directory-back{width:auto!important;min-height:34px!important;padding:6px 9px!important;margin:0 0 10px!important;font-size:11px!important;border-radius:9px!important}
      .partner-status-actions{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:10px}
      .partner-status-actions button{min-height:36px!important;padding:6px 8px!important;font-size:11px!important;border-radius:10px!important}
      .partner-status-actions button.active-state{border-color:rgba(101,230,181,.82)!important;background:linear-gradient(180deg,#176158,#0d3a35)!important}
      .partner-status-actions button.suspended-state{border-color:rgba(255,146,165,.82)!important;background:linear-gradient(180deg,#6f3141,#4a1d2a)!important}
      .partner-control-tabs{display:grid;grid-template-columns:1fr 1fr;gap:6px;margin-top:8px}
      .partner-control-tabs button{min-height:36px!important;padding:6px 8px!important;font-size:11px!important;border-radius:10px!important}
      .partner-control-tabs button.active{border-color:rgba(101,230,181,.82)!important;background:linear-gradient(180deg,#176158,#0d3a35)!important}
      .partner-control-panel-hidden{display:none!important}
      .partner-control-panel{margin-top:8px;padding-top:8px;border-top:1px solid rgba(115,135,210,.22)}
      .partner-legacy-status-control{display:none!important}
      #partnerControls .partner .controls{margin-top:0!important;grid-template-columns:1fr!important}
      #partnerControls .partner .controls .wide{min-height:34px!important;margin-top:6px!important;padding:6px 8px!important;font-size:11px!important}
      #partnerControls .partner .controls input,#partnerControls .partner .controls select{min-height:38px!important;padding:8px 9px!important;font-size:12px!important}
      #partnerControls .partner .claimbox{margin-top:0!important;padding:8px!important}
      #partnerControls .partner .claimbox>button{min-height:34px!important;padding:6px 8px!important;font-size:11px!important;width:auto!important}
      #partnerControls .partner .branchgrid{grid-template-columns:1fr!important}

      @media(max-width:430px){.partner-directory-list{grid-template-columns:1fr}}
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
    preserveViewport(()=>{
      const panel=partner.querySelector(`.partner-control-panel[data-panel="${view}"]`);
      const button=partner.querySelector(`.partner-control-tabs [data-control-view="${view}"]`);
      closePartnerPanels(partner);
      panel?.classList.remove('partner-control-panel-hidden');
      button?.classList.add('active');
    });
  }

  function buildPanel(kind,node){
    const panel=document.createElement('div');
    panel.className='partner-control-panel partner-control-panel-hidden';
    panel.dataset.panel=kind;
    panel.appendChild(node);
    return panel;
  }

  function showPartnerDirectory(controlsCard){
    const root=controlsCard?.querySelector('#partnerControls');
    const dir=controlsCard?.querySelector('#partnerDirectory');
    if(!root||!dir)return;
    preserveViewport(()=>{
      root.classList.remove('partner-detail-mode');
      root.classList.add('partner-directory-list-hidden');
      root.querySelectorAll('.partner').forEach(p=>{p.classList.remove('partner-detail-active');closePartnerPanels(p);});
      dir.classList.remove('partner-directory-hidden');
    });
  }

  function showPartnerDetail(controlsCard,partner){
    const root=controlsCard?.querySelector('#partnerControls');
    const dir=controlsCard?.querySelector('#partnerDirectory');
    if(!root||!dir||!partner)return;
    preserveViewport(()=>{
      dir.classList.add('partner-directory-hidden');
      root.classList.remove('partner-directory-list-hidden');
      root.classList.add('partner-detail-mode');
      root.querySelectorAll('.partner').forEach(p=>p.classList.toggle('partner-detail-active',p===partner));
      closePartnerPanels(partner);
    });
  }

  function partnerStatus(partner){return (partner.querySelector('.partnerhead .badge')?.textContent||'').trim().toLowerCase();}
  function partnerId(partner){
    const statusSelect=partner.querySelector('select[id^="st-"]');
    return statusSelect?.id?.replace(/^st-/,'')||'';
  }

  function syncQuickStatus(partner){
    const status=partnerStatus(partner);
    partner.querySelectorAll('.partner-status-actions [data-partner-status]').forEach(btn=>{
      const target=btn.dataset.partnerStatus;
      btn.classList.toggle('active-state',target==='active'&&status==='active');
      btn.classList.toggle('suspended-state',target==='suspended'&&status==='suspended');
    });
  }

  function ensureQuickStatus(partner,head,basic){
    const statusField=[...basic.querySelectorAll('.field')].find(field=>(field.querySelector('label')?.textContent||'').trim()==='Status');
    statusField?.classList.add('partner-legacy-status-control');

    const actions=document.createElement('div');
    actions.className='partner-status-actions';
    actions.innerHTML='<button type="button" data-partner-status="active">Active</button><button type="button" data-partner-status="suspended">Suspend</button>';
    actions.addEventListener('click',e=>{
      const btn=e.target.closest('[data-partner-status]');
      if(!btn)return;
      const target=btn.dataset.partnerStatus;
      const id=partnerId(partner);
      if(!id||typeof window.setStatus!=='function')return;
      if(partnerStatus(partner)===target)return;
      window.setStatus(id,target);
    });
    head.insertAdjacentElement('afterend',actions);
    syncQuickStatus(partner);
    return actions;
  }

  function compactPartnerCard(partner,controlsCard){
    if(!partner||partner.dataset.compactControlsReady==='1')return;
    const head=partner.querySelector('.partnerhead');
    const basic=partner.querySelector('.controls');
    const access=partner.querySelector('.claimbox');
    if(!head||!basic||!access)return;
    partner.dataset.compactControlsReady='1';

    const dirBack=document.createElement('button');
    dirBack.type='button';
    dirBack.className='partner-directory-back';
    dirBack.textContent='← Back to Partners';
    dirBack.addEventListener('click',()=>showPartnerDirectory(controlsCard));
    partner.prepend(dirBack);

    const statusActions=ensureQuickStatus(partner,head,basic);

    const tabs=document.createElement('div');
    tabs.className='partner-control-tabs';
    tabs.innerHTML='<button type="button" data-control-view="basic">Basic</button><button type="button" data-control-view="access">Access</button>';
    tabs.addEventListener('click',e=>{
      const btn=e.target.closest('[data-control-view]');
      if(btn)setPartnerControlView(partner,btn.dataset.controlView);
    });
    statusActions.insertAdjacentElement('afterend',tabs);
    const basicPanel=buildPanel('basic',basic);
    const accessPanel=buildPanel('access',access);
    tabs.insertAdjacentElement('afterend',accessPanel);
    tabs.insertAdjacentElement('afterend',basicPanel);
  }

  function partnerName(partner){return (partner.querySelector('.partnerhead b')?.textContent||'').trim();}
  function partnerLetter(name){const c=(name||'').trim().charAt(0).toUpperCase();return /^[A-Z]$/.test(c)?c:'#';}

  function appendDirectoryGroup(dir,label,items,controlsCard,suspended=false){
    if(!items.length)return;
    const group=document.createElement('section');
    group.className='partner-directory-group'+(suspended?' suspended-group':'');
    const title=document.createElement('div');
    title.className='partner-directory-letter';
    title.textContent=label;
    const list=document.createElement('div');
    list.className='partner-directory-list';
    items.forEach(item=>{
      const btn=document.createElement('button');
      btn.type='button';
      btn.className='partner-directory-name';
      btn.textContent=item.name;
      btn.addEventListener('click',()=>showPartnerDetail(controlsCard,item.partner));
      list.appendChild(btn);
    });
    group.append(title,list);
    dir.appendChild(group);
  }

  function rebuildPartnerDirectory(controlsCard){
    const root=controlsCard?.querySelector('#partnerControls');
    if(!root)return;
    const x=window.scrollX||0;
    const y=window.scrollY||0;
    root.querySelectorAll('.partner').forEach(p=>compactPartnerCard(p,controlsCard));

    let dir=controlsCard.querySelector('#partnerDirectory');
    if(!dir){
      dir=document.createElement('div');
      dir.id='partnerDirectory';
      dir.className='partner-directory';
      root.insertAdjacentElement('beforebegin',dir);
    }

    const partners=[...root.querySelectorAll('.partner')]
      .map((partner,index)=>({partner,index,name:partnerName(partner),status:partnerStatus(partner)}))
      .filter(x=>x.name)
      .sort((a,b)=>a.name.localeCompare(b.name,undefined,{sensitivity:'base'}));

    dir.innerHTML='';
    if(!partners.length){
      dir.innerHTML='<div class="partner-directory-empty">No Partners match the current search.</div>';
      root.classList.add('partner-directory-list-hidden');
      window.scrollTo({left:x,top:y,behavior:'auto'});
      return;
    }

    const active=partners.filter(x=>x.status!=='suspended');
    const suspended=partners.filter(x=>x.status==='suspended');
    const groups=new Map();
    active.forEach(item=>{
      const letter=partnerLetter(item.name);
      if(!groups.has(letter))groups.set(letter,[]);
      groups.get(letter).push(item);
    });

    [...groups.entries()].sort((a,b)=>a[0].localeCompare(b[0])).forEach(([letter,items])=>appendDirectoryGroup(dir,letter,items,controlsCard,false));
    appendDirectoryGroup(dir,'Suspended',suspended,controlsCard,true);

    showPartnerDirectory(controlsCard);
    window.scrollTo({left:x,top:y,behavior:'auto'});
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
    preserveViewport(()=>{
      const createCard=cardByTitle('Create Partner');
      const controlsCard=cardByTitle('Partner Controls');
      createCard?.classList.add('partner-sub-hidden');
      controlsCard?.classList.add('partner-sub-hidden');
      launcher()?.classList.remove('partner-sub-hidden');
    });
  }

  function showSubview(which){
    preserveViewport(()=>{
      const createCard=cardByTitle('Create Partner');
      const controlsCard=cardByTitle('Partner Controls');
      launcher()?.classList.add('partner-sub-hidden');
      createCard?.classList.toggle('partner-sub-hidden',which!=='add');
      controlsCard?.classList.toggle('partner-sub-hidden',which!=='controls');
      if(which==='controls')rebuildPartnerDirectory(controlsCard);
    });
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
    rebuildPartnerDirectory(controlsCard);

    const partnerRoot=controlsCard.querySelector('#partnerControls');
    if(partnerRoot&&!partnerRoot.dataset.directoryObserverReady){
      partnerRoot.dataset.directoryObserverReady='1';
      let queued=false;
      const po=new MutationObserver(()=>{
        if(queued)return;
        queued=true;
        queueMicrotask(()=>{queued=false;rebuildPartnerDirectory(controlsCard);});
      });
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