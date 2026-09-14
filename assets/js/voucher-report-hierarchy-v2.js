// Voucher Reports V2: compact drill-down view for Admin V2.
// Presentation-only. Existing report RPCs, filters and exports remain unchanged.
(function(){
  'use strict';
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!path.endsWith('/experience/admin-v2.html'))return;

  const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const style=document.createElement('style');
  style.id='voucherReportHierarchyV2Style';
  style.textContent=`
    #voucherTable.voucherHierarchyHost{overflow:visible;border:0;background:transparent}
    .voucherHierarchy{margin-top:12px;display:grid;gap:10px}
    .voucherPartnerGroup,.voucherDateGroup,.voucherItemV2{border:0;margin:0}
    .voucherPartnerGroup>summary,.voucherDateGroup>summary,.voucherItemV2>summary{list-style:none}
    .voucherPartnerGroup>summary::-webkit-details-marker,.voucherDateGroup>summary::-webkit-details-marker,.voucherItemV2>summary::-webkit-details-marker{display:none}
    .bronzeBranchBtn{display:flex;align-items:center;gap:11px;width:100%;padding:13px 14px;border:1px solid #c08a50;border-radius:14px;background:linear-gradient(145deg,#6f4324 0%,#a86e37 42%,#d3a369 100%);box-shadow:0 8px 22px rgba(0,0,0,.24),inset 0 1px 0 rgba(255,255,255,.22);color:#fff;cursor:pointer}
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

  function indexMap(table){
    const out={};
    [...table.querySelectorAll('thead th')].forEach((th,i)=>{out[String(th.textContent||'').trim().toLowerCase()]=i});
    return out;
  }
  function cellText(cells,index){return index==null?'—':String(cells[index]?.textContent||'—').trim()||'—'}
  function dateBucket(issued){
    const text=String(issued||'—').trim();
    if(!text||text==='—')return 'Unknown date';
    const comma=text.indexOf(',');
    if(comma>0)return text.slice(0,comma).trim();
    const m=text.match(/^((?:\d{1,4}[\/\-.]){2}\d{1,4})/);
    if(m)return m[1];
    return text.split(/\s+/)[0]||'Unknown date';
  }
  function counts(rows){
    const c={active:0,redeemed:0,expired:0,revoked:0};
    rows.forEach(r=>{const s=String(r.status||'').toLowerCase();if(Object.hasOwn(c,s))c[s]++});
    return c;
  }
  function rowDetail(r){
    const fields=[['Voucher',r.voucher],['Customer',r.customer],['Partner / Branch',r.partner],['Type',r.type],['Status',r.status],['Expiry',r.expiry],['Issued',r.issued]];
    return fields.map(([k,v])=>`<div class="detailRow"><b>${esc(k)}</b><span>${esc(v)}</span></div>`).join('');
  }
  function renderHierarchy(rows){
    if(!rows.length)return '<div class="voucherHierarchyEmpty">No records.</div>';
    const partners=new Map();
    rows.forEach(r=>{const key=r.partner||'Unknown';if(!partners.has(key))partners.set(key,[]);partners.get(key).push(r)});
    return `<div class="voucherHierarchy">${[...partners.entries()].map(([partner,items])=>{
      const c=counts(items),dates=new Map();
      items.forEach(r=>{const key=dateBucket(r.issued);if(!dates.has(key))dates.set(key,[]);dates.get(key).push(r)});
      return `<details class="voucherPartnerGroup"><summary class="bronzeBranchBtn"><span class="bronzeMark">EO</span><span class="bronzeText"><b>${esc(partner)}</b><small>${items.length} voucher${items.length===1?'':'s'} · ${c.active} active · ${c.redeemed} redeemed</small></span><span class="bronzeChevron">›</span></summary><div class="voucherDateStack">${[...dates.entries()].map(([date,dayRows])=>{
        const dc=counts(dayRows);
        return `<details class="voucherDateGroup"><summary class="voucherDateBtn"><b>${esc(date)}</b><span>${dayRows.length} voucher${dayRows.length===1?'':'s'} · ${dc.active} active</span><span>›</span></summary><div class="voucherDayList">${dayRows.map(r=>`<details class="voucherItemV2"><summary class="voucherItemSummary"><span class="voucherStatusDot ${esc(String(r.status||'').toLowerCase())}"></span><span class="voucherItemMain"><b>${esc(r.voucher)}</b><small>${esc(r.customer)} · ${esc(r.status)}</small></span><span>›</span></summary><div class="voucherItemDetail">${rowDetail(r)}</div></details>`).join('')}</div></details>`;
      }).join('')}</div></details>`;
    }).join('')}</div>`;
  }

  function transform(){
    const host=document.getElementById('voucherTable');
    const mobile=document.getElementById('voucherCards');
    if(!host||!mobile)return;
    if(host.querySelector('.voucherHierarchy'))return;
    const table=host.querySelector('table');
    if(!table){
      if(host.querySelector('.readonly'))mobile.innerHTML='<div class="voucherHierarchyEmpty">No records.</div>';
      return;
    }
    const idx=indexMap(table),rows=[...table.querySelectorAll('tbody tr')].map(tr=>{
      const cells=[...tr.children];
      return {voucher:cellText(cells,idx.voucher),partner:cellText(cells,idx.partner),customer:cellText(cells,idx.customer),type:cellText(cells,idx.type),status:cellText(cells,idx.status),expiry:cellText(cells,idx.expiry),issued:cellText(cells,idx.issued)};
    });
    const html=renderHierarchy(rows);
    host.classList.add('voucherHierarchyHost');
    host.innerHTML=html;
    mobile.innerHTML=`<div class="voucherHierarchyHint">Tap a bronze Partner / Branch card, then choose a date. Voucher details stay collapsed until you need them.</div>${html}`;
    const panel=document.querySelector('#voucher .reportsub');
    if(panel)panel.textContent='Compact view: Partner / Branch → Date → Voucher details.';
  }

  function install(){
    const host=document.getElementById('voucherTable');if(!host)return false;
    const observer=new MutationObserver(()=>queueMicrotask(transform));
    observer.observe(host,{childList:true,subtree:false});
    transform();
    return true;
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>{let tries=0;const t=setInterval(()=>{tries++;if(install()||tries>60)clearInterval(t)},100)},{once:true});
  else{let tries=0;const t=setInterval(()=>{tries++;if(install()||tries>60)clearInterval(t)},100);}
})();
