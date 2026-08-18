Deno.serve(() => new Response(JSON.stringify({success:false,error:'Admin bootstrap is permanently disabled.'}), {status:410,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}}));
