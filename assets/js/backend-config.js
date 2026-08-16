// Evolution Voucher frontend backend configuration.
// Cutover branch: production release candidate for the reconstructed canonical Supabase backend.
// Browser clients use the Supabase publishable key only. Never place service_role here.
window.EVOLUTION_VOUCHER_BACKEND = Object.freeze({
  enabled: true,
  environment: 'production',
  projectId: 'xfivcfwexcxsyiylgryn',
  supabaseUrl: 'https://xfivcfwexcxsyiylgryn.supabase.co',
  publishableKey: 'sb_publishable_uu1Qyx-M3dldpZn9jq7jXw_RLTHOMh_',
  siteBase: 'https://evo-voucher.github.io/evolution-optical-voucher/'
});

// Shared commercial UI theme. Kept outside page business logic so visual changes remain reversible.
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

// Auth session ownership
// ----------------------
// All portals are served from the same GitHub Pages origin and use the same Supabase project.
// Supabase's default browser storage key would therefore be shared across Admin, Partner and
// Staff portals, allowing one portal login/logout/refresh to overwrite another portal's session.
// Keep each operational surface in its own storage namespace. Admin-owned tools intentionally
// share the Admin namespace; Partner and Evolution Staff remain isolated.
(function installPortalAuthNamespace() {
  const supabase = window.supabase;
  if (!supabase || typeof supabase.createClient !== 'function' || supabase.__evolutionAuthNamespaced) return;

  const originalCreateClient = supabase.createClient.bind(supabase);
  const path = String(window.location?.pathname || '').toLowerCase();

  function resolveStorageKey() {
    if (
      path.includes('admin') ||
      path.includes('voucher-engine')
    ) return 'evolution-voucher-auth-admin';

    if (path.includes('partner')) return 'evolution-voucher-auth-partner';
    if (path.includes('staff')) return 'evolution-voucher-auth-staff';

    return 'evolution-voucher-auth-default';
  }

  const portalStorageKey = resolveStorageKey();

  supabase.createClient = function createNamespacedClient(url, key, options = {}) {
    const authOptions = options?.auth || {};
    return originalCreateClient(url, key, {
      ...options,
      auth: {
        ...authOptions,
        storageKey: authOptions.storageKey || portalStorageKey
      }
    });
  };

  Object.defineProperty(supabase, '__evolutionAuthNamespaced', {
    value: true,
    configurable: false,
    enumerable: false,
    writable: false
  });
})();

// Per-allocation validity UI is isolated from core page logic so the feature can evolve
// without rewriting Admin or Voucher Engine pages.
(function loadAllocationValidityUI(){
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!(path.endsWith('/admin.html')||path.includes('voucher-engine')))return;
  if(document.getElementById('allocationValidityUiScript'))return;
  const script=document.createElement('script');
  script.id='allocationValidityUiScript';
  script.src='assets/js/allocation-validity-ui.js?v=1';
  document.head.appendChild(script);
})();

(function loadPartnerSetupCollapse(){
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!path.endsWith('/admin.html'))return;
  if(document.getElementById('partnerSetupCollapseScript'))return;
  const script=document.createElement('script');
  script.id='partnerSetupCollapseScript';
  script.src='assets/js/partner-setup-collapse.js?v=1';
  document.head.appendChild(script);
})();
