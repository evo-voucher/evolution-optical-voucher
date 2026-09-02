(()=>{
const cfg=window.EVOLUTION_VOUCHER_BACKEND||{},path=String(location.pathname||'').toLowerCase(),$=id=>document.getElementById(id),esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
if(!window.supabase?.createClient)return;const db=window.supabase.createClient(cfg.supabaseUrl,cfg.publishableKey);

function preparePartnerCustomerFields(){
  if(!path.endsWith('/partner.html'))return false;
  const phone=$('issuePhone');if(!phone)return false;
  const phoneField=phone.closest('.field');if(!phoneField)return false;
  phoneField.classList.add('partner-phone-field');
  phone.type='tel';
  phone.setAttribute('inputmode','tel');
  phone.setAttribute('autocomplete','tel');
  phone.setAttribute('enterkeyhint','done');
  let birthday=$('issueBirthday');
  if(!birthday){
    const birthdayField=document.createElement('div');
    birthdayField.className='field partner-birthday-field';
    birthdayField.innerHTML='<label id="issueBirthdayLabel">Customer Birthday (optional)</label><input id="issueBirthday" type="date" autocomplete="off">';
    phoneField.insertAdjacentElement('afterend',birthdayField);
    birthday=$('issueBirthday');
  }
  const birthdayField=birthday?.closest('.field');
  if(birthdayField)birthdayField.classList.add('partner-birthday-field');
  if(birthday){birthday.setAttribute('autocomplete','off');birthday.autocomplete='off';}
  if(!$('partnerCustomerFieldSeparationStyle')){
    const style=document.createElement('style');
    style.id='partnerCustomerFieldSeparationStyle';
    style.textContent='.partner-phone-field{position:relative;z-index:2}.partner-phone-field input{position:relative;z-index:2;touch-action:manipulation}.partner-birthday-field{position:relative;z-index:1;margin-top:28px!important}.partner-birthday-field input{position:relative;z-index:1;touch-action:manipulation}@media(max-width:680px){.partner-birthday-field{margin-top:32px!important}}';
    document.head.appendChild(style);
  }
  return true;
}

if(path.endsWith('/partner.html')){
  document.addEventListener('DOMContentLoaded',preparePartnerCustomerFields,{once:true,capture:true});
  if(document.readyState!=='loading')preparePartnerCustomerFields();
}

async function rules(){const{data,error}=await db.rpc('customer_field_requirements',{});if(error)throw error;return data||{}}
async function districts(admin=false){const{data,error}=await db.rpc(admin?'admin_customer_district_directory':'customer_district_options',{});if(error)throw error;return data||[]}
function excelSafe(value){const s=String(value??'');return /^[=+\-@]/.test(s)?`'${s}`:s}
async function exportAllCustomersByDistrict(button,status){
  const previous=button.textContent;button.disabled=true;button.textContent='Preparing…';status.textContent='Loading all Partner customers…';
  try{
    if(!window.XLSX)throw new Error('Excel export library is unavailable.');
    const [{data:customers,error:customerError},districtRows]=await Promise.all([db.rpc('admin_customer_directory',{p_partner_id:null}),districts(true)]);
    if(customerError)throw customerError;
    const rows=customers||[];if(!rows.length)throw new Error('No customer records to export.');
    const order=new Map((districtRows||[]).map((r,i)=>[String(r.district_name||'').trim().toLowerCase(),i]));
    const rankedDistrict=d=>{const key=String(d||'').trim().toLowerCase();return order.has(key)?order.get(key):Number.MAX_SAFE_INTEGER;};
    rows.sort((a,b)=>rankedDistrict(a.customer_district)-rankedDistrict(b.customer_district)||String(a.customer_district||'').localeCompare(String(b.customer_district||''),undefined,{sensitivity:'base'})||String(a.partner_code||'').localeCompare(String(b.partner_code||''),undefined,{numeric:true,sensitivity:'base'})||String(a.customer_name||'').localeCompare(String(b.customer_name||''),undefined,{sensitivity:'base'}));
    const exportRows=rows.map(r=>({
      District:excelSafe(r.customer_district||'Unspecified'),
      Partner_Code:excelSafe(r.partner_code),
      Partner_Name:excelSafe(r.partner_name),
      Customer_Name:excelSafe(r.customer_name),
      Phone:excelSafe(r.customer_phone),
      Birthday:r.customer_birthday||'',
      Voucher_Count:Number(r.voucher_count||0),
      First_Seen:r.first_seen_at||'',
      Last_Seen:r.last_seen_at||''
    }));
    const ws=XLSX.utils.json_to_sheet(exportRows),wb=XLSX.utils.book_new();
    ws['!cols']=[{wch:22},{wch:16},{wch:28},{wch:28},{wch:18},{wch:14},{wch:14},{wch:22},{wch:22}];
    XLSX.utils.book_append_sheet(wb,ws,'Customers by District');
    const date=new Date().toISOString().slice(0,10);XLSX.writeFile(wb,`evolution-all-customers-by-district-${date}.xlsx`);
    const districtCount=new Set(rows.map(r=>String(r.customer_district||'').trim()).filter(Boolean)).size;
    status.textContent=`Ready ✓ ${rows.length} customer(s) across ${districtCount} District(s). Sorted by District → Partner → Customer.`;
  }catch(e){status.textContent=e.message||'Unable to export customer records.';}finally{button.disabled=false;button.textContent=previous;}
}
function ensureAdminCustomerExportCard(dash){
  if($('adminCustomerExportCard'))return;
  const card=document.createElement('section');card.id='adminCustomerExportCard';card.className='card';card.dataset.adminSection='reports';
  card.innerHTML='<h2>Customer Records</h2><p class="small">All Partner customers in one master Excel file. Primary order follows the District Management sequence, then Partner, then Customer.</p><button id="exportAllCustomersByDistrict" class="wide" type="button">Export All Customers XLSX</button><div id="allCustomerExportStatus" class="small" style="margin-top:10px">Admin only • read-only export.</div>';
  dash.appendChild(card);
  const button=$('exportAllCustomersByDistrict'),status=$('allCustomerExportStatus');button.onclick=()=>exportAllCustomersByDistrict(button,status);
}
function admin(){if(!path.endsWith('/admin.html')||$('districtMasterCard'))return;const dash=$('dashboardState');if(!dash)return;const card=document.createElement('section');card.id='districtMasterCard';card.className='card';card.dataset.adminSection='settings';card.innerHTML=`<h2>District Management</h2><p class="small">Partner District list follows this exact order. Inactive Districts stay in history but are hidden from new customer selection.</p><button id="openAddDistrictBtn" class="wide" type="button">＋ Add District</button><div id="addDistrictPanel" class="hidden" style="margin-top:12px"><div class="field"><label>District Name</label><input id="newDistrictName" placeholder="Enter District name"></div><button id="addDistrictBtn" class="wide" type="button">Save District</button></div><div id="districtMsg" class="small"></div><div id="districtList" style="margin-top:12px"></div>`;dash.appendChild(card);ensureAdminCustomerExportCard(dash);
const msg=$('districtMsg'),list=$('districtList'),panel=$('addDistrictPanel'),open=$('openAddDistrictBtn');open.onclick=()=>{panel.classList.toggle('hidden');open.textContent=panel.classList.contains('hidden')?'＋ Add District':'− Close Add District';if(!panel.classList.contains('hidden'))setTimeout(()=>$('newDistrictName')?.focus(),50)};
async function load(){try{const rows=await districts(true);list.innerHTML=rows.map((r,i)=>`<div style="display:grid;grid-template-columns:34px 1fr auto;gap:8px;align-items:center;padding:9px 0;border-bottom:1px solid rgba(115,135,210,.22)"><b>${i+1}</b><span>${esc(r.district_name)} <small>(${esc(r.district_status)})</small></span><span><button data-move="up" data-id="${r.district_id}" ${i===0?'disabled':''}>↑</button> <button data-move="down" data-id="${r.district_id}" ${i===rows.length-1?'disabled':''}>↓</button> <button data-status="${r.district_status==='active'?'inactive':'active'}" data-id="${r.district_id}">${r.district_status==='active'?'Inactive':'Active'}</button></span></div>`).join('');msg.textContent=`${rows.length} District(s)`}catch(e){msg.textContent=e.message||'Unable to load Districts'}}
$('addDistrictBtn').onclick=async()=>{const name=$('newDistrictName').value.trim();if(!name)return;try{const{error}=await db.rpc('admin_add_customer_district',{p_district_name:name});if(error)throw error;$('newDistrictName').value='';panel.classList.add('hidden');open.textContent='＋ Add District';await load()}catch(e){msg.textContent=e.message}};
list.onclick=async e=>{const b=e.target.closest('button');if(!b)return;b.disabled=true;try{let error;if(b.dataset.move)({error}=await db.rpc('admin_move_customer_district',{p_district_id:b.dataset.id,p_direction:b.dataset.move}));else({error}=await db.rpc('admin_set_customer_district_status',{p_district_id:b.dataset.id,p_status:b.dataset.status}));if(error)throw error;await load()}catch(x){msg.textContent=x.message}finally{b.disabled=false}};
const ruleBox=$('customerBirthdayRule')?.closest('.customer-field-rule-grid');if(ruleBox&&!$('customerDistrictRule')){const f=document.createElement('div');f.className='field';f.innerHTML='<label>Customer District</label><select id="customerDistrictRule"><option value="required">Required</option><option value="optional">Optional</option></select>';ruleBox.appendChild(f);const save=$('saveCustomerFieldRules');if(save){save.addEventListener('click',async e=>{e.stopImmediatePropagation();save.disabled=true;try{const{data,error}=await db.rpc('admin_set_customer_field_requirements',{p_phone_required:$('customerPhoneRule').value==='required',p_birthday_required:$('customerBirthdayRule').value==='required',p_district_required:$('customerDistrictRule').value==='required'});if(error)throw error;$('customerFieldRulesStatus').textContent=`Saved ✓ Phone ${data.phone_required?'Required':'Optional'} • Birthday ${data.birthday_required?'Required':'Optional'} • District ${data.district_required?'Required':'Optional'}`}catch(x){$('customerFieldRulesStatus').textContent=x.message}finally{save.disabled=false}},true)}rules().then(r=>$('customerDistrictRule').value=r.district_required?'required':'optional').catch(()=>{})}
let tries=0,t=setInterval(()=>{tries++;if(!dash.classList.contains('hidden')){clearInterval(t);load()}else if(tries>80)clearInterval(t)},250)}
function partner(){if(!path.endsWith('/partner.html')||$('issueDistrict'))return;if(!preparePartnerCustomerFields()){setTimeout(partner,250);return}const birthday=$('issueBirthday'),phone=$('issuePhone'),btn=$('issueBtn');if(!phone||!btn){setTimeout(partner,250);return}const anchor=birthday?.closest('.field')||phone.closest('.field');const f=document.createElement('div');f.className='field';f.innerHTML='<label id="issueDistrictLabel">Customer District</label><select id="issueDistrict" disabled><option value="">Loading Districts…</option></select>';anchor.insertAdjacentElement('afterend',f);const select=$('issueDistrict'),label=$('issueDistrictLabel');let required=false,loaded=false;
async function refresh(){const [r,ds]=await Promise.all([rules(),districts(false)]);required=!!r.district_required;select.required=required;label.textContent=`Customer District${required?'':' (optional)'}`;const val=select.value;select.innerHTML='<option value="">Select District</option>'+ds.map(d=>`<option value="${esc(d.district_name)}">${esc(d.district_name)}</option>`).join('');if(ds.some(d=>d.district_name===val))select.value=val;loaded=true;select.disabled=false;}
async function loadForSession(){const{data}=await db.auth.getSession();if(!data?.session){loaded=false;select.disabled=true;select.innerHTML='<option value="">Sign in to load Districts</option>';return;}try{await refresh()}catch(e){loaded=false;select.disabled=true;select.innerHTML='<option value="">Unable to load Districts</option>';}}
db.auth.getSession().then(()=>loadForSession());db.auth.onAuthStateChange((event,session)=>{if(session)setTimeout(()=>loadForSession(),0);else{loaded=false;select.disabled=true;select.innerHTML='<option value="">Sign in to load Districts</option>';}});
window.addEventListener('click',async e=>{const target=e.target.closest?.('#issueBtn');if(!target)return;e.preventDefault();e.stopImmediatePropagation();const version=$('issueVersion')?.value?.trim(),name=$('issueName')?.value?.trim(),pv=phone.value.trim(),bv=birthday?.value||null,dv=select.value||null,msg=$('issueMsg'),result=$('issueResult');const show=(x,ok=false)=>{if(msg)msg.innerHTML=x?`<div class="msg ${ok?'ok':'err'}">${esc(x)}</div>`:''};if(!loaded){try{await loadForSession()}catch(_){}}if(!version)return show('Select an available Voucher type.');if(!name)return show('Customer name is required.');const r=await rules();if(r.phone_required&&!pv)return show('Customer phone is required.');if(r.birthday_required&&!bv)return show('Customer birthday is required.');if(r.district_required&&!dv)return show('Customer district is required.');target.disabled=true;try{const args={p_version_id:version,p_customer_name:name,p_customer_phone:pv||null,p_customer_birthday:bv,p_customer_district:dv};const picker=$('adminPartnerSelect');if(picker?.value)args.p_partner_id=picker.value;const{data,error}=await db.rpc('issue_engine_voucher_with_customer',args);if(error)throw error;const url=data.public_token?`${cfg.siteBase}voucher.html?v=${encodeURIComponent(data.public_token)}`:'';show(`Voucher ${data.voucher_code||''} issued successfully.`,true);if(result)result.innerHTML=`<div class="msg ok"><b>${esc(data.voucher_type||'Voucher')}</b><div>Code: ${esc(data.voucher_code||'—')}</div><div>Expiry: ${esc(data.expiry_date||'—')}</div>${url?`<a class="resultLink" href="${esc(url)}" target="_blank">Open customer voucher</a>`:''}</div>`;$('issueName').value='';phone.value='';if(birthday)birthday.value='';select.value=''}catch(x){show(x.message||'Voucher issuance failed.')}finally{target.disabled=false}},true)}
function mount(){if(path.endsWith('/admin.html'))admin();if(path.endsWith('/partner.html'))partner()}if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',mount,{once:true});else mount();
})();