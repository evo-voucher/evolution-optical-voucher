(()=>{
  'use strict';
  const path=String(location.pathname||'').toLowerCase();
  const isPartner=path.endsWith('/partner.html');
  const isStaff=path.endsWith('/staff.html');
  if(!isPartner&&!isStaff)return;

  const escXml=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot',"'":'&apos;'}[c]));
  const escHtml=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const safeCell=v=>v==null?'':String(v).replace(/^([=+\-@])/,'\'$1');
  const dateTime=v=>v?new Date(v).toLocaleString('en-MY',{timeZone:'Asia/Kuala_Lumpur'}):'';
  const dateOnly=v=>v?String(v):'';
  const slug=v=>String(v||'export').replace(/[^a-z0-9_-]+/gi,'-').replace(/^-+|-+$/g,'').toLowerCase()||'export';

  function excelXml(sheetName,headers,rows){
    const cell=v=>`<Cell><Data ss:Type="String">${escXml(safeCell(v))}</Data></Cell>`;
    const row=values=>`<Row>${values.map(cell).join('')}</Row>`;
    return `<?xml version="1.0"?><?mso-application progid="Excel.Sheet"?><Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet"><Worksheet ss:Name="${escXml(sheetName.slice(0,31))}"><Table>${row(headers)}${rows.map(row).join('')}</Table></Worksheet></Workbook>`;
  }
  function downloadExcel(filename,sheetName,headers,rows){const blob=new Blob([excelXml(sheetName,headers,rows)],{type:'application/vnd.ms-excel;charset=utf-8'});const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=filename;document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1500);}
  function findSupabaseClient(){const sb=window.supabase,cfg=window.EVOLUTION_VOUCHER_BACKEND||{};if(!sb?.createClient||!cfg.supabaseUrl||!cfg.publishableKey)throw new Error('Export service unavailable.');return sb.createClient(cfg.supabaseUrl,cfg.publishableKey);}
  function button(label){const b=document.createElement('button');b.type='button';b.className='wide';b.textContent=label;return b;}
  function statusNode(){return document.createElement('div');}
  function show(node,text,ok=false){node.innerHTML=text?`<div class="msg ${ok?'ok':'err'}">${String(text).replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]))}</div>`:'';}

  async function districtGroupedRows(db,data){
    let master=[];try{const res=await db.rpc('customer_district_options',{});if(!res.error)master=res.data||[]}catch(_){}
    const order=new Map(master.map((d,i)=>[String(d.district_name||'').trim().toLowerCase(),i]));
    const sorted=[...(data||[])].sort((a,b)=>{
      const ad=String(a.customer_district||'').trim(),bd=String(b.customer_district||'').trim();
      const ai=order.has(ad.toLowerCase())?order.get(ad.toLowerCase()):100000;
      const bi=order.has(bd.toLowerCase())?order.get(bd.toLowerCase()):100000;
      if(ai!==bi)return ai-bi;if(ad!==bd)return ad.localeCompare(bd);return String(a.customer_name||'').localeCompare(String(b.customer_name||''));
    });
    const rows=[];let last=null;
    for(const r of sorted){const district=String(r.customer_district||'').trim()||'No District';if(district!==last){if(last!==null)rows.push(Array(14).fill(''));rows.push([`DISTRICT: ${district}`,...Array(13).fill('')]);last=district;}rows.push([district,r.voucher_code,r.customer_name,r.customer_phone,dateOnly(r.customer_birthday),r.voucher_type,r.voucher_status,dateOnly(r.expiry_date),dateTime(r.issued_at),r.issued_by_name,r.usage_count,r.usage_limit,dateTime(r.last_redeemed_at),r.last_branch_name]);}
    return rows;
  }

  async function installPartner(){
    const panel=document.getElementById('vouchersFile'),report=document.getElementById('voucherReport');if(!panel||!report||document.getElementById('exportPartnerExcelBtn'))return;
    const b=button('Export Excel');b.id='exportPartnerExcelBtn';const s=statusNode();s.id='partnerExportMsg';report.parentElement.append(b,s);
    b.onclick=async()=>{b.disabled=true;show(s,'');try{const db=findSupabaseClient(),picker=document.getElementById('adminPartnerSelect'),args=picker&&!picker.classList.contains('hidden')&&picker.value?{p_partner_id:picker.value}:{};const {data,error}=await db.rpc('partner_export_vouchers',args);if(error)throw error;if(!(data||[]).length)throw new Error('No Voucher records to export.');const rows=await districtGroupedRows(db,data);downloadExcel(`partner-vouchers-by-district-${new Date().toISOString().slice(0,10)}.xls`,'Vouchers by District',['District','Voucher Code','Customer Name','Customer Phone','Customer Birthday','Voucher Type','Status','Expiry Date','Issued At','Issued By','Usage Count','Usage Limit','Last Redeemed At','Last Branch'],rows);show(s,`${data.length} Voucher record(s) exported by District.`,true);}catch(e){show(s,e?.message||'Excel export failed.');}finally{b.disabled=false;}};
  }

  async function installStaff(){
    const history=document.getElementById('history');if(!history||document.getElementById('exportStaffExcelBtn'))return;const card=history.closest('.card');if(!card)return;const b=button('Export Branch Excel');b.id='exportStaffExcelBtn';const s=statusNode();s.id='staffExportMsg';card.append(b,s);
    b.onclick=async()=>{b.disabled=true;show(s,'');try{const db=findSupabaseClient(),branchSelect=document.getElementById('branchCode'),branch=branchSelect&&!branchSelect.closest('.hidden')?branchSelect.value:null;if(branchSelect&&!branchSelect.closest('.hidden')&&!branch)throw new Error('Select a branch before export.');const {data,error}=await db.rpc('staff_export_redemptions',{p_branch_code:branch||null});if(error)throw error;const rows=(data||[]).map(r=>[r.voucher_code,r.customer_name,r.voucher_type,r.partner_name,r.branch_name,r.branch_code,r.staff_name,r.redeem_method,r.redemption_status,dateTime(r.redeemed_at),r.notes]);if(!rows.length)throw new Error('No Redemption records to export.');const branchName=(data?.[0]?.branch_code)||branch||'permitted-scope';downloadExcel(`branch-redemptions-${slug(branchName)}-${new Date().toISOString().slice(0,10)}.xls`,'Redemptions',['Voucher Code','Customer Name','Voucher Type','Partner','Branch','Branch Code','Redeemed By','Method','Status','Redeemed At','Notes'],rows);show(s,`${rows.length} Redemption record(s) exported.`,true);}catch(e){show(s,e?.message||'Excel export failed.');}finally{b.disabled=false;}};
  }

  const install=()=>{if(isPartner)installPartner();if(isStaff)installStaff();};if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install,{once:true});else install();
})();