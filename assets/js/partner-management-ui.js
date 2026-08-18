(()=>{
  const CARD_SELECTOR='#dashboardState > .card';
  const cardByTitle=title=>[...document.querySelectorAll(CARD_SELECTOR)].find(card=>(card.querySelector('h2')?.textContent||'').trim()===title)||null;

  function installStyle(){
    if(document.getElementById('partnerManagementUiStyle'))return;
    const s=document.createElement('style');s.id='partnerManagementUiStyle';s.textContent=`
      .partner-subnav{display:grid;grid-template-columns:1fr 1fr;gap:12px}.partner-subnav button{min-height:76px!important;padding:14px!important;font-weight:800!important}.partner-sub-hidden{display:none!important}.partner-sub-return{width:auto!important;min-width:96px!important;min-height:40px!important;padding:8px 12px!important;margin:0 0 12px!important}.partner-setup-details{border:1px solid rgba(118,91,255,.5);border-radius:16px;background:#0a1736;overflow:hidden}.partner-setup-details>summary{list-style:none;cursor:pointer;padding:14px 16px;font-weight:800;color:#e9efff;display:flex;align-items:center;justify-content:space-between;gap:12px}.partner-setup-details>summary::-webkit-details-marker{display:none}.partner-setup-details>summary::after{content:'›';font-size:24px;line-height:1;color:#8feaff;transform:rotate(90deg)}.partner-setup-details[open]>summary::after{transform:rotate(-90deg)}.partner-setup-details-body{padding:0 12px 12px}.partner-auto-code-note{padding:11px 12px;border:1px solid rgba(100,128,210,.45);border-radius:13px;background:#0d1839;color:#bcc7e3;font-size:12px;line-height:1.45}.partner-directory{display:block;margin-top:10px}.partner-directory-group{margin:12px 0 16px}.partner-directory-letter{font-size:12px;font-weight:900;letter-spacing:.14em;color:#8feaff;margin:0 0 7px;padding:0 2px}.partner-directory-group.suspended-group,.partner-directory-group.archived-group{margin-top:22px;padding-top:14px;border-top:1px solid rgba(115,135,210,.22)}.partner-directory-group.suspended-group .partner-directory-letter{color:#ffb4c0;letter-spacing:.08em}.partner-directory-group.archived-group .partner-directory-letter{color:#c7cde2;letter-spacing:.08em}.partner-directory-list{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}.partner-directory-name{min-height:40px!important;padding:8px 10px!important;font-size:12px!important;text-align:left!important;border-radius:11px!important;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.partner-directory-group.suspended-group .partner-directory-name{opacity:.82}.partner-directory-group.archived-group .partner-directory-name{opacity:.66}.partner-directory-empty{padding:14px 4px;color:#91a2c4;font-size:12px}.partner-directory-hidden{display:none!important}#partnerControls.partner-directory-list-hidden{display:none!important}#partnerControls.partner-detail-mode{display:block!important}#partnerControls.partner-detail-mode>.partner{display:none!important}#partnerControls.partner-detail-mode>.partner.partner-detail-active{display:block!important}.partner-directory-back{width:auto!important;min-height:34px!important;padding:6px 9px!important;margin:0 0 10px!important;font-size:11px!important;border-radius:9px!important}.partner-status-actions{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:10px}.partner-status-actions button{min-height:36px!important;padding:6px 8px!important;font-size:11px!important;border-radius:10px!important}.partner-status-actions button.active-state{border-color:rgba(101,230,181,.82)!important;background:linear-gradient(180deg,#176158,#0d3a35)!important}.partner-status-actions button.suspended-state{border-color:rgba(255,146,165,.82)!important;background:linear-gradient(180deg,#6f3141,#4a1d2a)!important}.partner-control-tabs{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:6px;margin-top:8px}.partner-control-tabs button{min-height:36px!important;padding:6px 8px!important;font-size:11px!important;border-radius:10px!important}.partner-control-tabs button.active{border-color:rgba(101,230,181,.82)!important;background:linear-gradient(180deg,#176158,#0d3a35)!important}.partner-control-panel-hidden{display:none!important}.partner-control-panel{margin-top:8px;padding-top:8px;border-top:1px solid rgba(115,135,210,.22)}.partner-legacy-status-control{display:none!important}.partner-password-note{margin:0 0 8px;color:#91a2c4;font-size:11px;line-height:1.45}.partner-password-action{display:block;width:100%;text-align:center;text-decoration:none;color:#fff;min-height:38px;padding:9px 10px;border:1px solid rgba(122,119,255,.7);border-radius:10px;background:linear-gradient(180deg,#3549a8,#182b73 58%,#0d1c4c);font-size:11px;font-weight:900}#partnerControls .partner .controls{margin-top:0!important;grid-template-columns:1fr!important}#partnerControls .partner .claimbox{margin-top:0!important;padding:8px!important}#partnerControls .partner .branchgrid{grid-template-columns:1fr!important}@media(max-width:430px){.partner-directory-list{grid-template-columns:1fr}}@media(max-width:560px){.partner-subnav{grid-template-columns:1fr 1fr;gap:10px}.partner-subnav button{min-height:68px!important;padding:10px!important;font-size:13px!important}}
    `;document.head.appendChild(s);
  }

  function prepareAutoPartnerCode(createCard){
    const input=createCard?.querySelector('#newPartnerCode');if(!input)return;
    input.value='AUTO';input.type='hidden';
    const field=input.closest('.field');if(!field||field.dataset.autoCodeReady==='1')return;
    field.dataset.autoCodeReady='1';
    const label=field.querySelector('label');if(label)label.textContent='Partner Code';
    const note=document.createElement('div');note.className='partner-auto-code-note';note.innerHTML='<b>Auto-generated</b><br>Based on Partner Name. Example: Abu → A001, next A Partner → A002.';field.appendChild(note);
  }

  function ensureVoucherCollapse(createCard){const setup=createCard?.querySelector('#initialVoucherSetup');if(!setup||setup.dataset.partnerUiCollapsed==='1')return;setup.dataset.partnerUiCollapsed='1';const d=document.createElement('details');d.className='partner-setup-details';d.innerHTML='<summary>Voucher & Claim Setup</summary><div class="partner-setup-details-body"></div>';const body=d.querySelector('.partner-setup-details-body');while(setup.firstChild)body.appendChild(setup.firstChild);setup.appendChild(d);}
  function closePanels(p){p.querySelectorAll('.partner-control-panel').forEach(x=>x.classList.add('partner-control-panel-hidden'));p.querySelectorAll('[data-control-view]').forEach(x=>x.classList.remove('active'));}
  function setView(p,v){const panel=p.querySelector(`.partner-control-panel[data-panel="${v}"]`),btn=p.querySelector(`[data-control-view="${v}"]`),open=panel&&!panel.classList.contains('partner-control-panel-hidden');closePanels(p);if(!open){panel?.classList.remove('partner-control-panel-hidden');btn?.classList.add('active');}}
  function partnerStatus(p){return (p.querySelector('.partnerhead .badge')?.textContent||'').trim().toLowerCase();}
  function partnerId(p){return p.querySelector('select[id^="st-"]')?.id?.replace(/^st-/,'')||'';}
  function partnerName(p){return (p.querySelector('.partnerhead b')?.textContent||'').trim();}
  function partnerCode(p){const text=(p.querySelector('.partnerhead .small')?.textContent||'').trim();return (text.split('•')[0]||'').trim().toUpperCase();}

  function showDirectory(card){const root=card?.querySelector('#partnerControls'),dir=card?.querySelector('#partnerDirectory');if(!root||!dir)return;root.classList.remove('partner-detail-mode');root.classList.add('partner-directory-list-hidden');root.querySelectorAll('.partner').forEach(p=>{p.classList.remove('partner-detail-active');closePanels(p)});dir.classList.remove('partner-directory-hidden');}
  function showDetail(card,p){const root=card?.querySelector('#partnerControls'),dir=card?.querySelector('#partnerDirectory');if(!root||!dir)return;dir.classList.add('partner-directory-hidden');root.classList.remove('partner-directory-list-hidden');root.classList.add('partner-detail-mode');root.querySelectorAll('.partner').forEach(x=>x.classList.toggle('partner-detail-active',x===p));closePanels(p);}

  function compactPartnerCard(p,card){
    if(!p||p.dataset.compactControlsReady==='1')return;const head=p.querySelector('.partnerhead'),basic=p.querySelector('.controls'),access=p.querySelector('.claimbox');if(!head||!basic||!access)return;p.dataset.compactControlsReady='1';
    const back=document.createElement('button');back.type='button';back.className='partner-directory-back';back.textContent='← Back to Partners';back.onclick=()=>showDirectory(card);p.prepend(back);
    const statusField=[...basic.querySelectorAll('.field')].find(f=>(f.querySelector('label')?.textContent||'').trim()==='Status');statusField?.classList.add('partner-legacy-status-control');
    const staffLabel=[...basic.querySelectorAll('.field label')].find(l=>(l.textContent||'').trim()==='Partner Staff');if(staffLabel)staffLabel.textContent='Redeem Portal Users';
    const actions=document.createElement('div');actions.className='partner-status-actions';actions.innerHTML='<button type="button" data-partner-status="active">Active</button><button type="button" data-partner-status="suspended">Suspend</button>';actions.onclick=e=>{const b=e.target.closest('[data-partner-status]');if(!b)return;const id=partnerId(p),target=b.dataset.partnerStatus;if(id&&typeof window.setStatus==='function'&&partnerStatus(p)!==target)window.setStatus(id,target)};head.insertAdjacentElement('afterend',actions);
    const tabs=document.createElement('div');tabs.className='partner-control-tabs';tabs.innerHTML='<button type="button" data-control-view="basic">Staff Limit</button><button type="button" data-control-view="access">Branch Access</button><button type="button" data-control-view="password">Reset Password</button>';tabs.onclick=e=>{const b=e.target.closest('[data-control-view]');if(b)setView(p,b.dataset.controlView)};actions.insertAdjacentElement('afterend',tabs);
    const password=document.createElement('div');const id=partnerId(p);password.innerHTML=`<p class="partner-password-note">Reset this Partner Administrator password through the trusted Admin password-reset flow.</p><a class="partner-password-action" href="admin-partner-password.html${id?`?partner_id=${encodeURIComponent(id)}`:''}">Reset Partner Password</a>`;
    [['basic',basic],['access',access],['password',password]].forEach(([kind,node])=>{const panel=document.createElement('div');panel.className='partner-control-panel partner-control-panel-hidden';panel.dataset.panel=kind;panel.appendChild(node);tabs.insertAdjacentElement('afterend',panel)});
  }

  function appendGroup(dir,label,items,card,kind='active'){
    if(!items.length)return;
    const group=document.createElement('section');
    group.className='partner-directory-group'+(kind==='suspended'?' suspended-group':kind==='archived'?' archived-group':'');
    const title=document.createElement('div');title.className='partner-directory-letter';title.textContent=label;
    const list=document.createElement('div');list.className='partner-directory-list';
    items.forEach(item=>{const b=document.createElement('button');b.type='button';b.className='partner-directory-name';b.textContent=`${item.code?item.code+' · ':''}${item.name}`;b.onclick=()=>showDetail(card,item.partner);list.appendChild(b)});
    group.append(title,list);dir.appendChild(group);
  }

  function rebuildDirectory(card){
    const root=card?.querySelector('#partnerControls');if(!root)return;
    root.querySelectorAll('.partner').forEach(p=>compactPartnerCard(p,card));
    let dir=card.querySelector('#partnerDirectory');if(!dir){dir=document.createElement('div');dir.id='partnerDirectory';dir.className='partner-directory';root.insertAdjacentElement('beforebegin',dir)}
    const rows=[...root.querySelectorAll('.partner')]
      .map(partner=>({partner,name:partnerName(partner),code:partnerCode(partner),status:partnerStatus(partner)}))
      .filter(x=>x.name)
      .sort((a,b)=>(a.code||'ZZZZ').localeCompare(b.code||'ZZZZ',undefined,{numeric:true})||a.name.localeCompare(b.name,undefined,{sensitivity:'base'}));
    dir.innerHTML='';
    if(!rows.length){dir.innerHTML='<div class="partner-directory-empty">No Partners match the current search.</div>';root.classList.add('partner-directory-list-hidden');return;}

    const active=rows.filter(x=>x.status==='active');
    const suspended=rows.filter(x=>x.status==='suspended');
    const archived=rows.filter(x=>x.status==='archived');
    const other=rows.filter(x=>!['active','suspended','archived'].includes(x.status));
    const activeRows=[...active,...other];
    const groups=new Map();
    activeRows.forEach(x=>{const c=(x.code||x.name).charAt(0).toUpperCase(),letter=/^[A-Z]$/.test(c)?c:'#';if(!groups.has(letter))groups.set(letter,[]);groups.get(letter).push(x)});
    [...groups.entries()].sort((a,b)=>a[0].localeCompare(b[0])).forEach(([l,items])=>appendGroup(dir,l,items,card,'active'));
    appendGroup(dir,'Suspended',suspended,card,'suspended');
    appendGroup(dir,'Archived',archived,card,'archived');
    showDirectory(card);
  }

  const launcher=()=>document.getElementById('partnerSubnavCard');
  function showMenu(){cardByTitle('Create Partner')?.classList.add('partner-sub-hidden');cardByTitle('Partner Controls')?.classList.add('partner-sub-hidden');launcher()?.classList.remove('partner-sub-hidden');}
  function showSubview(which){const create=cardByTitle('Create Partner'),controls=cardByTitle('Partner Controls');launcher()?.classList.add('partner-sub-hidden');create?.classList.toggle('partner-sub-hidden',which!=='add');controls?.classList.toggle('partner-sub-hidden',which!=='controls');if(which==='add')prepareAutoPartnerCode(create);if(which==='controls')rebuildDirectory(controls);}
  function ensureReturn(card){if(!card||card.querySelector('.partner-sub-return'))return;const b=document.createElement('button');b.type='button';b.className='partner-sub-return';b.textContent='← Return';b.onclick=showMenu;card.prepend(b);}
  function ensureLauncher(create,controls){if(launcher())return;const card=document.createElement('section');card.id='partnerSubnavCard';card.className='card';card.dataset.adminSection='partners';card.innerHTML='<h2>Partner Management</h2><div class="partner-subnav"><button type="button" data-partner-view="add">＋ Add Partner</button><button type="button" data-partner-view="controls">⚙ Partner Controls</button></div>';card.onclick=e=>{const b=e.target.closest('[data-partner-view]');if(b)showSubview(b.dataset.partnerView)};(create||controls)?.parentNode?.insertBefore(card,create||controls);}

  function mount(){const create=cardByTitle('Create Partner'),controls=cardByTitle('Partner Controls');if(!create||!controls)return false;installStyle();prepareAutoPartnerCode(create);ensureLauncher(create,controls);ensureReturn(create);ensureReturn(controls);ensureVoucherCollapse(create);rebuildDirectory(controls);const root=controls.querySelector('#partnerControls');if(root&&!root.dataset.directoryObserverReady){root.dataset.directoryObserverReady='1';let queued=false;new MutationObserver(()=>{if(queued)return;queued=true;queueMicrotask(()=>{queued=false;rebuildDirectory(controls)})}).observe(root,{childList:true});}if(!document.body.dataset.partnerSubnavReady){document.body.dataset.partnerSubnavReady='1';showMenu();new MutationObserver(m=>{if(m.some(x=>x.attributeName==='data-admin-section')&&document.body.dataset.adminSection==='partners')showMenu()}).observe(document.body,{attributes:true,attributeFilter:['data-admin-section']});}return true;}
  const start=()=>{if(mount()){const create=cardByTitle('Create Partner');new MutationObserver(()=>{prepareAutoPartnerCode(create);ensureVoucherCollapse(create)}).observe(create,{childList:true,subtree:true});return;}const mo=new MutationObserver(()=>{if(mount())mo.disconnect()});mo.observe(document.documentElement,{childList:true,subtree:true});};
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();