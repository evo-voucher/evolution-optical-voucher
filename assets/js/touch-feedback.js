(()=>{
  if(window.__evolutionTouchFeedbackInstalled)return;
  Object.defineProperty(window,'__evolutionTouchFeedbackInstalled',{value:true});

  const style=document.createElement('style');
  style.id='evolutionTouchFeedbackStyle';
  style.textContent=`
    :where(button,.btn,a.card,.tool,[role="button"],.moduleBtn,.listToggle,.directoryToggle,.reportCardBtn,.shareLink){
      touch-action:manipulation!important;
      -webkit-tap-highlight-color:transparent!important;
      -webkit-user-select:none!important;
      user-select:none!important;
      cursor:pointer;
      transition:transform 70ms ease,filter 70ms ease,box-shadow 70ms ease,border-color 70ms ease!important;
    }
    :where(button,.btn,[role="button"],.listToggle,.directoryToggle,.shareLink){min-height:46px}
    :where(button,.btn,a.card,.tool,[role="button"],.moduleBtn,.listToggle,.directoryToggle,.reportCardBtn,.shareLink).evoTouchPressed{
      transform:translateY(1px) scale(.985)!important;
      filter:brightness(1.12)!important;
    }
    :where(button,.btn,a.card,.tool,[role="button"],.moduleBtn,.listToggle,.directoryToggle,.reportCardBtn,.shareLink):focus-visible{
      outline:2px solid rgba(112,228,238,.9)!important;
      outline-offset:2px!important;
    }
  `;
  document.head.appendChild(style);

  const selector='button,.btn,a.card,.tool,[role="button"],.moduleBtn,.listToggle,.directoryToggle,.reportCardBtn,.shareLink';
  const pressed=new Set();
  const release=el=>{if(!el)return;el.classList.remove('evoTouchPressed');pressed.delete(el)};

  document.addEventListener('pointerdown',e=>{
    if(e.pointerType==='mouse'&&e.button!==0)return;
    const el=e.target.closest?.(selector);
    if(!el||el.matches(':disabled,[aria-disabled="true"]'))return;
    el.classList.add('evoTouchPressed');
    pressed.add(el);
  },{passive:true,capture:true});

  ['pointerup','pointercancel','pointerout'].forEach(type=>document.addEventListener(type,e=>{
    const el=e.target.closest?.(selector);
    if(el)release(el);
  },{passive:true,capture:true}));

  window.addEventListener('blur',()=>{pressed.forEach(release);pressed.clear()});
})();