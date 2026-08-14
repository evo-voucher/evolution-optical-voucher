// Evolution Voucher frontend backend configuration.
// FAIL-CLOSED by default. Do not insert legacy Supabase credentials here.
// Populate only after the NEW reconstructed Supabase target has passed deployment gates.
window.EVOLUTION_VOUCHER_BACKEND = Object.freeze({
  enabled: false,
  environment: 'reconstruction',
  projectId: '',
  supabaseUrl: '',
  publishableKey: '',
  siteBase: 'https://evo-voucher.github.io/evolution-optical-voucher/'
});
