(()=>{
  const path=String(window.location?.pathname||'').toLowerCase();
  if(!path.endsWith('/admin.html'))return;

  function finalizeOwnership(){
    const btn=document.getElementById('createPartnerBtn');
    if(!btn)return false;
    // Legacy admin-settings.js used the onclick property for the old password-required flow.
    // The canonical server-generated-password flow is registered with addEventListener
    // by portal-access-share.js. Clear only the legacy property handler after all scripts load.
    btn.onclick=null;
    btn.dataset.createPartnerOwner='server-generated-password';
    const password=document.getElementById('newPartnerPassword');
    password?.closest('.field')?.remove();
    return true;
  }

  const run=()=>{
    if(finalizeOwnership())return;
    let tries=0;
    const timer=setInterval(()=>{
      tries++;
      if(finalizeOwnership()||tries>80)clearInterval(timer);
    },100);
  };

  if(document.readyState==='complete')run();
  else window.addEventListener('load',run,{once:true});
})();
