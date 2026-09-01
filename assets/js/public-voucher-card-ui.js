// Public Voucher Card UI
// Presentation-only enhancement for voucher.html. Reuses the canonical issued-voucher
// payload and existing Voucher Card renderer; it never mutates Voucher state.
(function(){
  'use strict';
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!path.endsWith('/voucher.html'))return;

  function recoverToken(){
    const direct=String(window.__EVOLUTION_PUBLIC_VOUCHER_TOKEN||'').trim();
    if(direct)return direct;
    try{
      const current=new URL(location.href).searchParams.get('v');
      if(current)return String(current).trim();
    }catch(_){}
    try{
      const nav=performance.getEntriesByType?.('navigation')?.[0]?.name;
      const original=nav?new URL(nav).searchParams.get('v'):'';
      if(original)return String(original).trim();
    }catch(_){}
    return '';
  }

  const token=recoverToken();
  if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(token))return;

  const cfg=window.EVOLUTION_VOUCHER_BACKEND||{};
  const version=window.EVOLUTION_ASSET_VERSION||'';
  const asset=path=>`${path}${version?`?v=${encodeURIComponent(version)}`:''}`;

  function loadScript(id,src,test){
    return new Promise((resolve,reject)=>{
      if(test?.()){resolve();return;}
      const existing=document.getElementById(id);
      if(existing){
        if(test?.()){resolve();return;}
        existing.addEventListener('load',()=>resolve(),{once:true});
        existing.addEventListener('error',()=>reject(new Error(`Unable to load ${id}`)),{once:true});
        return;
      }
      const script=document.createElement('script');script.id=id;script.src=src;
      script.onload=()=>resolve();script.onerror=()=>reject(new Error(`Unable to load ${id}`));
      document.head.appendChild(script);
    });
  }

  function valueLabel(voucherType){
    const matches=[...String(voucherType||'').matchAll(/RM\s*([0-9]+(?:\.[0-9]+)?)/ig)].map(m=>m[1]);
    return matches.length?`RM${matches[0]}`:'VOUCHER';
  }

  function installStyle(){
    if(document.getElementById('publicVoucherCardStyle'))return;
    const style=document.createElement('style');style.id='publicVoucherCardStyle';
    style.textContent='.publicVoucherCardShell{margin:0 0 18px}.publicVoucherCardImage{display:block;width:100%;height:auto;border-radius:20px;background:#fff;box-shadow:0 16px 44px rgba(0,0,0,.3)}.publicVoucherCardNote{margin-top:8px;color:#91a2c4;font-size:11px;text-align:center}.publicVoucherCardError{margin:10px 0;padding:10px 12px;border-radius:12px;border:1px solid rgba(255,146,165,.45);color:#ffb2c0;font-size:11px}';
    document.head.appendChild(style);
  }

  async function start(){
    try{
      await loadScript('publicVoucherQrLibrary','https://cdn.jsdelivr.net/npm/qrcodejs@1.0.0/qrcode.min.js',()=>typeof window.QRCode==='function');
      await loadScript('publicVoucherCardRenderer',asset('assets/js/voucher-card-renderer.js'),()=>!!window.EvolutionVoucherCard);
      if(!window.supabase?.createClient||!window.EvolutionVoucherCard)return;

      const voucherState=document.getElementById('voucherState');
      if(!voucherState)return;
      const db=window.supabase.createClient(cfg.supabaseUrl,cfg.publishableKey,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
      const{data,error}=await db.rpc('get_public_voucher',{p_token:token});
      if(error||!data?.success)throw error||new Error(data?.error||'Voucher unavailable');

      const base=String(cfg.siteBase||'').replace(/\/?$/,'/');
      const qrValue=`${base}voucher.html?v=${encodeURIComponent(token)}`;
      const rendered=await window.EvolutionVoucherCard.create({
        partner_name:data.partner_name,
        customer_name:data.customer_name,
        voucher_code:data.voucher_code,
        voucher_type:data.voucher_type,
        value_label:valueLabel(data.voucher_type),
        expiry_date:data.expiry_date,
        branches:Array.isArray(data.branches)?data.branches:[],
        theme_code:data.theme_code,
        theme_config:data.theme_config,
        qr_value:qrValue
      });

      installStyle();
      let shell=document.getElementById('publicVoucherCardShell');
      if(!shell){shell=document.createElement('section');shell.id='publicVoucherCardShell';shell.className='publicVoucherCardShell';voucherState.insertBefore(shell,voucherState.firstChild);}
      shell.innerHTML='';
      const img=document.createElement('img');
      img.className='publicVoucherCardImage';
      img.alt=`Voucher ${data.voucher_code||''}`;
      img.src=rendered.canvas.toDataURL('image/png');
      shell.appendChild(img);
      if(rendered.url)URL.revokeObjectURL(rendered.url);
      const note=document.createElement('div');note.className='publicVoucherCardNote';note.textContent='Scan the QR on this Voucher at the counter for verification.';shell.appendChild(note);

      const duplicateTheme=document.getElementById('voucherThemeExperience');
      if(duplicateTheme)duplicateTheme.classList.add('hidden');
    }catch(error){
      const voucherState=document.getElementById('voucherState');if(!voucherState)return;
      installStyle();
      let box=document.getElementById('publicVoucherCardError');
      if(!box){box=document.createElement('div');box.id='publicVoucherCardError';box.className='publicVoucherCardError';voucherState.insertBefore(box,voucherState.firstChild);}
      box.textContent='Voucher card preview is unavailable. Voucher details below remain valid.';
    }
  }

  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();
