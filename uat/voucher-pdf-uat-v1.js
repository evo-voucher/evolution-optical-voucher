(() => {
  'use strict';

  const SCRIPT_ID = 'evolution-voucher-pdf-uat-v1';
  const ISSUE_RESULT_ID = 'issueResult';
  const PDF_BUTTON_ID = 'downloadVoucherPdfUat';
  const LIBRARIES = [
    {
      global: 'html2canvas',
      src: 'https://cdn.jsdelivr.net/npm/html2canvas@1.4.1/dist/html2canvas.min.js'
    },
    {
      global: 'jspdf',
      src: 'https://cdn.jsdelivr.net/npm/jspdf@2.5.1/dist/jspdf.umd.min.js'
    }
  ];

  function safeName(value) {
    return String(value || 'voucher')
      .trim()
      .replace(/[^a-z0-9._-]+/gi, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 80) || 'voucher';
  }

  function loadScriptOnce(globalName, src) {
    if (window[globalName]) return Promise.resolve();
    return new Promise((resolve, reject) => {
      const existing = document.querySelector(`script[data-pdf-lib="${globalName}"]`);
      if (existing) {
        existing.addEventListener('load', resolve, { once: true });
        existing.addEventListener('error', () => reject(new Error(`${globalName} failed to load`)), { once: true });
        return;
      }
      const script = document.createElement('script');
      script.src = src;
      script.async = true;
      script.dataset.pdfLib = globalName;
      script.onload = resolve;
      script.onerror = () => reject(new Error(`${globalName} failed to load`));
      document.head.appendChild(script);
    });
  }

  async function ensurePdfLibraries() {
    for (const lib of LIBRARIES) await loadScriptOnce(lib.global, lib.src);
    if (!window.html2canvas || !window.jspdf?.jsPDF) throw new Error('PDF libraries unavailable');
  }

  function getIssuedContext() {
    const root = document.getElementById(ISSUE_RESULT_ID);
    if (!root) return null;
    const link = root.querySelector('a.resultLink[href]');
    const qrNode = root.querySelector('#issuedQr img, #issuedQr canvas');
    if (!link || !qrNode) return null;
    const text = root.textContent || '';
    const codeMatch = text.match(/Code:\s*([^\n]+)/i);
    const code = codeMatch ? codeMatch[1].trim() : 'voucher';
    return { root, url: link.href, qrNode, code };
  }

  function qrDataUrl(node) {
    if (node.tagName === 'CANVAS') return node.toDataURL('image/png');
    if (node.tagName === 'IMG') return node.src;
    throw new Error('QR image unavailable');
  }

  function waitForVoucher(iframe, timeoutMs = 12000) {
    return new Promise((resolve, reject) => {
      const started = Date.now();
      const check = () => {
        try {
          const doc = iframe.contentDocument;
          const card = doc?.getElementById('voucherCard');
          const state = doc?.getElementById('voucherState');
          const errorState = doc?.getElementById('errorState');
          if (errorState && !errorState.classList.contains('hidden')) {
            reject(new Error('Customer voucher could not be loaded'));
            return;
          }
          if (card && state && !state.classList.contains('hidden')) {
            resolve(card);
            return;
          }
        } catch (_) {
          reject(new Error('Voucher preview is not same-origin'));
          return;
        }
        if (Date.now() - started > timeoutMs) {
          reject(new Error('Voucher preview timed out'));
          return;
        }
        setTimeout(check, 180);
      };
      iframe.addEventListener('load', check, { once: true });
      setTimeout(check, 250);
    });
  }

  async function makePdf(button) {
    const ctx = getIssuedContext();
    if (!ctx) throw new Error('Issued voucher is no longer available on this screen');

    button.disabled = true;
    const originalText = button.textContent;
    button.textContent = 'Preparing PDF…';

    let iframe;
    try {
      await ensurePdfLibraries();

      iframe = document.createElement('iframe');
      iframe.setAttribute('aria-hidden', 'true');
      iframe.style.position = 'fixed';
      iframe.style.left = '-10000px';
      iframe.style.top = '0';
      iframe.style.width = '760px';
      iframe.style.height = '1200px';
      iframe.style.opacity = '0';
      iframe.style.pointerEvents = 'none';
      document.body.appendChild(iframe);
      iframe.src = ctx.url;

      const card = await waitForVoucher(iframe);
      const canvas = await window.html2canvas(card, {
        scale: 2,
        useCORS: true,
        backgroundColor: null,
        logging: false
      });

      const { jsPDF } = window.jspdf;
      const pdf = new jsPDF({ orientation: 'portrait', unit: 'mm', format: 'a4', compress: true });
      const pageW = 210;
      const pageH = 297;
      const margin = 12;
      const qrSize = 44;
      const footerH = 58;
      const maxW = pageW - margin * 2;
      const maxH = pageH - margin * 2 - footerH;
      const ratio = Math.min(maxW / canvas.width, maxH / canvas.height);
      const drawW = canvas.width * ratio;
      const drawH = canvas.height * ratio;
      const x = (pageW - drawW) / 2;
      const y = margin;

      pdf.addImage(canvas.toDataURL('image/jpeg', 0.92), 'JPEG', x, y, drawW, drawH, undefined, 'FAST');

      const qrY = pageH - margin - qrSize;
      pdf.setDrawColor(220);
      pdf.roundedRect(margin, qrY - 5, pageW - margin * 2, qrSize + 5, 3, 3);
      pdf.addImage(qrDataUrl(ctx.qrNode), 'PNG', margin + 5, qrY, qrSize, qrSize, undefined, 'FAST');
      pdf.setFont('helvetica', 'bold');
      pdf.setFontSize(11);
      pdf.text('SCAN FOR CURRENT VOUCHER STATUS', margin + 55, qrY + 12);
      pdf.setFont('helvetica', 'normal');
      pdf.setFontSize(9);
      pdf.text('The QR opens the live Evolution Optical voucher record.', margin + 55, qrY + 20);
      pdf.text(`Voucher: ${ctx.code}`, margin + 55, qrY + 29);
      pdf.text('PDF is a copy of the voucher view; live system status remains authoritative.', margin + 55, qrY + 38, { maxWidth: 125 });

      pdf.save(`${safeName(ctx.code)}.pdf`);
    } finally {
      if (iframe?.parentNode) iframe.parentNode.removeChild(iframe);
      button.disabled = false;
      button.textContent = originalText;
    }
  }

  function installButton() {
    const ctx = getIssuedContext();
    if (!ctx || document.getElementById(PDF_BUTTON_ID)) return;

    const button = document.createElement('button');
    button.id = PDF_BUTTON_ID;
    button.type = 'button';
    button.textContent = 'Download PDF (UAT)';
    button.style.width = '100%';
    button.style.marginTop = '10px';
    button.style.minHeight = '42px';
    button.dataset.uatPdf = 'v1';
    button.addEventListener('click', async () => {
      try {
        await makePdf(button);
      } catch (error) {
        console.error('[UAT PDF V1]', error);
        alert(`PDF was not generated. Voucher issuance is unchanged.\n\n${error?.message || 'Unknown PDF error'}`);
      }
    });

    const share = ctx.root.querySelector('.shareLink');
    if (share?.parentNode) share.parentNode.insertBefore(button, share);
    else ctx.root.appendChild(button);
  }

  function watchIssueResult() {
    const root = document.getElementById(ISSUE_RESULT_ID);
    if (!root) return;
    const observer = new MutationObserver(() => installButton());
    observer.observe(root, { childList: true, subtree: true });
    installButton();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', watchIssueResult, { once: true });
  else watchIssueResult();

  window.__EVOLUTION_VOUCHER_PDF_UAT__ = { version: '1.0.0', scriptId: SCRIPT_ID };
})();
