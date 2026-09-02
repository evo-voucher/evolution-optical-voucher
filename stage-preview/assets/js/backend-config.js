// Voucher Stage preview backend configuration wrapper.
// Reuses the UAT preview runtime helpers, but forcibly routes all browser backend access to Voucher Stage.
// Browser clients use the Supabase publishable key only. Never place service_role here.
(() => {
  const STAGE = Object.freeze({
    enabled: true,
    role: 'stage',
    authoritativeData: false,
    environment: 'stage',
    projectId: 'tagusbcluzoxueixjmwh',
    supabaseUrl: 'https://tagusbcluzoxueixjmwh.supabase.co',
    publishableKey: 'sb_publishable_R86zjGv4yso-krORZdj3IQ_7QZUtMMB',
    siteBase: 'https://evo-voucher.github.io/evolution-optical-voucher/stage-preview/'
  });

  let current = STAGE;
  Object.defineProperty(window, 'EVOLUTION_VOUCHER_BACKEND', {
    configurable: true,
    enumerable: true,
    get() { return current; },
    set(value) {
      current = Object.freeze({ ...(value || {}), ...STAGE });
    }
  });

  // Load the existing UAT preview helper layer synchronously. Any backend assignment
  // made by that helper is intercepted above and rewritten to Voucher Stage.
  document.write('<script src="../uat-preview/assets/js/backend-config.js"><\/script>');
})();
