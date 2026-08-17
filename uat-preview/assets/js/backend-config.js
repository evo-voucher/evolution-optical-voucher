// Evolution Voucher UAT Preview backend configuration.
// Isolated preview: canonical reconstructed Supabase backend + preview-local customer links.
// Browser clients use the Supabase publishable key only. Never place service_role here.
const EVOLUTION_ASSET_VERSION='20260817-8';
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

(function installPortalAuthNamespace() {
  const supabase = window.supabase;
  if (!supabase || typeof supabase.createClient !== 'function' || supabase.__evolutionAuthNamespaced) return;
  const originalCreateClient = supabase.createClient.bind(supabase);
  const path = String(window.location?.pathname || '').toLowerCase();
  function resolveStorageKey() {
    if (path.includes('admin') || path.includes('voucher-engine')) return 'evolution-voucher-auth-admin';
    if (path.includes('partner')) return 'evolution-voucher-auth-partner';
    if (path.includes('staff')) return 'evolution-voucher-auth-staff';
    return 'evolution-voucher-auth-default';
  }
  const portalStorageKey = resolveStorageKey();
  supabase.createClient = function createNamespacedClient(url, key, options = {}) {
    const authOptions = options?.auth || {};
    return originalCreateClient(url, key, {
      ...options,
      auth: { ...authOptions, storageKey: authOptions.storageKey || portalStorageKey }
    });
  };
  Object.defineProperty(supabase, '__evolutionAuthNamespaced', {
    value: true, configurable: false, enumerable: false, writable: false
  });
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