(()=>{
  const cfg=window.EVOLUTION_VOUCHER_BACKEND||{};
  if(!(cfg.enabled===true&&cfg.supabaseUrl&&cfg.publishableKey))return;
  if(!String(window.location?.pathname||'').toLowerCase().endsWith('/admin.html'))return;

  const db=window.supabase.createClient(cfg.supabaseUrl,cfg.publishableKey,{auth:{persistSession:true}});
  const siteBase=String(cfg.siteBase||'').replace(/\/?$/,'/');
  const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const partnerUrl=`${siteBase}partner.html`;
  const staffUrl=`${siteBase}staff.html`;
  const EMAILS={
    partner:'test.partner@evolution-optical.test',
    partnerStaff:'test.partner.staff@evolution-optical.test',
    evolutionStaff:'test.evolution.staff@evolution-optical.test'
  };

  function ensureStyle(){
    if(document.getElementById('testSandboxStyle'))return;
    const style=document.createElement('style');
    style.id='testSandboxStyle';
    style.textContent=`.sandbox-box{margin-top:16px;padding:16px;border:1px solid rgba(101,230,181,.4);border-radius:16px;background:#0b1736}.sandbox-box h3{margin:0 0 8px;font-size:16px}.sandbox-note{color:#aebdde;font-size:12px;line-height:1.5}.sandbox-grid{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:12px}.sandbox-account{padding:11px 12px;border-radius:13px;background:#0e1a42;border:1px solid rgba(115,135,210,.34)}.sandbox-account b{display:block;font-size:12px}.sandbox-account span{display:block;margin-top:4px;color:#9fb1d9;font-size:11px;word-break:break-word}.sandbox-actions{display:flex;gap:8px;flex-wrap:wrap;margin-top:12px}.sandbox-actions a,.sandbox-actions button{display:inline-flex;align-items:center;justify-content:center;min-height:42px;padding:9px 12px;border-radius:12px;text-decoration:none;font-weight:900}.sandbox-actions a{color:#fff;border:1px solid rgba(122,119,255,.7);background:linear-gradient(180deg,#3549a8,#182b73 58%,#0d1c4c)}.sandbox-danger{border-color:#c45a6c!important;background:linear-gradient(180deg,#8a3e50,#5e2132)!important}.sandbox-password{margin-top:12px}.sandbox-password input{width:100%}.sandbox-msg{margin-top:10px;font-size:12px}.sandbox-msg.ok{color:#65e6b5}.sandbox-msg.err{color:#ff92a5}@media(max-width:620px){.sandbox-grid{grid-template-columns:1fr}.sandbox-actions>*{flex:1}}`;
    document.head.appendChild(style);
  }

  async function invoke(action,extra={}){
    const {data,error}=await db.functions.invoke('admin-test-sandbox',{body:{action,...extra}});
    if(error)throw error;
    if(!data?.success)throw new Error(data?.details||data?.error||'Test Sandbox request failed');
    return data;
  }

  function renderReady(box,sandbox){
    box.innerHTML=`<h3>Test Sandbox</h3><div class="sandbox-note">Admin-only reusable test environment. Reset clears the registered Sandbox business data and restores a clean baseline for the next test.</div><div class="sandbox-grid"><div class="sandbox-account"><b>Test Partner</b><span>${esc(EMAILS.partner)}</span></div><div class="sandbox-account"><b>Test Partner Staff</b><span>${esc(EMAILS.partnerStaff)}</span></div><div class="sandbox-account"><b>Test Evolution Staff</b><span>${esc(EMAILS.evolutionStaff)}</span></div><div class="sandbox-account"><b>Baseline</b><span>${esc(sandbox?.baseline_quantity||20)} vouchers • MINES • Staff Access ON</span></div></div><div class="sandbox-actions"><a href="${esc(partnerUrl)}" target="_blank" rel="noopener">Open Partner Portal</a><a href="${esc(staffUrl)}" target="_blank" rel="noopener">Open Staff Portal</a><button id="sandboxResetBtn" type="button" class="sandbox-danger">Reset Test Data</button></div><div id="sandboxMsg" class="sandbox-msg"></div>`;
    document.getElementById('sandboxResetBtn').onclick=async()=>{
      if(!confirm('Reset all Test Sandbox business data back to the clean baseline? Real Partner data will not be touched.'))return;
      const btn=document.getElementById('sandboxResetBtn'),msg=document.getElementById('sandboxMsg');
      btn.disabled=true;msg.className='sandbox-msg';msg.textContent='Resetting Test Sandbox…';
      try{
        const res=await invoke('reset');
        msg.className='sandbox-msg ok';
        msg.textContent=`Reset complete. Clean baseline restored to ${res.reset?.baseline_quantity||20} vouchers.`;
      }catch(e){msg.className='sandbox-msg err';msg.textContent=e?.message||'Reset failed.'}
      finally{btn.disabled=false}
    };
  }

  function renderSetup(box){
    box.innerHTML=`<h3>Test Sandbox</h3><div class="sandbox-note">Create one reusable Test Partner, one Test Partner Staff and one Test Evolution Staff account. Set one test password for all three accounts. The password is not stored in the Sandbox registry.</div><div class="sandbox-password"><label>Test Password</label><input id="sandboxPassword" type="password" minlength="8" autocomplete="new-password" placeholder="Minimum 8 characters"></div><div class="sandbox-actions"><button id="sandboxInitBtn" type="button">Initialize Sandbox</button></div><div id="sandboxMsg" class="sandbox-msg"></div>`;
    document.getElementById('sandboxInitBtn').onclick=async()=>{
      const input=document.getElementById('sandboxPassword'),btn=document.getElementById('sandboxInitBtn'),msg=document.getElementById('sandboxMsg');
      const password=input.value;
      if(password.length<8){msg.className='sandbox-msg err';msg.textContent='Test password must be at least 8 characters.';return}
      if(!confirm('Initialize the reusable Test Sandbox now?'))return;
      btn.disabled=true;msg.className='sandbox-msg';msg.textContent='Creating Test Sandbox…';
      try{
        await invoke('setup',{password});
        input.value='';
        msg.className='sandbox-msg ok';msg.textContent='Test Sandbox initialized. Use the password you just set for all three test accounts.';
        setTimeout(load,500);
      }catch(e){msg.className='sandbox-msg err';msg.textContent=e?.message||'Sandbox setup failed.'}
      finally{btn.disabled=false}
    };
  }

  async function load(){
    const box=document.getElementById('testSandboxBox');
    if(!box)return;
    try{
      const data=await invoke('status');
      if(data?.sandbox?.configured===true)renderReady(box,data.sandbox);else renderSetup(box);
    }catch(e){box.innerHTML=`<h3>Test Sandbox</h3><div class="sandbox-msg err">${esc(e?.message||'Unable to load Test Sandbox status.')}</div>`}
  }

  function mount(){
    const card=document.getElementById('adminSettingsCard');
    if(!card)return false;
    if(document.getElementById('testSandboxBox'))return true;
    ensureStyle();
    const box=document.createElement('div');box.id='testSandboxBox';box.className='sandbox-box';box.innerHTML='<h3>Test Sandbox</h3><div class="sandbox-note">Loading…</div>';
    card.appendChild(box);load();return true;
  }

  if(mount())return;
  const observer=new MutationObserver(()=>{if(mount())observer.disconnect()});
  observer.observe(document.documentElement,{childList:true,subtree:true});
})();