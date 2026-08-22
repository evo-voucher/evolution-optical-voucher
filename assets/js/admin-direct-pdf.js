(()=>{
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!path.endsWith('/experience/admin-v2.html'))return;

  const HTML2PDF_SRC='https://cdn.jsdelivr.net/npm/html2pdf.js@0.10.1/dist/html2pdf.bundle.min.js';
  let loaderPromise=null;

  function loadHtml2Pdf(){
    if(window.html2pdf)return Promise.resolve(window.html2pdf);
    if(loaderPromise)return loaderPromise;
    loaderPromise=new Promise((resolve,reject)=>{
      const s=document.createElement('script');
      s.src=HTML2PDF_SRC;
      s.async=true;
      s.onload=()=>window.html2pdf?resolve(window.html2pdf):reject(new Error('PDF engine unavailable'));
      s.onerror=()=>reject(new Error('Unable to load PDF engine'));
      document.head.appendChild(s);
    });
    return loaderPromise;
  }

  function safeFileName(){
    const month=document.getElementById('redemptionMonth')?.value||'';
    const range=document.getElementById('redemptionRange')?.value||'all';
    const suffix=month?`_${month}_${range==='all'?'all':range+'m'}`:'';
    return `Redemption_Report${suffix}.pdf`;
  }

  function buildPdfNode(){
    const panel=document.querySelector('#redemption .panelbox');
    if(!panel)throw new Error('Redemption report is not available');
    const clone=panel.cloneNode(true);
    clone.querySelectorAll('.filters,.reportactions,.paneltop button,.mobileCards').forEach(x=>x.remove());
    clone.querySelectorAll('.desktopTable').forEach(x=>x.style.display='block');
    clone.querySelectorAll('.tablewrap').forEach(x=>{x.style.overflow='visible';x.style.border='0';});
    clone.style.background='#fff';
    clone.style.color='#000';
    clone.style.border='0';
    clone.style.padding='14px';
    clone.style.width='760px';
    clone.querySelectorAll('table').forEach(x=>{x.style.color='#000';x.style.minWidth='0';});
    clone.querySelectorAll('th').forEach(x=>{x.style.background='#eee';x.style.color='#000';});
    clone.querySelectorAll('.monthHead,.issuerHead').forEach(x=>{x.style.background='#eee';x.style.color='#000';x.style.borderColor='#999';});
    clone.querySelectorAll('.monthHead span,.issuerHead span,.periodMeta,.reportsub').forEach(x=>x.style.color='#333');
    const wrap=document.createElement('div');
    wrap.style.position='fixed';
    wrap.style.left='-10000px';
    wrap.style.top='0';
    wrap.style.background='#fff';
    wrap.appendChild(clone);
    document.body.appendChild(wrap);
    return wrap;
  }

  async function deliverPdf(blob,fileName){
    const file=new File([blob],fileName,{type:'application/pdf'});
    if(navigator.share&&navigator.canShare&&navigator.canShare({files:[file]})){
      try{
        await navigator.share({files:[file],title:'Redemption Report'});
        return;
      }catch(e){
        if(e?.name==='AbortError')return;
      }
    }
    const url=URL.createObjectURL(blob);
    const a=document.createElement('a');
    a.href=url;
    a.download=fileName;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(()=>URL.revokeObjectURL(url),30000);
  }

  async function exportRedemptionPdf(){
    let wrap;
    try{
      const html2pdf=await loadHtml2Pdf();
      wrap=buildPdfNode();
      const blob=await html2pdf().set({
        margin:[8,8,8,8],
        filename:safeFileName(),
        image:{type:'jpeg',quality:0.98},
        html2canvas:{scale:2,useCORS:true,backgroundColor:'#ffffff'},
        jsPDF:{unit:'mm',format:'a4',orientation:'portrait'},
        pagebreak:{mode:['css','legacy'],avoid:['.monthHead','.issuerHead','tr']}
      }).from(wrap.firstElementChild).outputPdf('blob');
      await deliverPdf(blob,safeFileName());
    }catch(e){
      console.error('Direct PDF export failed',e);
      alert('PDF export failed. Please try again.');
    }finally{
      wrap?.remove();
    }
  }

  const install=()=>{
    const original=window.printReport;
    if(typeof original!=='function')return;
    window.printReport=id=>id==='redemption'?exportRedemptionPdf():original(id);
  };

  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install,{once:true});else install();
})();
