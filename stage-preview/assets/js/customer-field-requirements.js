(()=>{
  'use strict';
  const cfg=window.EVOLUTION_VOUCHER_BACKEND||{};
  if(!(cfg.enabled===true&&cfg.supabaseUrl&&cfg.publishableKey&&window.supabase?.createClient))return;
  const path=String(location.pathname||'').toLowerCase();
  const isPartner=path.endsWith('/partner.html');
  const isAdmin=path.endsWith('/admin.html');
  if(!isPartner&&!isAdmin)return;
  const db=window.supabase.createClient(cfg.supabaseUrl,cfg.publishableKey);
  let rules={phone_required:false,birthday_required:false};
  const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

  async function getRules(){const{data,error}=await db.rpc('customer_field_requirements');if(error)throw error;rules={phone_required:!!data?.phone_required,birthday_required:!!data?.birthday_required};return rules;}
  function applyPartnerLabels(){
    const phone=document.getElementById('issuePhone'),birthday=document.getElementById('issueBirthday');
    if(phone){phone.required=rules.phone_required;const l=phone.closest('.field')?.querySelector('label');if(l)l.textContent=`Customer Phone (${rules.phone_required?'required':'optional'})`;}
    if(birthday){birthday.required=rules.birthday_required;const l=birthday.closest('.field')?.querySelector('label');if(l)l.textContent=`Customer Birthday (${rules.birthday_required?'required':'optional'})`;}
  }
  function installPartnerGuard(){
    const btn=document.getElementById('issueBtn');if(!btn||btn.dataset.customerRuleGuard==='1')return false;btn.dataset.customerRuleGuard='1';
    btn.addEventListener('click',e=>{
      const phone=(document.getElementById('issuePhone')?.value||'').trim(),birthday=document.getElementById('issueBirthday')?.value||'';
      let text='';if(rules.phone_required&&!phone)text='Customer phone is required.';else if(rules.birthday_required&&!birthday)text='Customer birthday is required.';
      if(text){e.preventDefault();e.stopImmediatePropagation();const out=document.getElementById('issueMsg');if(out)out.innerHTML=`<div class="msg err">${esc(text)}</div>`;}
    },true);return true;
  }
  async function mountPartner(){try{await getRules();applyPartnerLabels();installPartnerGuard();}catch(_){} }

  function settingsCard(){return document.getElementById('adminSettingsCard')||[...document.querySelectorAll('#dashboardState>.card')].find(c=>(c.querySelector('h2')?.textContent||'').trim()==='System Settings');}
  function renderAdmin(card){if(!card||document.getElementById('customerFieldRequirementSettings'))return;
    const box=document.createElement('div');box.id='customerFieldRequirementSettings';box.style.marginTop='16px';box.innerHTML=`<h3>Partner Customer Fields</h3><p class="small">Choose which customer details Partners must enter before issuing a Voucher.</p><div class="field"><label>Customer Phone</label><select id="customerPhoneRequirement"><option value="optional">Optional</option><option value="required">Required</option></select></div><div class="field"><label>Customer Birthday</label><select id="customerBirthdayRequirement"><option value="optional">Optional</option><option value="required">Required</option></select></div><button id="saveCustomerFieldRequirements" class="wide" type="button">Save Customer Field Rules</button><div id="customerFieldRequirementMsg"></div>`;card.appendChild(box);
    document.getElementById('customerPhoneRequirement').value=rules.phone_required?'required':'optional';document.getElementById('customerBirthdayRequirement').value=rules.birthday_required?'required':'optional';
    document.getElementById('saveCustomerFieldRequirements').onclick=async()=>{const b=document.getElementById('saveCustomerFieldRequirements'),out=document.getElementById('customerFieldRequirementMsg');b.disabled=true;out.innerHTML='';try{const phone=document.getElementById('customerPhoneRequirement').value==='required',birthday=document.getElementById('customerBirthdayRequirement').value==='required';const{data,error}=await db.rpc('admin_set_customer_field_requirements',{p_phone_required:phone,p_birthday_required:birthday});if(error)throw error;rules={phone_required:!!data?.phone_required,birthday_required:!!data?.birthday_required};out.innerHTML='<div class="msg ok">Customer field rules saved.</div>';}catch(e){out.innerHTML=`<div class="msg err">${esc(e?.message||'Unable to save customer field rules.')}</div>`;}finally{b.disabled=false;}};
  }
  async function mountAdmin(){try{await getRules();}catch(_){return}const tryMount=()=>{const card=settingsCard();if(card){renderAdmin(card);return true}return false};if(tryMount())return;const mo=new MutationObserver(()=>{if(tryMount())mo.disconnect()});mo.observe(document.documentElement,{childList:true,subtree:true});}
  const start=()=>isPartner?mountPartner():mountAdmin();if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();