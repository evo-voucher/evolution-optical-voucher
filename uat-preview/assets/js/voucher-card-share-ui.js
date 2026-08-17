// Evolution Voucher Card Share UI
// Partner-portal presentation module. It consumes the issued voucher's public token,
// fetches the canonical public voucher payload, renders a PNG, and exposes image actions.
(function(){
  'use strict';
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!path.endsWith('/partner.html'))return;

  const start=()=>{
    const cfg=window.EVOLUTION_VOUCHER_BACKEND||{};
    const renderer=window.EvolutionVoucherCard;
    const supabase=window.supabase;
    const root=document.getElementById('issueResult');
    if(!root||!renderer||!supabase?.createClient)return;

    if(!document.getElementById('voucherCardShareStyle')){
      const style=document.createElement('style');
      style.id='voucherCardShareStyle';
      style.textContent=`
        .voucherCardOutput{margin-top:14px;padding:14px;border-radius:18px;background:#0b1737;border:1px solid rgba(115,135,210,.34)}
        .voucherCardPreview{display:block;width:min(100%,520px);height:auto;margin:0 auto;border-radius:18px;background:#fff;box-shadow:0 18px 46px rgba(0,0,0,.28)}
        .voucherCardActions{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:9px;margin-top:13px}
        .voucherCardActions button{width:100%;min-height:44px}
        .voucherCardStatus{margin-top:9px;font-size:11px;color:#b9c7e8;text-align:center}
        @media(max-width:680px){.voucherCardActions{grid-template-columns:1fr}}
      `;
      document.head.appendChild(style);
    }

    const db=supabase.createClient(cfg.supabaseUrl,cfg.publishableKey);
    let activeObjectUrl=null;
    let renderSerial=0;

    function tokenFromResult(){
      const link=root.querySelector('a.resultLink[href*="voucher.html?v="]');
      if(!link)return null;
      try{return new URL(link.href,location.href).searchParams.get('v')}catch(_){return null}
    }
    function valueLabel(voucherType){
      const m=String(voucherType||'').match(/RM\s*([0-9]+(?:\.[0-9]+)?)/i);
      return m?`RM${m[1]}`:'VOUCHER';
    }
    function cleanupLegacyOutput(){
      root.querySelectorAll('.resultLink,.issuedQrWrap,.shareLink,.shareNote').forEach(el=>el.remove());
    }
    function status(node,message,isError=false){node.textContent=message||'';node.style.color=isError?'#ff9bad':'#b9c7e8'}

    async function enhance(){
      const token=tokenFromResult();
      if(!token||root.dataset.voucherCardToken===token)return;
      const serial=++renderSerial;
      root.dataset.voucherCardToken=token;
      const existing=root.querySelector('.voucherCardOutput');if(existing)existing.remove();

      const shell=document.createElement('div');shell.className='voucherCardOutput';
      shell.innerHTML='<div class="voucherCardStatus">Preparing voucher image…</div>';
      root.appendChild(shell);
      const statusNode=shell.querySelector('.voucherCardStatus');

      try{
        const{data,error}=await db.rpc('get_public_voucher',{p_token:token});
        if(serial!==renderSerial)return;
        if(error)throw error;
        if(!data?.success)throw new Error(data?.error||'Voucher data unavailable');
        const base=(cfg.siteBase||'').replace(/\/?$/,'/');
        const qrValue=`${base}voucher.html?v=${encodeURIComponent(token)}`;
        const rendered=await renderer.create({
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
        if(serial!==renderSerial){URL.revokeObjectURL(rendered.url);return}
        if(activeObjectUrl)URL.revokeObjectURL(activeObjectUrl);activeObjectUrl=rendered.url;
        cleanupLegacyOutput();
        shell.innerHTML='';
        const img=document.createElement('img');img.className='voucherCardPreview';img.alt=`Voucher ${data.voucher_code||''}`;img.src=rendered.url;shell.appendChild(img);
        const actions=document.createElement('div');actions.className='voucherCardActions';
        const copy=document.createElement('button');copy.type='button';copy.textContent='Copy Image';
        const share=document.createElement('button');share.type='button';share.textContent='Share Image';
        const download=document.createElement('button');download.type='button';download.textContent='Download Image';
        actions.append(copy,share,download);shell.appendChild(actions);
        const note=document.createElement('div');note.className='voucherCardStatus';note.textContent='Customer receives the voucher as an image. QR keeps the secure voucher link inside the card.';shell.appendChild(note);
        copy.addEventListener('click',async()=>{copy.disabled=true;try{await renderer.copy(rendered.blob);status(note,'Voucher image copied.',false)}catch(e){status(note,e.message||'Unable to copy image.',true)}finally{copy.disabled=false}});
        share.addEventListener('click',async()=>{share.disabled=true;try{await renderer.share(rendered.blob,rendered.filename);status(note,'Share sheet opened.',false)}catch(e){status(note,e.message||'Unable to share image.',true)}finally{share.disabled=false}});
        download.addEventListener('click',()=>{renderer.download(rendered.blob,rendered.filename);status(note,'Voucher image prepared for download.',false)});
      }catch(e){cleanupLegacyOutput();status(statusNode,e.message||'Voucher image generation failed.',true)}
    }

    const observer=new MutationObserver(()=>queueMicrotask(enhance));
    observer.observe(root,{childList:true,subtree:true});
    enhance();
  };

  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});
  else start();
})();