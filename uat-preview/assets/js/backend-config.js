// Evolution Voucher UAT Preview backend configuration.
// Isolated preview: canonical reconstructed Supabase backend + preview-local customer links.
// Browser clients use the Supabase publishable key only. Never place service_role here.
const EVOLUTION_ASSET_VERSION='20260818-06';
window.EVOLUTION_ASSET_VERSION=EVOLUTION_ASSET_VERSION;
const evolutionAsset=path=>`${path}?v=${encodeURIComponent(EVOLUTION_ASSET_VERSION)}`;

window.EVOLUTION_VOUCHER_BACKEND = Object.freeze({
  enabled: true,
  environment: 'production',
  projectId: 'xfivcfwexcxsyiylgryn',
  supabaseUrl: 'https://xfivcfwexcxsyiylgryn.supabase.co',
  publishableKey: 'sb_publishable_uu1Qyx-M3dldpZn9jq7jXw_RLTHOMh_',
  siteBase: 'https://evo-voucher.github.io/evolution-optical-voucher/uat-preview/'
});

(function registerCanonicalAdminSettingsCard(){
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!path.endsWith('/admin.html'))return;
  const register=()=>{
    if(document.getElementById('adminSettingsCard'))return;
    const dash=document.getElementById('dashboardState');
    if(!dash)return;
    const card=[...dash.children].find(el=>el.classList?.contains('card')&&(el.querySelector('h2')?.textContent||'').trim()==='Admin Tools');
    if(!card)return;
    card.id='adminSettingsCard';
    card.dataset.adminSection='settings';
    const heading=card.querySelector('h2');
    if(heading)heading.textContent='System Settings';
    const toolgrid=card.querySelector('.toolgrid');
    if(toolgrid)toolgrid.remove();
  };
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',register,{once:true});
  else register();
})();

(function installEvolutionTheme(){
  if(document.getElementById('evolutionCommercialTheme')) return;
  const link=document.createElement('link');
  link.id='evolutionCommercialTheme';
  link.rel='stylesheet';
  link.href=evolutionAsset('assets/css/evolution-theme.css');
  document.head.appendChild(link);
})();

(function installAllocationCompactStyle(){
  if(document.getElementById('allocationCompactStyle')) return;
  const link=document.createElement('link');
  link.id='allocationCompactStyle';
  link.rel='stylesheet';
  link.href=evolutionAsset('assets/css/allocation-compact.css');
  document.head.appendChild(link);
})();

(function installPartnerEntryLayout(){
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!path.endsWith('/admin.html'))return;
  if(document.getElementById('partnerEntryLayoutStyle'))return;
  const link=document.createElement('link');
  link.id='partnerEntryLayoutStyle';
  link.rel='stylesheet';
  link.href=evolutionAsset('assets/css/partner-entry-layout.css');
  document.head.appendChild(link);
})();

