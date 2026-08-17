(()=>{
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!path.endsWith('/admin.html'))return;

  function install(){
    const ids=['email','password','setupEmail','setupPassword','setupCode'];
    const inputs=ids.map(id=>document.getElementById(id)).filter(Boolean);
    if(!inputs.length)return;

    if(!document.getElementById('adminMobileFocusStyle')){
      const style=document.createElement('style');
      style.id='adminMobileFocusStyle';
      style.textContent=`
        #authState input{
          position:relative!important;
          z-index:4!important;
          pointer-events:auto!important;
          -webkit-user-select:text!important;
          user-select:text!important;
          touch-action:manipulation!important;
          -webkit-appearance:none;
        }
        #authState .field{position:relative!important;z-index:3!important}
      `;
      document.head.appendChild(style);
    }

    inputs.forEach(input=>{
      if(input.dataset.mobileFocusReady==='1')return;
      input.dataset.mobileFocusReady='1';
      input.addEventListener('touchend',()=>{
        if(document.activeElement!==input){
          try{input.focus({preventScroll:false});}catch(_){input.focus();}
        }
      },{passive:true});
      input.addEventListener('pointerup',()=>{
        if(document.activeElement!==input){
          try{input.focus({preventScroll:false});}catch(_){input.focus();}
        }
      },{passive:true});
    });
  }

  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install,{once:true});
  else install();
})();