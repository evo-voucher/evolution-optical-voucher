// Evolution Voucher production backend configuration.
// Browser clients use the Supabase publishable key only. Never place service_role here.
const EVOLUTION_ASSET_VERSION=(()=>{
  const pageVersion=new URLSearchParams(window.location.search).get('v');
  let scriptVersion='';
  try{scriptVersion=new URL(document.currentScript?.src||'',window.location.href).searchParams.get('v')||'';}catch(_){}
  const pagePath=String(window.location?.pathname||'').toLowerCase();
  const legacyAdminBootstrap=pagePath.endsWith('/admin.html')&&scriptVersion==='20260818-07';
  return pageVersion||(legacyAdminBootstrap?'20260822-1616':scriptVersion)||'20260822-1616';
})();
window.EVOLUTION_ASSET_VERSION=EVOLUTION_ASSET_VERSION;
const evolutionAsset=path=>`${path}?v=${encodeURIComponent(EVOLUTION_ASSET_VERSION)}`;

window.EVOLUTION_VOUCHER_BACKEND = Object.freeze({
  enabled: true,
  environment: 'production',
  projectId: 'xfivcfwexcxsyiylgryn',
  supabaseUrl: 'https://xfivcfwexcxsyiylgryn.supabase.co',
  publishableKey: 'sb_publishable_uu1Qyx-M3dldpZn9jq7jXw_RLTHOMh_',
  siteBase: 'https://evo-voucher.github.io/evolution-optical-voucher/'
});

(function unifyBrowserChrome(){
  const apply=()=>{
    const metas=[...document.querySelectorAll('meta[name="theme-color"]')];
    if(!metas.length){const meta=document.createElement('meta');meta.name='theme-color';document.head.appendChild(meta);metas.push(meta);}
    metas.forEach(meta=>meta.setAttribute('content','#000000'));
    document.documentElement.style.backgroundColor='#000000';
  };
  apply();if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',apply,{once:true});else apply();
})();

(function installSecondLevelReturnToMain(){
  const path=String(window.location?.pathname||'').toLowerCase();
  const secondLevelPaths=['/admin-login.html','/admin.html','/voucher-engine.html','/partner.html','/staff.html','/admin-staff.html'];
  if(!secondLevelPaths.some(p=>path.endsWith(p)))return;
  const install=()=>{
    if(document.getElementById('portalReturnMainBtn'))return;
    const existing=[...document.querySelectorAll('button,a')].find(el=>(el.textContent||'').trim().toLowerCase()==='return to main');
    if(existing){existing.id=existing.id||'portalReturnMainBtn';return;}
    const btn=document.createElement('button');
    btn.id='portalReturnMainBtn';btn.type='button';btn.textContent='Return to Main';btn.setAttribute('aria-label','Return to Voucher Main');
    btn.onclick=()=>{window.location.href=window.EVOLUTION_VOUCHER_BACKEND?.siteBase||'./';};
    const top=document.querySelector('body .toprow');
    if(top){const logout=document.getElementById('logoutBtn');if(logout)top.insertBefore(btn,logout);else top.appendChild(btn);return;}
    const firstCard=document.querySelector('main .card, body .card');
    if(firstCard){btn.classList.add('wide');btn.style.marginBottom='14px';firstCard.prepend(btn);return;}
    const main=document.querySelector('main')||document.body;btn.classList.add('wide');main.prepend(btn);
  };
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install,{once:true});else install();
})();

