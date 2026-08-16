// Evolution Voucher UAT Preview backend configuration.
// Isolated preview: canonical reconstructed Supabase backend + preview-local customer links.
// Browser clients use the Supabase publishable key only. Never place service_role here.
window.EVOLUTION_VOUCHER_BACKEND = Object.freeze({
  enabled: true,
  environment: 'production',
  projectId: 'xfivcfwexcxsyiylgryn',
  supabaseUrl: 'https://xfivcfwexcxsyiylgryn.supabase.co',
  publishableKey: 'sb_publishable_uu1Qyx-M3dldpZn9jq7jXw_RLTHOMh_',
  siteBase: 'https://evo-voucher.github.io/evolution-optical-voucher/uat-preview/'
});

(function installEvolutionTheme(){
  if(document.getElementById('evolutionCommercialTheme')) return;
  const link=document.createElement('link');
  link.id='evolutionCommercialTheme';
  link.rel='stylesheet';
  link.href='assets/css/evolution-theme.css?v=1';
  document.head.appendChild(link);
})();

(function installAllocationCompactStyle(){
  if(document.getElementById('allocationCompactStyle')) return;
  const link=document.createElement('link');
  link.id='allocationCompactStyle';
  link.rel='stylesheet';
  link.href='assets/css/allocation-compact.css?v=1';
  document.head.appendChild(link);
})();

(function installPartnerEntryLayout(){
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!path.endsWith('/admin.html'))return;
  if(document.getElementById('partnerEntryLayoutStyle'))return;
  const link=document.createElement('link');
  link.id='partnerEntryLayoutStyle';
  link.rel='stylesheet';
  link.href='assets/css/partner-entry-layout.css?v=3';
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
  script.src='assets/js/allocation-validity-ui.js?v=1';
  document.head.appendChild(script);
})();

(function loadPartnerManagementUI(){
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!path.endsWith('/admin.html'))return;
  if(document.getElementById('partnerManagementUiScript'))return;
  const script=document.createElement('script');
  script.id='partnerManagementUiScript';
  script.src='assets/js/partner-management-ui.js?v=3';
  document.head.appendChild(script);
})();
