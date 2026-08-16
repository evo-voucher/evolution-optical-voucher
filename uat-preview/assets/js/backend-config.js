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
