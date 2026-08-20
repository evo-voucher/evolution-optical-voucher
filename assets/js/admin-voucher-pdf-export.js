(()=>{
  'use strict';
  const path=String(location.pathname||'').toLowerCase();
  if(!path.endsWith('/admin.html'))return;

  const JSPDF_SRC='https://cdn.jsdelivr.net/npm/jspdf@2.5.1/dist/jspdf.umd.min.js';
  const HTML2CANVAS_SRC='https://cdn.jsdelivr.net/npm/html2canvas@1.4.1/dist/html2canvas.min.js';
  const PAGE_ROW_LIMIT=12;

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
    page.className='evo-pdf-render-page';
    page.setAttribute('aria-hidden','true');
    Object.assign(page.style,{
      position:'fixed',left:'-12000px',top:'0',width:'1500px',padding:'42px 46px 32px',
      background:'#ffffff',color:'#000000',fontFamily:'Arial, Helvetica, sans-serif',zIndex:'-1'
    });

    const isolation=document.createElement('style');
    isolation.textContent=`
      .evo-pdf-render-page{background:#fff!important;color:#000!important;color-scheme:light!important}
      .evo-pdf-render-page table{background:#fff!important;color:#000!important}
      .evo-pdf-render-page thead,.evo-pdf-render-page tbody,.evo-pdf-render-page tr{background:transparent!important;color:#000!important}
      .evo-pdf-render-page th{background:#0f1b3f!important;color:#fff!important;-webkit-text-fill-color:#fff!important;border-color:#334155!important}
      .evo-pdf-render-page td{color:#000!important;-webkit-text-fill-color:#000!important;border-color:#64748b!important;font-weight:900!important;text-shadow:none!important}
      .evo-pdf-render-page tbody tr:nth-child(odd) td{background:#eef2f6!important}
      .evo-pdf-render-page tbody tr:nth-child(even) td{background:#dbe1e8!important}
      .evo-pdf-render-page div{color:#000!important;-webkit-text-fill-color:#000!important}
    `;
    page.appendChild(isolation);

    const title=document.createElement('div');
    title.innerHTML=`<div style="font-size:38px;font-weight:900;letter-spacing:.2px;color:#000000">Evolution Optical - Voucher Report</div>
      <div style="margin-top:10px;font-size:20px;font-weight:800;color:#000000">${escapeHtml(filterSummary())}</div>
      <div style="margin-top:7px;font-size:17px;font-weight:800;color:#000000">Generated: ${escapeHtml(new Date().toLocaleString())} &nbsp; | &nbsp; Page ${pageNo} of ${totalPages}</div>`;
    page.appendChild(title);

    const table=document.createElement('table');
    table.style.cssText='width:100%;border-collapse:collapse;table-layout:fixed;margin-top:26px;font-size:19px;color:#000000;background:#fff;';
    const thead=document.createElement('thead');
    const hr=document.createElement('tr');
    headers.forEach(text=>{
      const th=document.createElement('th');
      th.textContent=text;
      th.style.cssText='padding:16px 12px;border:3px solid #334155;background:#0f1b3f;color:#ffffff;text-align:left;font-size:18px;font-weight:900;line-height:1.25;word-break:break-word;';
      hr.appendChild(th);
    });
    thead.appendChild(hr);table.appendChild(thead);

    const tbody=document.createElement('tbody');
    rows.forEach((row,index)=>{
      const tr=document.createElement('tr');
      tr.style.minHeight='78px';
      row.forEach(text=>{
        const td=document.createElement('td');
        td.textContent=text||'—';
        td.style.cssText=`padding:20px 12px;border:3px solid #64748b;vertical-align:middle;line-height:1.35;word-break:break-word;color:#000000;font-size:19px;font-weight:900;background:${index%2?'#dbe1e8':'#eef2f6'};min-height:78px;`;
        tr.appendChild(td);
      });
      tbody.appendChild(tr);
    });
    table.appendChild(tbody);page.appendChild(table);

    const footer=document.createElement('div');
    footer.textContent='Evolution Optical - Confidential Admin Report';
    footer.style.cssText='margin-top:18px;font-size:15px;font-weight:800;color:#000000;text-align:right;';
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
      const marginX=8;
      const marginTop=8;
      const maxW=pageWidth-marginX*2;
      const maxH=pageHeight-marginTop-8;

      for(let i=0;i<chunks.length;i++){
        if(i>0)pdf.addPage('a4','landscape');
        const renderPage=buildRenderPage(data.headers,chunks[i],i+1,chunks.length);
        document.body.appendChild(renderPage);
        const canvas=await window.html2canvas(renderPage,{backgroundColor:'#ffffff',scale:1.75,logging:false,useCORS:true});
        renderPage.remove();

        const widthScale=maxW/canvas.width;
        const heightScale=maxH/canvas.height;
        const scale=Math.min(widthScale,heightScale);
        const w=canvas.width*scale;
        const h=canvas.height*scale;
        const x=(pageWidth-w)/2;
        const y=marginTop;
        pdf.addImage(canvas.toDataURL('image/png'),'PNG',x,y,w,h,undefined,'FAST');
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