// Temporary Evolution Voucher UAT backend configuration.
// Uses the canonical reconstructed Supabase backend and an isolated /uat/ site base.
// Browser clients use the Supabase publishable key only. Never place service_role here.
window.EVOLUTION_VOUCHER_BACKEND = Object.freeze({
  enabled: true,
  environment: 'uat',
  projectId: 'xfivcfwexcxsyiylgryn',
  supabaseUrl: 'https://xfivcfwexcxsyiylgryn.supabase.co',
  publishableKey: 'sb_publishable_uu1Qyx-M3dldpZn9jq7jXw_RLTHOMh_',
  siteBase: 'https://evo-voucher.github.io/evolution-optical-voucher/uat/'
});
