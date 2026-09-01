(function(){
  const path=String(window.location?.pathname||'').toLowerCase();
  const isEngine=path.endsWith('/voucher-engine.html');
  const isVoucher=path.endsWith('/voucher.html');
  if(!isEngine&&!isVoucher)return;

  function ensureThemeLibrary(done){
    if(window.EOVoucherThemes){done(window.EOVoucherThemes);return;}
    const existing=document.getElementById('voucherThemeSystemV1');
    if(existing){existing.addEventListener('load',()=>done(window.EOVoucherThemes),{once:true});return;}
    const script=document.createElement('script');
    script.id='voucherThemeSystemV1';
    const version=window.EVOLUTION_ASSET_VERSION||'';
    script.src=`voucher-theme-system-v1.js${version?`?v=${encodeURIComponent(version)}`:''}`;
    script.onload=()=>done(window.EOVoucherThemes);
    document.head.appendChild(script);
  }

  function installEngineThemeOptions(api){
    const applyOptions=()=>{
      const options=api.options();
      for(const id of ['templateTheme','versionTheme']){
        const select=document.getElementById(id);if(!select)continue;
        const current=select.value||'classic';
        select.replaceChildren(...options.map(({code,label})=>{const o=document.createElement('option');o.value=code;o.textContent=label;return o;}));
        select.value=options.some(o=>o.code===api.normalize(current))?api.normalize(current):'classic';
      }
    };
    if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',applyOptions,{once:true});else applyOptions();
  }

  function installPublicThemeRenderer(api){
    const install=()=>{
      const card=document.getElementById('voucherCard');
      const voucherState=document.getElementById('voucherState');
      if(!card||!voucherState)return;
      if(!document.getElementById('voucherThemeIntegrationStyle')){
        const style=document.createElement('style');
        style.id='voucherThemeIntegrationStyle';
        style.textContent='.voucher-theme-experience{margin:14px 0;padding:18px;border-radius:18px;background:var(--voucher-offer-bg);color:#fff;overflow:hidden}.voucher-theme-experience .av-gift-text{font:700 26px/1.2 Georgia,serif}.voucher-theme-experience .av-theme-decoration{margin-top:10px;max-width:260px}.voucher-theme-experience .av-theme-decoration svg{display:block;width:100%;height:auto}.voucher-theme-chip{display:inline-block;margin-bottom:8px;padding:4px 8px;border-radius:999px;background:rgba(255,255,255,.16);font-size:10px;font-weight:900;letter-spacing:.8px;text-transform:uppercase}';
        document.head.appendChild(style);
      }
      let panel=document.getElementById('voucherThemeExperience');
      if(!panel){
        panel=document.createElement('section');panel.id='voucherThemeExperience';panel.className='voucher-theme-experience';
        panel.innerHTML='<div class="voucher-theme-chip"></div><div class="av-gift-text">A little gift just for you</div><div class="av-theme-decoration"></div>';
        voucherState.insertBefore(panel,voucherState.firstChild);
      }
      const apply=()=>{
        const code=api.normalize(card.dataset.theme||'classic');
        const theme=api.applyToVoucher(panel,code);
        const chip=panel.querySelector('.voucher-theme-chip');if(chip)chip.textContent=theme?.label||code;
      };
      const observer=new MutationObserver(apply);observer.observe(card,{attributes:true,attributeFilter:['data-theme']});
      apply();
    };
    if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install,{once:true});else install();
  }

  ensureThemeLibrary(api=>{
    if(!api)return;
    if(isEngine)installEngineThemeOptions(api);
    if(isVoucher)installPublicThemeRenderer(api);
  });
})();
