(() => {
  const page = String(window.EVOLUTION_UAT_PAGE || '').trim();
  const allowed = new Set([
    'index.html',
    'admin.html',
    'partner.html',
    'staff.html',
    'voucher.html',
    'voucher-engine.html',
    'admin-staff.html',
    'admin-partner-password.html'
  ]);
  const commit = 'de89d3c8a3cbcafa48f0a58afdaa937c16d67aa9';
  const fail = (message) => {
    document.body.innerHTML = `<main style="max-width:720px;margin:40px auto;padding:20px;font-family:system-ui"><h1>Evolution Voucher UAT</h1><p>${message}</p><p>This temporary UAT harness does not modify the production portal.</p></main>`;
  };
  if (!allowed.has(page)) {
    fail('Invalid UAT page.');
    return;
  }
  const source = `https://raw.githubusercontent.com/evo-voucher/evolution-optical-voucher/${commit}/${page}`;
  fetch(source, { cache: 'no-store' })
    .then((response) => {
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      return response.text();
    })
    .then((html) => {
      document.open();
      document.write(html);
      document.close();
    })
    .catch(() => fail('Unable to load the pinned cutover build. Please retry later.'));
})();
