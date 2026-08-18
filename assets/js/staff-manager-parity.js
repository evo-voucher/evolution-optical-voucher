(()=>{
  const mobileStyle=document.createElement('style');
  mobileStyle.id='staffMobileLayoutFix';
  mobileStyle.textContent=`
    @media(max-width:680px){
      .toprow{flex-direction:column!important;align-items:stretch!important}
      .toprow>div:first-child{max-width:100%!important;width:100%!important}
      .toprow button{width:100%!important;min-width:0!important}
      .stats{grid-template-columns:1fr!important}
      .actions{flex-direction:column!important;flex-wrap:nowrap!important}
      .actions button{width:100%!important;flex:1 1 auto!important}
      .tablewrap{overflow:visible!important}
    }
    @media(hover:none) and (pointer:coarse){
      button:hover:not(:disabled){transform:none!important}
      button:active:not(:disabled){transform:translateY(1px)!important}
    }
  `;
  if(!document.getElementById(mobileStyle.id))document.head.appendChild(mobileStyle);

  const cfg=window.EVOLUTION_VOUCHER_BACKEND||{};
  if(!(cfg.enabled===true&&cfg.supabaseUrl&&cfg.publishableKey&&window.supabase))return;
  const db=window.supabase.createClient(cfg.supabaseUrl,cfg.publishableKey,{auth:{persistSession:true}});
  const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const show=(node,text,ok=false)=>{node.innerHTML=text?`<div class="msg ${ok?'ok':'err'}">${esc(text)}</div>`:''};

  async function boot(){
    const {data:{session}}=await db.auth.getSession();
    if(!session?.user)return;
    const {data:realm,error:realmError}=await db.rpc('current_operational_realm');
    if(realmError||realm?.realm!=='staff'||!['manager','all_branch_manager'].includes(String(realm?.role||'').toLowerCase()))return;
    const {data:ctx,error:ctxError}=await db.rpc('staff_operational_context');
    if(ctxError)return;
    const branches=Array.isArray(ctx?.branches)?ctx.branches:[];
    const role=String(realm.role||'').toLowerCase();
    const allManager=role==='all_branch_manager';
    const host=document.getElementById('operationState');
    if(!host||document.getElementById('managerStaffCard'))return;

    const card=document.createElement('section');
    card.id='managerStaffCard';card.className='card';
    card.innerHTML=`<h2>Staff Management</h2><p class="small">${allManager?'All Branch Manager can create Staff or Branch Manager accounts at an allowed branch.':'Branch Manager can create Staff accounts only for the assigned branch.'}</p><div class="grid"><div class="field"><label>Staff Name</label><input id="mgrStaffName" autocomplete="name"></div><div class="field"><label>Login Email</label><input id="mgrStaffEmail" type="email" autocomplete="off"></div><div class="field"><label>Temporary Password</label><input id="mgrStaffPassword" type="password" autocomplete="new-password"></div><div id="mgrBranchField" class="field"><label>Assigned Branch</label><select id="mgrStaffBranch"></select></div>${allManager?'<div class="field"><label>Role</label><select id="mgrStaffRole"><option value="staff">Staff</option><option value="manager">Branch Manager</option></select></div>':''}</div><button id="mgrCreateStaffBtn" class="wide">Add Staff</button><div id="mgrStaffMsg"></div>`;
    host.insertBefore(card,host.lastElementChild);

    const branchSelect=document.getElementById('mgrStaffBranch');
    branchSelect.innerHTML='<option value="">Select branch</option>'+branches.map(b=>`<option value="${esc(b.branch_id||b.id)}">${esc(b.branch_name)} (${esc(b.branch_code)})</option>`).join('');
    if(!allManager&&branches.length===1){branchSelect.value=branches[0].branch_id||branches[0].id;branchSelect.disabled=true;}

    document.getElementById('mgrCreateStaffBtn').addEventListener('click',async()=>{
      const btn=document.getElementById('mgrCreateStaffBtn'),msg=document.getElementById('mgrStaffMsg');
      const staff_name=document.getElementById('mgrStaffName').value.trim();
      const email=document.getElementById('mgrStaffEmail').value.trim().toLowerCase();
      const password=document.getElementById('mgrStaffPassword').value;
      const branch_id=branchSelect.value;
      const requestedRole=allManager?(document.getElementById('mgrStaffRole')?.value||'staff'):'staff';
      show(msg,'');
      if(!staff_name||!email||!password||!branch_id){show(msg,'Staff name, login email, password and branch are required.');return;}
      if(!email.includes('@')){show(msg,'Enter a valid Staff login email.');return;}
      if(password.length<6){show(msg,'Password must be at least 6 characters.');return;}
      btn.disabled=true;
      try{
        const {data,error}=await db.functions.invoke('create-staff',{body:{staff_name,email,password,branch_id,role:requestedRole}});
        if(error)throw error;
        if(!data?.success)throw new Error(data?.details||data?.error||'Staff creation failed.');
        document.getElementById('mgrStaffName').value='';document.getElementById('mgrStaffEmail').value='';document.getElementById('mgrStaffPassword').value='';if(allManager)branchSelect.value='';
        show(msg,`${requestedRole==='manager'?'Branch Manager':'Staff'} ${staff_name} created successfully.`,true);
      }catch(e){show(msg,e.message||'Staff creation failed.');}
      finally{btn.disabled=false;}
    });
  }

  window.addEventListener('load',()=>setTimeout(boot,0));
})();
