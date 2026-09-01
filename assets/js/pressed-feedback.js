(()=>{
  if(window.__evoPressedFeedbackInstalled)return;
  window.__evoPressedFeedbackInstalled=true;
  const selector='button,.btn,.tool,a.card,.moduleBtn,.listToggle,.directoryToggle,.reportCardBtn,.shareLink,.tile,.refresh';
  const style=document.createElement('style');
  style.id='evoPressedFeedbackStyle';
  style.textContent=`
    ${selector}{touch-action:manipulation;-webkit-tap-highlight-color:transparent;-webkit-user-select:none;user-select:none;will-change:transform,filter}
    ${selector}.evo-pressed{transform:translateY(2px) scale(.972)!important;filter:brightness(1.16)!important;box-shadow:0 1px 2px rgba(0,0,0,.16)!important}
  `;
  document.head.appendChild(style);
  let active=null;
  const release=()=>{if(active){active.classList.remove('evo-pressed');active=null;}};
  const press=e=>{
    const el=e.target?.closest?.(selector);
    if(!el||el.matches(':disabled,[aria-disabled="true"]'))return;
    release();active=el;el.classList.add('evo-pressed');
  };
  document.addEventListener('pointerdown',press,{passive:true,capture:true});
  document.addEventListener('pointerup',release,{passive:true,capture:true});
  document.addEventListener('pointercancel',release,{passive:true,capture:true});
  document.addEventListener('pointerleave',e=>{if(active&&e.target===active)release();},{passive:true,capture:true});
  window.addEventListener('blur',release,{passive:true});
})();

(()=>{
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!path.endsWith('/voucher-engine.html')&&!path.endsWith('/voucher.html'))return;
  if(document.getElementById('voucherThemeIntegrationScript'))return;
  const script=document.createElement('script');
  script.id='voucherThemeIntegrationScript';
  const version=window.EVOLUTION_ASSET_VERSION||'';
  script.src=`assets/js/voucher-theme-integration.js${version?`?v=${encodeURIComponent(version)}`:''}`;
  document.head.appendChild(script);
})();

(()=>{
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!path.endsWith('/voucher.html'))return;
  if(document.getElementById('publicVoucherCardUiScript'))return;
  const script=document.createElement('script');
  script.id='publicVoucherCardUiScript';
  const version=window.EVOLUTION_ASSET_VERSION||'';
  script.src=`assets/js/public-voucher-card-ui.js${version?`?v=${encodeURIComponent(version)}`:''}`;
  document.head.appendChild(script);
})();
