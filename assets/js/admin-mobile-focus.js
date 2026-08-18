(()=>{
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!path.endsWith('/admin.html'))return;

  const INPUT_SELECTOR='input:not([type="hidden"]):not([type="checkbox"]):not([type="radio"]):not([type="button"]):not([type="submit"]):not([type="file"]), textarea';

  function installStyle(){
    if(document.getElementById('adminMobileFocusStyle'))return;
    const style=document.createElement('style');
    style.id='adminMobileFocusStyle';
    style.textContent=`
      ${INPUT_SELECTOR}{
        position:relative!important;
        z-index:4!important;
        pointer-events:auto!important;
        -webkit-user-select:text!important;
        user-select:text!important;
        touch-action:manipulation!important;
      }
      .field{position:relative}
      body.admin-keyboard-open{padding-bottom:max(18px,env(safe-area-inset-bottom))!important}
    `;
    document.head.appendChild(style);
  }

  function installPartnerCredentialHints(root=document){
    const email=root.querySelector?.('#newPartnerEmail')||(root.id==='newPartnerEmail'?root:null);
    const password=root.querySelector?.('#newPartnerPassword')||(root.id==='newPartnerPassword'?root:null);
    if(email){
      email.setAttribute('autocomplete','off');
      email.setAttribute('autocapitalize','none');
      email.setAttribute('spellcheck','false');
      email.setAttribute('data-lpignore','true');
      email.setAttribute('data-1p-ignore','true');
    }
    if(password){
      password.setAttribute('autocomplete','new-password');
      password.setAttribute('data-lpignore','true');
      password.setAttribute('data-1p-ignore','true');
    }
  }

  function reveal(input){
    setTimeout(()=>{
      if(document.activeElement!==input)return;
      try{input.scrollIntoView({behavior:'smooth',block:'center',inline:'nearest'});}catch(_){input.scrollIntoView();}
    },220);
  }

  function prepare(input){
    if(!input||input.dataset.mobileFocusReady==='1')return;
    input.dataset.mobileFocusReady='1';
    const focus=()=>{
      if(document.activeElement!==input){
        try{input.focus({preventScroll:false});}catch(_){input.focus();}
      }
      reveal(input);
    };
    input.addEventListener('touchend',focus,{passive:true});
    input.addEventListener('pointerup',focus,{passive:true});
    input.addEventListener('focus',()=>reveal(input),{passive:true});
  }

  function installInputs(root=document){
    installPartnerCredentialHints(root);
    if(root.matches?.(INPUT_SELECTOR))prepare(root);
    root.querySelectorAll?.(INPUT_SELECTOR).forEach(prepare);
  }

  function installViewportGuard(){
    if(!window.visualViewport||document.body.dataset.mobileViewportGuard==='1')return;
    document.body.dataset.mobileViewportGuard='1';
    const vv=window.visualViewport;
    let baseHeight=vv.height;
    const sync=()=>{
      if(vv.height>baseHeight)baseHeight=vv.height;
      const keyboardOpen=baseHeight-vv.height>120;
      document.body.classList.toggle('admin-keyboard-open',keyboardOpen);
      if(keyboardOpen&&document.activeElement?.matches?.(INPUT_SELECTOR))reveal(document.activeElement);
    };
    vv.addEventListener('resize',sync,{passive:true});
    vv.addEventListener('scroll',sync,{passive:true});
  }

  function install(){
    installStyle();
    installInputs(document);
    installViewportGuard();
    const observer=new MutationObserver(mutations=>{
      mutations.forEach(m=>m.addedNodes.forEach(node=>{if(node.nodeType===1)installInputs(node);}));
    });
    observer.observe(document.body,{childList:true,subtree:true});
  }

  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install,{once:true});
  else install();
})();