(function honorAdminDeepLink(){
  const path=String(window.location?.pathname||'').toLowerCase();if(!(path.endsWith('/admin.html')||path.endsWith('/admin-dashboard.html')))return;
  let requested='';try{requested=sessionStorage.getItem('evo-admin-section')||'';}catch(_){}if(requested!=='reports')return;
  const locate=()=>{const dash=document.getElementById('dashboardState');if(!dash||dash.classList.contains('hidden'))return false;const target=[...dash.querySelectorAll('.card')].find(card=>(card.querySelector('h2')?.textContent||'').trim()==='Redemption Report');if(!target)return false;target.scrollIntoView({behavior:'smooth',block:'start'});target.animate?.([{boxShadow:'0 0 0 0 rgba(214,90,240,0)'},{boxShadow:'0 0 0 3px rgba(214,90,240,.55)'},{boxShadow:'0 0 0 0 rgba(214,90,240,0)'}],{duration:1200,easing:'ease-out'});try{sessionStorage.removeItem('evo-admin-section')}catch(_){}return true;};
  const start=()=>{if(locate())return;let tries=0;const timer=setInterval(()=>{tries++;if(locate()||tries>40)clearInterval(timer)},250);};if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();

(function registerCanonicalAdminSettingsCard(){
  const path=String(window.location?.pathname||'').toLowerCase();if(!path.endsWith('/admin.html'))return;
  const register=()=>{
    if(document.getElementById('adminSettingsCard'))return;
    const dash=document.getElementById('dashboardState');if(!dash)return;
    const toolsCard=[...dash.children].find(el=>el.classList?.contains('card')&&(el.querySelector('h2')?.textContent||'').trim()==='Admin Tools');
    if(!toolsCard)return;
    const settingsCard=document.createElement('section');
    settingsCard.id='adminSettingsCard';
    settingsCard.className='card';
    settingsCard.dataset.adminSection='settings';
    settingsCard.innerHTML='<h2>System Settings</h2>';
    toolsCard.insertAdjacentElement('afterend',settingsCard);
  };
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',register,{once:true});else register();
})();

(function recoverPartnerAccessShareView(){
  const path=String(window.location?.pathname||'').toLowerCase();if(!path.endsWith('/admin.html'))return;
  let ready=null;try{ready=JSON.parse(sessionStorage.getItem('evo_ready_partner_access_share')||'null')}catch(_){}
  if(!ready?.email)return;
  const reveal=()=>{
    const partnerNav=document.querySelector('[data-admin-open="partners"]');
    if(partnerNav)partnerNav.click();
    const add=document.querySelector('[data-partner-view="add"]');
    if(!add)return false;
    add.click();
    setTimeout(()=>document.getElementById('partnerAccessShare')?.scrollIntoView({block:'center',behavior:'smooth'}),180);
    return true;
  };
  let tries=0;const timer=setInterval(()=>{tries++;if(reveal()||tries>100)clearInterval(timer)},100);
})();

(function installEvolutionTheme(){if(document.getElementById('evolutionCommercialTheme'))return;const link=document.createElement('link');link.id='evolutionCommercialTheme';link.rel='stylesheet';link.href=evolutionAsset('assets/css/evolution-theme.css');document.head.appendChild(link);})();
(function installAllocationCompactStyle(){if(document.getElementById('allocationCompactStyle'))return;const link=document.createElement('link');link.id='allocationCompactStyle';link.rel='stylesheet';link.href=evolutionAsset('assets/css/allocation-compact.css');document.head.appendChild(link);})();
(function installPartnerEntryLayout(){const path=String(window.location?.pathname||'').toLowerCase();if(!path.endsWith('/admin.html')||document.getElementById('partnerEntryLayoutStyle'))return;const link=document.createElement('link');link.id='partnerEntryLayoutStyle';link.rel='stylesheet';link.href=evolutionAsset('assets/css/partner-entry-layout.css');document.head.appendChild(link);})();

(function installPortalAuthNamespaceAndRecovery(){
  const supabase=window.supabase;if(!supabase||typeof supabase.createClient!=='function'||supabase.__evolutionAuthNamespaced)return;const originalCreateClient=supabase.createClient.bind(supabase);const path=String(window.location?.pathname||'').toLowerCase();const clientCache=new Map();
  function resolveStorageKey(){if(path.includes('admin')||path.includes('voucher-engine'))return'evolution-voucher-auth-admin-v2';if(path.includes('partner'))return'evolution-voucher-auth-partner';if(path.includes('staff'))return'evolution-voucher-auth-staff';return'evolution-voucher-auth-default';}
  function errorStatus(error){const direct=Number(error?.status||error?.statusCode||0);if(direct)return direct;const context=error?.context;const fromContext=Number(context?.status||context?.statusCode||0);if(fromContext)return fromContext;return/\b401\b|unauthorized/i.test(String(error?.message||''))?401:0;}
  function isTerminalSessionError(error){const code=String(error?.code||error?.error_code||'').toLowerCase();const message=String(error?.message||error||'').toLowerCase();return code==='refresh_token_not_found'||code==='session_not_found'||/refresh token not found|session not found/.test(message);}
  const portalStorageKey=resolveStorageKey();if(portalStorageKey==='evolution-voucher-auth-admin-v2'){try{localStorage.removeItem('evolution-voucher-auth-admin');}catch(_){}try{sessionStorage.removeItem('evolution-voucher-auth-admin');}catch(_){}}
  async function clearTerminalSession(client,error){if(!isTerminalSessionError(error))return false;try{localStorage.removeItem(portalStorageKey);}catch(_){}try{sessionStorage.removeItem(portalStorageKey);}catch(_){}try{await client.auth.signOut({scope:'local'});}catch(_){}return true;}
  async function refreshIfPossible(client,force=false){const{data}=await client.auth.getSession();const session=data?.session;if(!session)return false;const expiresAt=Number(session.expires_at||0);const nearExpiry=expiresAt>0&&expiresAt*1000<=Date.now()+90000;if(!force&&!nearExpiry)return true;const{data:refreshed,error}=await client.auth.refreshSession();if(error){await clearTerminalSession(client,error);return false;}return!!refreshed?.session;}
  function wrapClient(client){if(!client?.functions||client.__evolutionAuthRecovery)return client;const originalInvoke=client.functions.invoke.bind(client.functions);client.functions.invoke=async function resilientInvoke(name,options){try{await refreshIfPossible(client,false)}catch(_){}let result=await originalInvoke(name,options);if(errorStatus(result?.error)!==401)return result;let refreshed=false;try{refreshed=await refreshIfPossible(client,true)}catch(_){refreshed=false}if(!refreshed)return result;return await originalInvoke(name,options);};Object.defineProperty(client,'__evolutionAuthRecovery',{value:true,enumerable:false});return client;}
  supabase.createClient=function createNamespacedClient(url,key,options={}){const authOptions=options?.auth||{};const storageKey=authOptions.storageKey||portalStorageKey;const persistSession=authOptions.persistSession!==false;const cacheKey=persistSession?`${String(url)}|${String(key)}|${storageKey}`:'';if(cacheKey&&clientCache.has(cacheKey))return clientCache.get(cacheKey);const client=wrapClient(originalCreateClient(url,key,{...options,auth:{...authOptions,storageKey}}));if(cacheKey)clientCache.set(cacheKey,client);return client;};Object.defineProperty(supabase,'__evolutionAuthNamespaced',{value:true,configurable:false,enumerable:false,writable:false});
})();

function evoLoadScript(id,path,test){if(test&&!test())return;if(document.getElementById(id))return;const s=document.createElement('script');s.id=id;s.src=evolutionAsset(path);document.head.appendChild(s);}
evoLoadScript('pressedFeedbackScript','assets/js/pressed-feedback.js',()=>true);
(function(){
  const path=String(window.location?.pathname||'').toLowerCase();
  const isAdmin=path.endsWith('/admin.html');
  evoLoadScript('adminMobileFocusScript','assets/js/admin-mobile-focus.js',()=>isAdmin);
  evoLoadScript('allocationValidityUiScript','assets/js/allocation-validity-ui.js',()=>isAdmin||path.includes('voucher-engine'));
  evoLoadScript('allocationManagementUiScript','assets/js/allocation-management-ui.js',()=>path.includes('voucher-engine'));
  evoLoadScript('classificationArchiveUiScript','assets/js/classification-archive-ui.js',()=>path.includes('voucher-engine'));
  evoLoadScript('partnerManagementUiScript','assets/js/partner-management-ui.js',()=>isAdmin);
  if(!isAdmin)evoLoadScript('portalAccessShareScript','assets/js/portal-access-share.js',()=>path.endsWith('/partner.html')||path.endsWith('/admin-staff.html'));
  const loadAdminPartnerCreator=()=>{if(!isAdmin)return;evoLoadScript('portalAccessShareScript','assets/js/portal-access-share.js',()=>true);evoLoadScript('adminPartnerCreateOwnerScript','assets/js/admin-partner-create-owner.js',()=>true);};
  if(isAdmin){if(document.readyState==='complete')setTimeout(loadAdminPartnerCreator,0);else window.addEventListener('load',()=>setTimeout(loadAdminPartnerCreator,0),{once:true});}
  evoLoadScript('customerDistrictUiScript','assets/js/customer-district-ui.js',()=>isAdmin||path.endsWith('/partner.html'));
  evoLoadScript('adminSettingsCollapseScript','assets/js/admin-settings-collapse.js',()=>isAdmin);
  evoLoadScript('portalExcelExportScript','assets/js/portal-excel-export.js',()=>path.endsWith('/partner.html')||path.endsWith('/staff.html'));
})();

(function installSafeVoucherVersionGrouping(){
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!path.includes('voucher-engine'))return;
  const sortSelect=select=>{
    if(!select||select.id!=='allocationVersion'||select.options.length<3)return;
    const current=select.value;
    const placeholder=[...select.options].find(option=>!option.value)||null;
    const options=[...select.options].filter(option=>option.value);
    options.sort((a,b)=>String(a.textContent||'').trim().localeCompare(String(b.textContent||'').trim(),undefined,{numeric:true,sensitivity:'base'}));
    select.replaceChildren(...(placeholder?[placeholder]:[]),...options);
    if(current)select.value=current;
  };
  const handle=e=>{const select=e.target?.closest?.('#allocationVersion');if(select)sortSelect(select);};
  document.addEventListener('pointerdown',handle,true);
  document.addEventListener('focusin',handle,true);
})();

(function loadVoucherCardImageUI(){const path=String(window.location?.pathname||'').toLowerCase();if(!path.endsWith('/partner.html'))return;if(document.getElementById('voucherCardRendererScript'))return;const renderer=document.createElement('script');renderer.id='voucherCardRendererScript';renderer.src=evolutionAsset('assets/js/voucher-card-renderer.js');renderer.onload=()=>{if(document.getElementById('voucherCardShareUiScript'))return;const share=document.createElement('script');share.id='voucherCardShareUiScript';share.src=evolutionAsset('assets/js/voucher-card-share-ui.js');document.head.appendChild(share);};document.head.appendChild(renderer);})();