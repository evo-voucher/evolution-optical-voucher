// Voucher Reports V3: branch-driven compact drill-down for Admin V2.
// Active branches come from admin_branch_directory. Existing report RPCs and exports remain unchanged.
(function(){
  'use strict';
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!path.endsWith('/experience/admin-v2.html'))return;

  const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const cfg=window.EVOLUTION_VOUCHER_BACKEND||{};
  const db=(cfg.enabled&&cfg.supabaseUrl&&cfg.publishableKey&&window.supabase)?window.supabase.createClient(cfg.supabaseUrl,cfg.publishableKey):null;
  let branchRows=[];
  let redemptionRows=[];
  let metadataReady=false;

  const style=document.createElement('style');
  style.id='voucherReportHierarchyV2Style';
  style.textContent=`
    #voucherTable.voucherHierarchyHost{overflow:visible;border:0;background:transparent}
    .voucherHierarchy{margin-top:12px;display:grid;gap:10px}
    .voucherPartnerGroup,.voucherDateGroup,.voucherItemV2{border:0;margin:0}
    .voucherPartnerGroup>summary,.voucherDateGroup>summary,.voucherItemV2>summary{list-style:none}
    .voucherPartnerGroup>summary::-webkit-details-marker,.voucherDateGroup>summary::-webkit-details-marker,.voucherItemV2>summary::-webkit-details-marker{display:none}
    .bronzeBranchBtn{display:flex;align-items:center;gap:11px;width:100%;padding:13px 14px;border:1px solid #c08a50;border-radius:14px;background:linear-gradient(145deg,#6f4324 0%,#a86e37 42%,#d3a369 100%);box-shadow:0 8px 22px rgba(0,0,0,.24),inset 0 1px 0 rgba(255,255,255,.22);color:#fff;cursor:pointer}
    .bronzeBranchBtn.empty{filter:saturate(.72);opacity:.86}
    .bronzeBranchBtn.pending{background:linear-gradient(145deg,#46392f 0%,#6d5949 45%,#8e735d 100%);border-color:#8e735d}
    .bronzeMark{width:38px;height:38px;border-radius:11px;display:grid;place-items:center;background:rgba(20,11,5,.35);border:1px solid rgba(255,255,255,.24);font-size:11px;font-weight:1000;letter-spacing:.08em;flex:0 0 auto}
    .bronzeText{min-width:0;flex:1;text-align:left}.bronzeText b{display:block;font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.bronzeText small{display:block;margin-top:4px;font-size:9px;color:#fff2df;opacity:.9}
    .bronzeChevron{font-size:20px;transition:transform .18s ease}.voucherPartnerGroup[open]>.bronzeBranchBtn .bronzeChevron{transform:rotate(90deg)}
    .voucherDateStack{display:grid;gap:8px;padding:9px 4px 2px 12px}
    .voucherDateBtn{display:flex;align-items:center;gap:9px;width:100%;padding:10px 11px;border:1px solid #3d568b;border-radius:11px;background:linear-gradient(160deg,#132249,#0a1530);color:#fff;cursor:pointer}
    .voucherDateBtn b{font-size:11px;flex:1;text-align:left}.voucherDateBtn span{font-size:9px;color:#b8c5e4}.voucherDateGroup[open]>.voucherDateBtn{border-color:#6f8ed0;background:linear-gradient(160deg,#1a2d5c,#0c1938)}
    .voucherDayList{display:grid;gap:7px;padding:8px 2px 2px 10px}
    .voucherItemSummary{display:flex;align-items:center;gap:9px;width:100%;padding:10px 11px;border:1px solid #293f70;border-radius:10px;background:#09142e;color:#fff;cursor:pointer}
    .voucherItemMain{min-width:0;flex:1;text-align:left}.voucherItemMain b{display:block;font-size:10px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.voucherItemMain small{display:block;margin-top:3px;color:#93a6cc;font-size:8px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .voucherStatusDot{width:8px;height:8px;border-radius:999px;background:#70e4ee;flex:0 0 auto}.voucherStatusDot.redeemed{background:#6ee7a8}.voucherStatusDot.expired,.voucherStatusDot.revoked{background:#ff9baa}
    .voucherItemDetail{margin-top:5px;padding:8px 10px;border:1px solid #263967;border-radius:9px;background:#071126}
    .voucherItemDetail .detailRow{grid-template-columns:82px 1fr;padding:4px 0}
    .voucherHierarchyEmpty{padding:12px;border:1px dashed #40517d;border-radius:10px;color:#aab7d6;font-size:10px}
    .voucherHierarchyHint{margin-top:9px;padding:8px 10px;border-radius:10px;background:rgba(192,138,80,.11);border:1px solid rgba(192,138,80,.38);color:#d8c3a7;font-size:9px;line-height:1.45}
    @media(min-width:621px){.voucherHierarchy{grid-template-columns:1fr 1fr;align-items:start}.voucherPartnerGroup[open]{grid-column:1/-1}.voucherDateStack{grid-template-columns:1fr 1fr}.voucherDateGroup[open]{grid-column:1/-1}.voucherDayList{grid-template-columns:1fr 1fr}.voucherItemV2[open]{grid-column:1/-1}}
    @media(max-width:620px){#voucherTable.voucherHierarchyHost{display:none!important}#voucherCards .voucherHierarchy{display:grid}}
  `;
  document.head.appendChild(style);

  function indexMap(table){const out={};[...table.querySelectorAll('thead th')].forEach((th,i)=>{out[String(th.textContent||'').trim().toLowerCase()]=i});return out}
  function cellText(cells,index){return index==null?'—':String(cells[index]?.textContent||'—').trim()||'—'}
  function dateBucket(issued){const text=String(issued||'—').trim();if(!text||text==='—')return 'Unknown date';const comma=text.indexOf(',');if(comma>0)return text.slice(0,comma).trim();const m=text.match(/^((?:\d{1,4}[\/\-.]){2}\d{1,4})/);if(m)return m[1];return text.split(/\s+/)[0]||'Unknown date'}
  function counts(rows){const c={active:0,redeemed:0,expired:0,revoked:0};rows.forEach(r=>{const s=String(r.status||'').toLowerCase();if(Object.hasOwn(c,s))c[s]++});return c}
  function rowDetail(r){const fields=[['Voucher',r.voucher],['Customer',r.customer],['Partner',r.partner],['Branch',r.branch||'Not yet redeemed'],['Type',r.type],['Status',r.status],['Expiry',r.expiry],['Issued',r.issued]];return fields.map(([k,v])=>`<div class="detailRow"><b>${esc(k)}</b><span>${esc(v)}</span></div>`).join('')}

  function completedBranchMap(){
    const byCode=new Map();
    redemptionRows.filter(r=>String(r.redemption_status||'').toLowerCase()==='completed').forEach(r=>{
      const code=String(r.voucher_code||'').trim();if(!code)return;
      const when=new Date(r.redeemed_at||0).getTime()||0;
      const prev=byCode.get(code);
      if(!prev||when>prev.when)byCode.set(code,{branchId:String(r.branch_id||''),branchName:String(r.branch_name||'').trim(),when});
    });
    return byCode;
  }

  function renderGroup(label,items,{pending=false,empty=false}={}){
    const c=counts(items),dates=new Map();
    items.forEach(r=>{const key=dateBucket(r.issued);if(!dates.has(key))dates.set(key,[]);dates.get(key).push(r)});
    const summary=empty?'No redeemed vouchers yet':`${items.length} voucher${items.length===1?'':'s'} · ${c.active} active · ${c.redeemed} redeemed`;
    const body=items.length?[...dates.entries()].map(([date,dayRows])=>{const dc=counts(dayRows);return `<details class="voucherDateGroup"><summary class="voucherDateBtn"><b>${esc(date)}</b><span>${dayRows.length} voucher${dayRows.length===1?'':'s'} · ${dc.active} active</span><span>›</span></summary><div class="voucherDayList">${dayRows.map(r=>`<details class="voucherItemV2"><summary class="voucherItemSummary"><span class="voucherStatusDot ${esc(String(r.status||'').toLowerCase())}"></span><span class="voucherItemMain"><b>${esc(r.voucher)}</b><small>${esc(r.customer)} · ${esc(r.status)}</small></span><span>›</span></summary><div class="voucherItemDetail">${rowDetail(r)}</div></details>`).join('')}</div></details>`}).join(''):'<div class="voucherHierarchyEmpty">No voucher records for this branch yet.</div>';
    return `<details class="voucherPartnerGroup"><summary class="bronzeBranchBtn${pending?' pending':''}${empty?' empty':''}"><span class="bronzeMark">EO</span><span class="bronzeText"><b>${esc(label)}</b><small>${esc(summary)}</small></span><span class="bronzeChevron">›</span></summary><div class="voucherDateStack">${body}</div></details>`;
  }

  function renderHierarchy(rows){
    if(!rows.length)return '<div class="voucherHierarchyEmpty">No records.</div>';
    const branchMap=completedBranchMap();
    const activeBranches=branchRows.filter(b=>String(b.branch_status||'').toLowerCase()==='active');
    const byBranchId=new Map(activeBranches.map(b=>[String(b.branch_id||''),[]]));
    const byBranchName=new Map(activeBranches.map(b=>[String(b.branch_name||'').trim().toLowerCase(),String(b.branch_id||'')]));
    const pending=[];
    rows.forEach(r=>{
      const hit=branchMap.get(String(r.voucher||'').trim());
      if(!hit){pending.push({...r,branch:''});return}
      let id=hit.branchId;
      if(!byBranchId.has(id))id=byBranchName.get(hit.branchName.toLowerCase())||'';
      if(id&&byBranchId.has(id))byBranchId.get(id).push({...r,branch:hit.branchName});
      else pending.push({...r,branch:hit.branchName||''});
    });
    const groups=activeBranches.map(b=>renderGroup(b.branch_name||b.branch_code||'Branch',byBranchId.get(String(b.branch_id||''))||[],{empty:(byBranchId.get(String(b.branch_id||''))||[]).length===0}));
    if(pending.length)groups.push(renderGroup('Not Yet Redeemed / Unassigned',pending,{pending:true}));
    return `<div class="voucherHierarchy">${groups.join('')}</div>`;
  }

  async function loadMetadata(){
    if(metadataReady||!db)return;
    try{
      const [{data:b,error:be},{data:r,error:re}]=await Promise.all([
        db.rpc('admin_branch_directory'),
        db.rpc('admin_redemption_report',{p_partner_id:null,p_limit:5000})
      ]);
      if(be)throw be;if(re)throw re;
      branchRows=Array.isArray(b)?b:[];redemptionRows=Array.isArray(r)?r:[];metadataReady=true;
    }catch(e){console.warn('Voucher branch hierarchy metadata unavailable; using fallback grouping.',e);metadataReady=false}
  }

  function fallbackHierarchy(rows){
    const partners=new Map();rows.forEach(r=>{const key=r.partner||'Unknown';if(!partners.has(key))partners.set(key,[]);partners.get(key).push(r)});
    return `<div class="voucherHierarchy">${[...partners.entries()].map(([name,items])=>renderGroup(name,items)).join('')}</div>`;
  }

  async function transform(){
    const host=document.getElementById('voucherTable'),mobile=document.getElementById('voucherCards');if(!host||!mobile)return;
    if(host.querySelector('.voucherHierarchy'))return;
    const table=host.querySelector('table');
    if(!table){if(host.querySelector('.readonly'))mobile.innerHTML='<div class="voucherHierarchyEmpty">No records.</div>';return}
    const idx=indexMap(table),rows=[...table.querySelectorAll('tbody tr')].map(tr=>{const cells=[...tr.children];return {voucher:cellText(cells,idx.voucher),partner:cellText(cells,idx.partner),customer:cellText(cells,idx.customer),type:cellText(cells,idx.type),status:cellText(cells,idx.status),expiry:cellText(cells,idx.expiry),issued:cellText(cells,idx.issued)}});
    await loadMetadata();
    const html=metadataReady?renderHierarchy(rows):fallbackHierarchy(rows);
    host.classList.add('voucherHierarchyHost');host.innerHTML=html;
    mobile.innerHTML=`<div class="voucherHierarchyHint">Branch cards are generated from active Branch records. Tap a branch, then a date, then a voucher. New active branches appear automatically; inactive branches stay hidden. Vouchers without a completed redemption remain under “Not Yet Redeemed / Unassigned”.</div>${html}`;
    const panel=document.querySelector('#voucher .reportsub');if(panel)panel.textContent='Branch-driven view: Branch → Date → Voucher details.';
  }

  function install(){const host=document.getElementById('voucherTable');if(!host)return false;const observer=new MutationObserver(()=>queueMicrotask(()=>transform()));observer.observe(host,{childList:true,subtree:false});transform();return true}
  const start=()=>{let tries=0;const t=setInterval(()=>{tries++;if(install()||tries>60)clearInterval(t)},100)};
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();
