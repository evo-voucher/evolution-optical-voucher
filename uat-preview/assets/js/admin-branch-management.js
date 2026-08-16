(()=>{
  const cfg=window.EVOLUTION_VOUCHER_BACKEND||{};
  if(!(cfg.enabled===true&&cfg.supabaseUrl&&cfg.publishableKey))return;
  const db=window.supabase.createClient(cfg.supabaseUrl,cfg.publishableKey,{auth:{persistSession:true}});
  const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  let mounted=false;
  function ensureCard(){
    if(document.getElementById('branchAdminCard'))return document.getElementById('branchAdminCard');
    const anchor=document.querySelector('#partnerControls')?.closest('.card');if(!anchor)return null;
    const card=document.createElement('section');card.id='branchAdminCard';card.className='card';
    card.innerHTML=`<div class="toprow"><div><h2>Branch Admin</h2><p class="small">Manage branch name, contact details and lifecycle status. Branch Code is immutable; deletion is intentionally disabled.</p></div><button id="branchRefresh">Refresh</button></div><div id="branchAdminMsg"></div><div id="branchAdminList"></div>`;
    anchor.parentNode.insertBefore(card,anchor.nextSibling);
    document.getElementById('branchRefresh').addEventListener('click',load);
    mounted=true;return card;
  }
  function msg(text,ok=false){const n=document.getElementById('branchAdminMsg');if(n)n.innerHTML=text?`<div class="msg ${ok?'ok':'err'}">${esc(text)}</div>`:''}
  async function load(){
    try{
      const {data:realm,error:re}=await db.rpc('current_operational_realm');if(re)throw re;
      if(!realm||realm.authenticated!==true||realm.realm!=='admin')return;
      ensureCard();
      const {data:rows,error}=await db.rpc('admin_branch_directory');if(error)throw error;
      const list=document.getElementById('branchAdminList');
      list.innerHTML=(rows||[]).map(b=>`<div class="partner"><div class="partnerhead"><div><b>${esc(b.branch_name)}</b><div class="small">Code: ${esc(b.branch_code)} • ${esc(b.branch_status)}</div></div><span class="badge">${esc(b.branch_status)}</span></div><div class="formgrid"><div class="field"><label>Branch Name</label><input id="bn-${b.branch_id}" value="${esc(b.branch_name)}"></div><div class="field"><label>Status</label><select id="bs-${b.branch_id}"><option value="active" ${b.branch_status==='active'?'selected':''}>Active</option><option value="inactive" ${b.branch_status==='inactive'?'selected':''}>Inactive</option><option value="closed" ${b.branch_status==='closed'?'selected':''}>Closed</option></select></div><div class="field"><label>Address</label><input id="ba-${b.branch_id}" value="${esc(b.address||'')}"></div><div class="field"><label>Phone</label><input id="bp-${b.branch_id}" value="${esc(b.phone||'')}"></div></div><button class="wide" onclick="window.saveBranchAdmin('${b.branch_id}')">Save Branch</button></div>`).join('')||'<div class="empty">No branches found.</div>';
    }catch(e){ensureCard();msg(e.message||'Unable to load Branch Admin.');}
  }
  window.saveBranchAdmin=async id=>{
    try{
      msg('');const name=document.getElementById(`bn-${id}`).value.trim(),address=document.getElementById(`ba-${id}`).value.trim(),phone=document.getElementById(`bp-${id}`).value.trim(),status=document.getElementById(`bs-${id}`).value;
      if(!name)throw new Error('Branch name is required.');
      const {data,error}=await db.rpc('admin_update_branch',{p_branch_id:id,p_branch_name:name,p_address:address||null,p_phone:phone||null,p_status:status});if(error)throw error;if(!data?.success)throw new Error(data?.error||'Branch update failed.');
      msg('Branch updated successfully.',true);await load();
    }catch(e){msg(e.message||'Branch update failed.');}
  };
  db.auth.onAuthStateChange(()=>setTimeout(load,0));setTimeout(load,300);
})();
