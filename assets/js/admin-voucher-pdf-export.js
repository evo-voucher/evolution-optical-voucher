(()=>{
  'use strict';
  const path=String(location.pathname||'').toLowerCase();
  if(!path.endsWith('/admin.html'))return;

  const JSPDF_SRC='https://cdn.jsdelivr.net/npm/jspdf@2.5.1/dist/jspdf.umd.min.js';
  const HTML2CANVAS_SRC='https://cdn.jsdelivr.net/npm/html2canvas@1.4.1/dist/html2canvas.min.js';
  const PAGE_ROW_LIMIT=18;

  function loadScript(id,src,test){
    if(test())return Promise.resolve();
    const existing=document.getElementById(id);
    if(existing){
      return new Promise((resolve,reject)=>{
        if(test())return resolve();
        existing.addEventListener('load',()=>test()?resolve():reject(new Error('PDF library failed to initialise.')),{once:true});
        existing.addEventListener('error',()=>reject(new Error('PDF library failed to load.')),{once:true});
      });
    }
    return new Promise((resolve,reject)=>{
      const script=document.createElement('script');
      script.id=id;script.src=src;script.async=true;
      script.onload=()=>test()?resolve():reject(new Error('PDF library failed to initialise.'));
      script.onerror=()=>reject(new Error('PDF library failed to load.'));
      document.head.appendChild(script);
    });
  }

  async function ensurePdfLibraries(){
    await loadScript('evoJsPdfLibrary',JSPDF_SRC,()=>!!window.jspdf?.jsPDF);
    await loadScript('evoHtml2CanvasLibrary',HTML2CANVAS_SRC,()=>typeof window.html2canvas==='function');
  }

  function voucherCard(){
    const dashboard=document.getElementById('dashboardState');
    if(!dashboard)return null;
    return [...dashboard.querySelectorAll('.card')].find(card=>(card.querySelector('h2')?.textContent||'').trim()==='Voucher Report')||null;
  }

  function readVisibleVoucherTable(){
    const card=voucherCard();
    const table=card?.querySelector('#voucherReport table.list');
    if(!table)return null;
    const headers=[...table.querySelectorAll('thead th')].map(th=>(th.textContent||'').trim());
    const rows=[...table.querySelectorAll('tbody tr')].map(tr=>[...tr.querySelectorAll('td')].map(td=>(td.textContent||'').trim()));
    return headers.length&&rows.length?{headers,rows}:null;
  }

  function filterSummary(){
    const q=(document.getElementById('voucherSearch')?.value||'').trim();
    const status=document.getElementById('voucherStatus');
    const partner=document.getElementById('voucherPartner');
    const parts=[];
    if(q)parts.push(`Search: ${q}`);
    if(status?.value)parts.push(`Status: ${status.options[status.selectedIndex]?.textContent||status.value}`);
    if(partner?.value)parts.push(`Partner: ${partner.options[partner.selectedIndex]?.textContent||partner.value}`);
    return parts.length?parts.join(' | '):'All current Voucher Report records';
  }

  function buildRenderPage(headers,rows,pageNo,totalPages){
    const page=document.createElement('section');
    page.setAttribute('aria-hidden','true');
    Object.assign(page.style,{
      position:'fixed',left:'-10000px',top:'0',width:'1200px',padding:'30px 34px',
      background:'#ffffff',color:'#111827',fontFamily:'Arial, Helvetica, sans-serif',zIndex:'-1'
    });

    const title=document.createElement('div');
    title.innerHTML=`<div style="font-size:26px;font-weight:800;letter-spacing:.4px">Evolution Optical - Voucher Report</div>
      <div style="margin-top:6px;font-size:13px;color:#4b5563">${escapeHtml(filterSummary())}</div>
      <div style="margin-top:4px;font-size:12px;color:#6b7280">Generated: ${escapeHtml(new Date().toLocaleString())} | Page ${pageNo} of ${totalPages}</div>`;
    page.appendChild(title);

    const table=document.createElement('table');
    table.style.cssText='width:100%;border-collapse:collapse;table-layout:fixed;margin-top:18px;font-size:12px;';
    const thead=document.createElement('thead');
    const hr=document.createElement('tr');
    headers.forEach(text=>{
      const th=document.createElement('th');
      th.textContent=text;
      th.style.cssText='padding:9px 7px;border:1px solid #cbd5e1;background:#e5e7eb;color:#111827;text-align:left;font-size:11px;word-break:break-word;';
      hr.appendChild(th);
    });
    thead.appendChild(hr);table.appendChild(thead);

    const tbody=document.createElement('tbody');
    rows.forEach((row,index)=>{
      const tr=document.createElement('tr');
      row.forEach(text=>{
        const td=document.createElement('td');
        td.textContent=text;
        td.style.cssText=`padding:8px 7px;border:1px solid #d1d5db;vertical-align:top;line-height:1.28;word-break:break-word;background:${index%2?'#f8fafc':'#ffffff'};`;
        tr.appendChild(td);
      });
      tbody.appendChild(tr);
    });
    table.appendChild(tbody);page.appendChild(table);

    const footer=document.createElement('div');
    footer.textContent='Evolution Optical - Confidential Admin Report';
    footer.style.cssText='margin-top:12px;font-size:10px;color:#6b7280;text-align:right;';
    page.appendChild(footer);
    return page;
  }

  function escapeHtml(value){
    return String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  }

  async function exportVoucherPdf(){
    const button=document.getElementById('exportVouchersPdf');
    const oldLabel=button?.textContent||'Export PDF';
    try{
      const data=readVisibleVoucherTable();
      if(!data){alert('No Voucher Report records to export.');return;}
      if(button){button.disabled=true;button.textContent='Generating PDF...';}
      await ensurePdfLibraries();

      const chunks=[];
      for(let i=0;i<data.rows.length;i+=PAGE_ROW_LIMIT)chunks.push(data.rows.slice(i,i+PAGE_ROW_LIMIT));
      const {jsPDF}=window.jspdf;
      const pdf=new jsPDF({orientation:'landscape',unit:'mm',format:'a4',compress:true});
      const pageWidth=pdf.internal.pageSize.getWidth();
      const pageHeight=pdf.internal.pageSize.getHeight();
      const margin=6;

      for(let i=0;i<chunks.length;i++){
        if(i>0)pdf.addPage('a4','landscape');
        const renderPage=buildRenderPage(data.headers,chunks[i],i+1,chunks.length);
        document.body.appendChild(renderPage);
        const canvas=await window.html2canvas(renderPage,{backgroundColor:'#ffffff',scale:1.25,logging:false,useCORS:true});
        renderPage.remove();
        const maxW=pageWidth-margin*2,maxH=pageHeight-margin*2;
        const scale=Math.min(maxW/canvas.width,maxH/canvas.height);
        const w=canvas.width*scale,h=canvas.height*scale;
        const x=(pageWidth-w)/2,y=(pageHeight-h)/2;
        pdf.addImage(canvas.toDataURL('image/jpeg',0.88),'JPEG',x,y,w,h,undefined,'FAST');
        await new Promise(resolve=>setTimeout(resolve,0));
      }

      const stamp=new Date().toISOString().slice(0,10);
      pdf.save(`evolution-voucher-report-${stamp}.pdf`);
    }catch(error){
      console.error('Voucher PDF export failed',error);
      alert(error?.message||'Unable to export PDF.');
    }finally{
      if(button){button.disabled=false;button.textContent=oldLabel;}
    }
  }

  function install(){
    if(document.getElementById('exportVouchersPdf'))return true;
    const xlsx=document.getElementById('exportVouchers');
    if(!xlsx)return false;
    let actions=xlsx.parentElement;
    if(!actions?.classList.contains('evo-voucher-export-actions')){
      actions=document.createElement('div');
      actions.className='evo-voucher-export-actions';
      actions.style.cssText='display:flex;gap:8px;flex-wrap:wrap;align-items:stretch;';
      xlsx.parentNode.insertBefore(actions,xlsx);
      actions.appendChild(xlsx);
    }
    const pdf=document.createElement('button');
    pdf.id='exportVouchersPdf';pdf.type='button';pdf.textContent='Export PDF';
    pdf.onclick=exportVoucherPdf;
    actions.appendChild(pdf);
    return true;
  }

  if(install())return;
  let tries=0;
  const timer=setInterval(()=>{tries++;if(install()||tries>240)clearInterval(timer)},250);
})();