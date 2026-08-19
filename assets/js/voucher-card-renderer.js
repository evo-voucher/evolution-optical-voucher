// Evolution Voucher Card Renderer
// Presentation-only layer: converts an issued voucher payload into a customer-facing PNG.
// Business validation, token security, expiry and redemption remain backend responsibilities.
(function(){
  'use strict';

  const W=1080,H=1620,S=2;
  const C={navy:'#112b6a',blue:'#3556d6',purple:'#7b45da',ink:'#172554',muted:'#6f7894',line:'#dce4f4',soft:'#f5f8ff',softPurple:'#f5f1ff',white:'#ffffff'};
  const THEMES={
    classic:{bg:'#eef4ff',a:'#2547bd',b:'#543ac7',c:'#8a43dc',accent:'#7b45da',title:['FREE','GLASSES','VOUCHER'],gift:['A little gift','just for you'],symbol:'♡'},
    birthday:{bg:'#fff4fa',a:'#e94f9c',b:'#9b4dde',c:'#5b66e8',accent:'#d84f9e',title:['HAPPY','BIRTHDAY','VOUCHER'],gift:['A birthday gift','just for you'],symbol:'🎂'},
    raya:{bg:'#f1fbf5',a:'#11785d',b:'#1e9b72',c:'#d3a63a',accent:'#168766',title:['SELAMAT','HARI RAYA','VOUCHER'],gift:['A festive gift','just for you'],symbol:'☾'},
    merdeka:{bg:'#f4f8ff',a:'#163e91',b:'#d73a3a',c:'#f1b82d',accent:'#c52f3a',title:['MERDEKA','SPECIAL','VOUCHER'],gift:['A special gift','just for you'],symbol:'★'},
    christmas:{bg:'#fff7f7',a:'#a72f3f',b:'#c9414f',c:'#1f7a59',accent:'#b93649',title:['MERRY','CHRISTMAS','VOUCHER'],gift:['A festive gift','just for you'],symbol:'✦'}
  };
  const themeFor=value=>THEMES[String(value||'classic').trim().toLowerCase()]||THEMES.classic;
  const fmtDate=value=>{
    if(!value)return '—';
    const d=new Date(String(value).length===10?`${value}T00:00:00+08:00`:value);
    if(Number.isNaN(d.getTime()))return String(value);
    return d.toLocaleDateString('en-GB',{day:'2-digit',month:'short',year:'numeric',timeZone:'Asia/Kuala_Lumpur'});
  };
  const text=(ctx,value,x,y,size=28,weight=500,color=C.ink,align='left',font='Arial')=>{
    ctx.save();ctx.fillStyle=color;ctx.font=`${weight} ${size}px ${font}`;ctx.textAlign=align;ctx.textBaseline='alphabetic';ctx.fillText(String(value??''),x,y);ctx.restore();
  };
  const roundRect=(ctx,x,y,w,h,r,fill,stroke=null,lw=1)=>{
    const rr=Math.min(r,w/2,h/2);ctx.beginPath();ctx.moveTo(x+rr,y);ctx.arcTo(x+w,y,x+w,y+h,rr);ctx.arcTo(x+w,y+h,x,y+h,rr);ctx.arcTo(x,y+h,x,y,rr);ctx.arcTo(x,y,x+w,y,rr);ctx.closePath();if(fill){ctx.fillStyle=fill;ctx.fill()}if(stroke){ctx.strokeStyle=stroke;ctx.lineWidth=lw;ctx.stroke()}
  };
  const wrap=(ctx,str,maxWidth)=>{
    const words=String(str||'').split(/\s+/);const lines=[];let line='';
    for(const word of words){const next=line?`${line} ${word}`:word;if(ctx.measureText(next).width<=maxWidth||!line)line=next;else{lines.push(line);line=word}}
    if(line)lines.push(line);return lines;
  };
  const fitText=(ctx,str,maxWidth,start=27,min=17,weight=700)=>{
    let size=start;while(size>min){ctx.font=`${weight} ${size}px Arial`;if(ctx.measureText(String(str||'')).width<=maxWidth)break;size--}return size;
  };
  const gradient=(ctx,x,y,w,h,t)=>{const g=ctx.createLinearGradient(x,y,x+w,y+h);g.addColorStop(0,t.a);g.addColorStop(.55,t.b);g.addColorStop(1,t.c);return g};
  const branchGrid=(count)=>{
    if(count<=1)return [1];
    if(count===2)return [2];
    if(count===3)return [3];
    if(count===4)return [2,2];
    if(count===5)return [3,2];
    if(count===6)return [3,3];
    return [3,3,1];
  };
  const drawPin=(ctx,x,y,accent)=>{ctx.save();ctx.fillStyle=accent;ctx.beginPath();ctx.arc(x,y-5,10,0,Math.PI*2);ctx.fill();ctx.beginPath();ctx.moveTo(x-6,y);ctx.lineTo(x,y+13);ctx.lineTo(x+6,y);ctx.closePath();ctx.fill();ctx.fillStyle=C.white;ctx.beginPath();ctx.arc(x,y-5,3,0,Math.PI*2);ctx.fill();ctx.restore()};
  const drawGift=(ctx,x,y,w,h,t)=>{
    roundRect(ctx,x,y,w,h,26,'#f8f4ff','#e1d7f5',2);
    ctx.save();ctx.translate(x+70,y+55);ctx.strokeStyle=t.accent;ctx.lineWidth=7;ctx.beginPath();ctx.ellipse(50,75,44,20,0,0,Math.PI*2);ctx.ellipse(145,75,44,20,0,0,Math.PI*2);ctx.moveTo(94,75);ctx.lineTo(101,75);ctx.stroke();ctx.restore();
    roundRect(ctx,x+42,y+128,150,108,18,'#e8edff','#bac7ef',2);roundRect(ctx,x+98,y+108,38,145,8,t.c);
    text(ctx,t.gift[0],x+220,y+120,35,600,t.accent,'left','Georgia');text(ctx,t.gift[1],x+220,y+167,35,600,t.b,'left','Georgia');text(ctx,t.symbol,x+286,y+214,38,500,t.accent);
  };
  async function qrCanvas(value,size){
    const holder=document.createElement('div');holder.style.cssText='position:fixed;left:-9999px;top:-9999px;background:#fff';document.body.appendChild(holder);
    try{
      if(typeof window.QRCode!=='function')throw new Error('QR library unavailable');
      new window.QRCode(holder,{text:value,width:size,height:size,correctLevel:window.QRCode.CorrectLevel.M});
      await new Promise(r=>setTimeout(r,30));
      const canvas=holder.querySelector('canvas');if(canvas)return canvas;
      const img=holder.querySelector('img');if(img){if(!img.complete)await new Promise((r,j)=>{img.onload=r;img.onerror=j});const c=document.createElement('canvas');c.width=size;c.height=size;c.getContext('2d').drawImage(img,0,0,size,size);return c}
      throw new Error('QR render failed');
    }finally{holder.remove()}
  }
  async function render(data){
    const t=themeFor(data.theme_code);
    const canvas=document.createElement('canvas');canvas.width=W*S;canvas.height=H*S;const ctx=canvas.getContext('2d');ctx.scale(S,S);
    ctx.fillStyle=t.bg;ctx.fillRect(0,0,W,H);roundRect(ctx,24,24,W-48,H-48,44,C.white,'#d7e3f6',2);
    text(ctx,'Evolution Optical',W/2,105,48,800,C.navy,'center');text(ctx,'Sdn Bhd',W/2,145,27,600,t.accent,'center');
    roundRect(ctx,70,190,W-140,210,34,gradient(ctx,70,190,W-140,210,t));
    text(ctx,t.title[0],105,268,60,900,C.white);text(ctx,t.title[1],105,330,fitText(ctx,t.title[1],455,55,36,900),900,C.white);text(ctx,t.title[2],105,385,50,900,C.white);
    ctx.strokeStyle='rgba(255,255,255,.55)';ctx.lineWidth=2;ctx.beginPath();ctx.moveTo(605,230);ctx.lineTo(605,365);ctx.stroke();text(ctx,'VALUE',650,270,24,700,C.white);text(ctx,data.value_label||'VOUCHER',650,350,76,900,C.white);
    const boxY=430,boxW=(W-170)/2;roundRect(ctx,70,boxY,boxW,112,22,C.white,C.line,2);roundRect(ctx,100+boxW,boxY,boxW,112,22,C.white,C.line,2);text(ctx,'PARTNER',98,468,18,700,C.muted);text(ctx,data.partner_name||'—',98,514,fitText(ctx,data.partner_name||'—',boxW-55,30,19,800),800,C.ink);text(ctx,'CUSTOMER',128+boxW,468,18,700,C.muted);text(ctx,data.customer_name||'—',128+boxW,514,fitText(ctx,data.customer_name||'—',boxW-55,30,19,800),800,C.ink);
    roundRect(ctx,70,560,600,145,22,C.white,C.line,2);text(ctx,'VOUCHER CODE',98,603,18,700,C.muted);text(ctx,data.voucher_code||'—',98,661,fitText(ctx,data.voucher_code||'—',540,35,20,800),800,C.ink);
    roundRect(ctx,700,575,310,110,22,C.white,C.line,2);text(ctx,'VALID UNTIL',728,615,17,700,C.muted);text(ctx,fmtDate(data.expiry_date),728,659,28,800,C.ink);
    drawGift(ctx,70,735,500,270,t);
    roundRect(ctx,600,725,410,305,26,C.white,t.accent,3);const qr=await qrCanvas(data.qr_value,250);ctx.drawImage(qr,680,750,250,250);roundRect(ctx,625,1003,360,54,18,gradient(ctx,625,1003,360,54,t));text(ctx,'SCAN TO REDEEM',805,1039,21,800,C.white,'center');
    text(ctx,'⌖  REDEEM AT',70,1108,25,800,t.accent);ctx.strokeStyle=C.line;ctx.lineWidth=2;ctx.beginPath();ctx.moveTo(255,1100);ctx.lineTo(1005,1100);ctx.stroke();
    const branches=(Array.isArray(data.branches)?data.branches:[]).slice(0,7);const rows=branchGrid(branches.length);let idx=0,y=1140;const totalH=355;const rowH=rows.length?totalH/rows.length:totalH;
    for(const cols of rows){const gap=24,areaW=W-140,colW=(areaW-gap*(cols-1))/cols;for(let c=0;c<cols&&idx<branches.length;c++,idx++){const b=branches[idx],x=70+c*(colW+gap);if(cols===1&&rows.length>1){drawPin(ctx,x+8,y+18,t.accent);text(ctx,b.branch_name||b.branch_code||'Branch',x+28,y+23,23,800,C.ink);text(ctx,b.address||'',x+28,y+55,18,500,C.muted);text(ctx,b.phone?`Tel: ${String(b.phone).replace(/^Tel:\s*/i,'')}`:'',x+28,y+82,19,700,t.accent);continue}drawPin(ctx,x+8,y+18,t.accent);text(ctx,b.branch_name||b.branch_code||'Branch',x+28,y+23,fitText(ctx,b.branch_name||b.branch_code||'Branch',colW-38,22,15,800),800,C.ink);ctx.font='500 17px Arial';const lines=wrap(ctx,b.address||'',colW-28).slice(0,3);lines.forEach((ln,i)=>text(ctx,ln,x+8,y+52+i*22,17,500,C.muted));text(ctx,b.phone?`Tel: ${String(b.phone).replace(/^Tel:\s*/i,'')}`:'',x+8,y+52+Math.min(lines.length,3)*22+7,17,700,t.accent)}y+=rowH}
    roundRect(ctx,70,1515,W-140,64,24,gradient(ctx,70,1515,W-140,64,t));text(ctx,'One-time redemption only  •  Non-exchangeable for cash  •  T&C apply',W/2,1557,19,700,C.white,'center');
    return canvas;
  }
  const canvasToBlob=canvas=>new Promise((resolve,reject)=>canvas.toBlob(b=>b?resolve(b):reject(new Error('Unable to create voucher image')),'image/png',1));
  async function create(data){const canvas=await render(data);const blob=await canvasToBlob(canvas);const filename=`${String(data.voucher_code||'voucher').replace(/[^a-z0-9_-]+/gi,'_')}.png`;return{canvas,blob,filename,url:URL.createObjectURL(blob)}}
  async function copy(blob){if(!navigator.clipboard||typeof ClipboardItem==='undefined')throw new Error('Copy Image is not supported on this device/browser.');await navigator.clipboard.write([new ClipboardItem({'image/png':blob})])}
  async function share(blob,filename,shareText=''){const file=new File([blob],filename,{type:'image/png'});if(!navigator.share||!navigator.canShare?.({files:[file]}))throw new Error('Image sharing is not supported on this device/browser.');const payload={files:[file],title:'Evolution Optical Voucher'};if(String(shareText||'').trim())payload.text=String(shareText).trim();await navigator.share(payload)}
  function download(blob,filename){const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download=filename;document.body.appendChild(a);a.click();setTimeout(()=>{URL.revokeObjectURL(a.href);a.remove()},500)}
  window.EvolutionVoucherCard=Object.freeze({create,copy,share,download,branchGrid});
})();