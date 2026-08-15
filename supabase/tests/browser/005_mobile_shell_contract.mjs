import { spawn } from 'node:child_process';
import puppeteer from 'puppeteer-core';

const WEB_URL='http://127.0.0.1:4174';
const pages=['index.html','admin.html','partner.html','staff.html','admin-staff.html','admin-partner-password.html','voucher.html'];
const viewports=[
  {name:'compact-android',width:360,height:800},
  {name:'iphone-width',width:390,height:844},
  {name:'large-phone',width:430,height:932}
];

const server=spawn('python3',['-m','http.server','4174','--bind','127.0.0.1'],{cwd:process.cwd(),stdio:['ignore','ignore','inherit']});
let browser;
try{
  await new Promise(r=>setTimeout(r,500));
  browser=await puppeteer.launch({
    headless:true,
    executablePath:process.env.CHROME_PATH||'/usr/bin/google-chrome',
    args:['--no-sandbox','--disable-dev-shm-usage']
  });

  for(const viewport of viewports){
    const page=await browser.newPage();
    await page.setCacheEnabled(false);
    await page.setViewport({width:viewport.width,height:viewport.height,isMobile:true,hasTouch:true,deviceScaleFactor:2});
    for(const file of pages){
      const response=await page.goto(`${WEB_URL}/${file}`,{waitUntil:'networkidle0'});
      const status=response?.status();
      if(!response || (status!==200 && status!==304)) throw new Error(`${file} failed to load at ${viewport.name}: HTTP ${status}`);
      const metrics=await page.evaluate(()=>({
        innerWidth:window.innerWidth,
        docWidth:document.documentElement.scrollWidth,
        bodyWidth:document.body?.scrollWidth||0,
        hasViewportMeta:!!document.querySelector('meta[name="viewport"]')
      }));
      if(!metrics.hasViewportMeta) throw new Error(`${file} is missing viewport metadata`);
      const widest=Math.max(metrics.docWidth,metrics.bodyWidth);
      if(widest>metrics.innerWidth+1){
        throw new Error(`${file} horizontally overflows at ${viewport.name}: ${widest}px > ${metrics.innerWidth}px`);
      }
    }
    await page.close();
  }

  console.log(`Mobile shell contract passed across ${viewports.length} phone viewports and ${pages.length} operational/public pages.`);
} finally {
  if(browser) await browser.close();
  server.kill('SIGTERM');
}
