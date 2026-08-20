(()=>{
  'use strict';
  const path=String(location.pathname||'').toLowerCase();
  if(!path.endsWith('/admin.html'))return;

  const JSPDF_SRC='https://cdn.jsdelivr.net/npm/jspdf@2.5.1/dist/jspdf.umd.min.js';
  const PAGE_ROW_LIMIT=8;
  const CANVAS_W=2800;
  const CANVAS_H=1980;
  const MARGIN_X=80;
  const COL_WIDTHS=[420,330,300,260,220,250,430,430];

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

  function voucherCard(){
    const dashboard=document.getElementById('dashboardState');
    if(!dashboard)return null;
    return [...dashboard.querySelectorAll('.card')].find(card=>(card.querySelector('h2')?.textContent||'').trim()==='Voucher Report')||null;
  }

  function readVisibleVoucherTable(){
    const table=voucherCard()?.querySelector('#voucherReport table.list');
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

  function wrapText(ctx,value,maxWidth){
    const text=String(value||'—');
    const lines=[];
    let current='';
    for(const ch of text){
      const candidate=current+ch;
      if(current&&ctx.measureText(candidate).width>maxWidth){lines.push(current);current=ch;}
      else current=candidate;
    }
    if(current)lines.push(current);
    return lines.length?lines:['—'];
  }

  function rowHeight(ctx,row){
    ctx.font='700 28px Arial, Helvetica, sans-serif';
    let maxLines=1;
    row.forEach((value,i)=>{maxLines=Math.max(maxLines,wrapText(ctx,value,COL_WIDTHS[i]-30).length)});
    return Math.max(120,maxLines*38+42);
  }

  function drawPage(headers,rows,pageNo,totalPages){
    const canvas=document.createElement('canvas');
    canvas.width=CANVAS_W;canvas.height=CANVAS_H;
    const ctx=canvas.getContext('2d');
    ctx.fillStyle='#ffffff';ctx.fillRect(0,0,CANVAS_W,CANVAS_H);
    ctx.textBaseline='top';

    ctx.fillStyle='#000000';ctx.font='900 58px Arial, Helvetica, sans-serif';
    ctx.fillText('Evolution Optical - Voucher Report',MARGIN_X,70);
    ctx.font='800 32px Arial, Helvetica, sans-serif';
    ctx.fillText(filterSummary(),MARGIN_X,150);
    ctx.font='700 27px Arial, Helvetica, sans-serif';
    ctx.fillText(`Generated: ${new Date().toLocaleString()}  |  Page ${pageNo} of ${totalPages}`,MARGIN_X,202);

    let y=290,x=MARGIN_X;
    const headerH=92;
    headers.forEach((label,i)=>{
      const w=COL_WIDTHS[i];
      ctx.fillStyle='#0f1b3f';ctx.fillRect(x,y,w,headerH);
      ctx.strokeStyle='#334155';ctx.lineWidth=4;ctx.strokeRect(x,y,w,headerH);
      ctx.fillStyle='#ffffff';ctx.font='900 30px Arial, Helvetica, sans-serif';
      const lines=wrapText(ctx,label,w-28).slice(0,2);
      lines.forEach((line,j)=>ctx.fillText(line,x+14,y+22+j*34));
      x+=w;
    });
    y+=headerH;

    rows.forEach((row,rowIndex)=>{
      const h=rowHeight(ctx,row);x=MARGIN_X;
      row.forEach((value,i)=>{
        const w=COL_WIDTHS[i];
        ctx.fillStyle=rowIndex%2===0?'#f3f4f6':'#dfe4ea';ctx.fillRect(x,y,w,h);
        ctx.strokeStyle='#475569';ctx.lineWidth=4;ctx.strokeRect(x,y,w,h);
        ctx.fillStyle='#000000';ctx.font='700 28px Arial, Helvetica, sans-serif';
        const lines=wrapText(ctx,value,w-30);
        lines.forEach((line,j)=>ctx.fillText(line,x+15,y+22+j*38));
        x+=w;
      });
      y+=h;
    });

    ctx.fillStyle='#000000';ctx.font='700 22px Arial, Helvetica, sans-serif';ctx.textAlign='right';
    ctx.fillText('Evolution Optical - Confidential Admin Report',CANVAS_W-MARGIN_X,CANVAS_H-55);
    ctx.textAlign='left';
    return canvas;
  }

  async function exportVoucherPdf(){
    const button=document.getElementById('exportVouchersPdf');
    const oldLabel=button?.textContent||'Export PDF';
    try{
      const data=readVisibleVoucherTable();
      if(!data){alert('No Voucher Report records to export.');return;}
      if(button){button.disabled=true;button.textContent='Generating PDF...';}
      await loadScript('evoJsPdfLibrary',JSPDF_SRC,()=>!!window.jspdf?.jsPDF);

      const chunks=[];
      for(let i=0;i<data.rows.length;i+=PAGE_ROW_LIMIT)chunks.push(data.rows.slice(i,i+PAGE_ROW_LIMIT));
      const {jsPDF}=window.jspdf;
      const pdf=new jsPDF({orientation:'landscape',unit:'mm',format:'a4',compress:true});
      const pageW=pdf.internal.pageSize.getWidth(),pageH=pdf.internal.pageSize.getHeight();

      chunks.forEach((rows,i)=>{
        if(i>0)pdf.addPage('a4','landscape');
        const canvas=drawPage(data.headers,rows,i+1,chunks.length);
        pdf.addImage(canvas.toDataURL('image/png'),'PNG',5,5,pageW-10,pageH-10,undefined,'FAST');
      });

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
      actions=document.createElement('div');actions.className='evo-voucher-export-actions';
      actions.style.cssText='display:flex;gap:8px;flex-wrap:wrap;align-items:stretch;';
      xlsx.parentNode.insertBefore(actions,xlsx);actions.appendChild(xlsx);
    }
    const pdf=document.createElement('button');pdf.id='exportVouchersPdf';pdf.type='button';pdf.textContent='Export PDF';pdf.onclick=exportVoucherPdf;actions.appendChild(pdf);
    return true;
  }

  if(install())return;
  let tries=0;const timer=setInterval(()=>{tries++;if(install()||tries>240)clearInterval(timer)},250);
})();