(function installPortalAuthNamespaceAndRecovery() {
  const supabase = window.supabase;
  if (!supabase || typeof supabase.createClient !== 'function' || supabase.__evolutionAuthNamespaced) return;
  const originalCreateClient = supabase.createClient.bind(supabase);
  const path = String(window.location?.pathname || '').toLowerCase();
  const clientCache = new Map();

  function resolveStorageKey() {
    if (path.includes('admin') || path.includes('voucher-engine')) return 'evolution-voucher-auth-admin-v2';
    if (path.includes('partner')) return 'evolution-voucher-auth-partner';
    if (path.includes('staff')) return 'evolution-voucher-auth-staff';
    return 'evolution-voucher-auth-default';
  }

  function errorStatus(error) {
    const direct=Number(error?.status||error?.statusCode||0);
    if(direct)return direct;
    const context=error?.context;
    const fromContext=Number(context?.status||context?.statusCode||0);
    if(fromContext)return fromContext;
    return /\b401\b|unauthorized/i.test(String(error?.message||''))?401:0;
  }

  function isTerminalSessionError(error) {
    const code=String(error?.code||error?.error_code||'').toLowerCase();
    const message=String(error?.message||error||'').toLowerCase();
    return code==='refresh_token_not_found'||code==='session_not_found'||/refresh token not found|session not found/.test(message);
  }

  const portalStorageKey = resolveStorageKey();
  if(portalStorageKey==='evolution-voucher-auth-admin-v2'){
    try{localStorage.removeItem('evolution-voucher-auth-admin');}catch(_){}
    try{sessionStorage.removeItem('evolution-voucher-auth-admin');}catch(_){}
  }

  async function clearTerminalSession(client,error) {
    if(!isTerminalSessionError(error))return false;
    try{localStorage.removeItem(portalStorageKey);}catch(_){}
    try{sessionStorage.removeItem(portalStorageKey);}catch(_){}
    try{await client.auth.signOut({scope:'local'});}catch(_){}
    return true;
  }

  async function refreshIfPossible(client,force=false) {
    const {data}=await client.auth.getSession();
    const session=data?.session;
    if(!session)return false;
    const expiresAt=Number(session.expires_at||0);
    const nearExpiry=expiresAt>0&&expiresAt*1000<=Date.now()+90000;
    if(!force&&!nearExpiry)return true;
    const {data:refreshed,error}=await client.auth.refreshSession();
    if(error){
      await clearTerminalSession(client,error);
      return false;
    }
    return !!refreshed?.session;
  }

  function wrapClient(client) {
    if(!client?.functions||client.__evolutionAuthRecovery)return client;
    const originalInvoke=client.functions.invoke.bind(client.functions);
    client.functions.invoke=async function resilientInvoke(name,options){
      try{await refreshIfPossible(client,false)}catch(_){/* normal invoke remains authoritative */}
      let result=await originalInvoke(name,options);
      if(errorStatus(result?.error)!==401)return result;
      let refreshed=false;
      try{refreshed=await refreshIfPossible(client,true)}catch(_){refreshed=false}
      if(!refreshed)return result;
      result=await originalInvoke(name,options);
      return result;
    };
    Object.defineProperty(client,'__evolutionAuthRecovery',{value:true,enumerable:false});
    return client;
  }

  supabase.createClient = function createNamespacedClient(url, key, options = {}) {
    const authOptions = options?.auth || {};
    const storageKey = authOptions.storageKey || portalStorageKey;
    const persistSession = authOptions.persistSession !== false;
    const cacheKey = persistSession ? `${String(url)}|${String(key)}|${storageKey}` : '';
    if(cacheKey&&clientCache.has(cacheKey))return clientCache.get(cacheKey);
    const client=wrapClient(originalCreateClient(url, key, {
      ...options,
      auth: { ...authOptions, storageKey }
    }));
    if(cacheKey)clientCache.set(cacheKey,client);
    return client;
  };
  Object.defineProperty(supabase, '__evolutionAuthNamespaced', {
    value: true, configurable: false, enumerable: false, writable: false
  });
})();

(function loadAdminMobileFocus(){
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!path.endsWith('/admin.html'))return;
  if(document.getElementById('adminMobileFocusScript'))return;
  const script=document.createElement('script');
  script.id='adminMobileFocusScript';
  script.src=evolutionAsset('assets/js/admin-mobile-focus.js');
  document.head.appendChild(script);
})();

(function loadAllocationValidityUI(){
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!(path.endsWith('/admin.html')||path.includes('voucher-engine')))return;
  if(document.getElementById('allocationValidityUiScript'))return;
  const script=document.createElement('script');
  script.id='allocationValidityUiScript';
  script.src=evolutionAsset('assets/js/allocation-validity-ui.js');
  document.head.appendChild(script);
})();

(function loadAllocationManagementUI(){
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!path.includes('voucher-engine'))return;
  if(document.getElementById('allocationManagementUiScript'))return;
  const script=document.createElement('script');
  script.id='allocationManagementUiScript';
  script.src=evolutionAsset('assets/js/allocation-management-ui.js');
  document.head.appendChild(script);
})();

(function loadPartnerManagementUI(){
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!path.endsWith('/admin.html'))return;
  if(document.getElementById('partnerManagementUiScript'))return;
  const script=document.createElement('script');
  script.id='partnerManagementUiScript';
  script.src=evolutionAsset('assets/js/partner-management-ui.js');
  document.head.appendChild(script);
})();

(function loadPortalAccessShare(){
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!(path.endsWith('/admin.html')||path.endsWith('/partner.html')))return;
  if(document.getElementById('portalAccessShareScript'))return;
  const script=document.createElement('script');
  script.id='portalAccessShareScript';
  script.src=evolutionAsset('assets/js/portal-access-share.js');
  document.head.appendChild(script);
})();

(function loadTestSandboxUI(){
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!path.endsWith('/admin.html'))return;
  if(document.getElementById('testSandboxUiScript'))return;
  const script=document.createElement('script');
  script.id='testSandboxUiScript';
  script.src=evolutionAsset('assets/js/test-sandbox-ui.js');
  document.head.appendChild(script);
})();

(function loadVoucherCardImageUI(){
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!path.endsWith('/partner.html'))return;
  if(document.getElementById('voucherCardRendererScript'))return;
  const renderer=document.createElement('script');
  renderer.id='voucherCardRendererScript';
  renderer.src=evolutionAsset('assets/js/voucher-card-renderer.js');
  renderer.onload=()=>{
    if(document.getElementById('voucherCardShareUiScript'))return;
    const share=document.createElement('script');
    share.id='voucherCardShareUiScript';
    share.src=evolutionAsset('assets/js/voucher-card-share-ui.js');
    document.head.appendChild(share);
  };
  document.head.appendChild(renderer);
})();