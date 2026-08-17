// Evolution Voucher frontend backend configuration.
// Production browser clients use the Supabase publishable key only.
window.EVOLUTION_VOUCHER_BACKEND = Object.freeze({
  enabled: true,
  environment: 'production',
  projectId: 'hukihbcyyqhanaqrizvm',
  supabaseUrl: 'https://hukihbcyyqhanaqrizvm.supabase.co',
  publishableKey: 'sb_publishable_kpPFeGYpedq2auo01Zo50A_aiSjdeVh',
  siteBase: 'https://evo-voucher.github.io/evolution-optical-voucher/'
});

// System-wide browser auth recovery for protected Edge Functions.
// Keeps authorization fail-closed: never disables JWT verification and retries at most once.
(function installResilientSupabaseClient(){
  const supabase=window.supabase;
  if(!supabase||typeof supabase.createClient!=='function'||supabase.__evolutionResilientClient)return;
  const originalCreateClient=supabase.createClient.bind(supabase);

  function errorStatus(error){
    const direct=Number(error?.status||error?.statusCode||0);
    if(direct)return direct;
    const context=error?.context;
    const fromContext=Number(context?.status||context?.statusCode||0);
    if(fromContext)return fromContext;
    return /\b401\b|unauthorized/i.test(String(error?.message||''))?401:0;
  }

  async function refreshIfPossible(client,force=false){
    const {data}=await client.auth.getSession();
    const session=data?.session;
    if(!session)return false;
    const expiresAt=Number(session.expires_at||0);
    const nearExpiry=expiresAt>0&&expiresAt*1000<=Date.now()+90000;
    if(!force&&!nearExpiry)return true;
    const {data:refreshed,error}=await client.auth.refreshSession();
    return !error&&!!refreshed?.session;
  }

  function wrapClient(client){
    if(!client?.functions||client.__evolutionAuthRecovery)return client;
    const originalInvoke=client.functions.invoke.bind(client.functions);
    client.functions.invoke=async function resilientInvoke(name,options){
      try{await refreshIfPossible(client,false)}catch(_){/* normal invoke remains authoritative */}
      let result=await originalInvoke(name,options);
      if(errorStatus(result?.error)!==401)return result;
      let refreshed=false;
      try{refreshed=await refreshIfPossible(client,true)}catch(_){refreshed=false}
      if(!refreshed)return result;
      result=await originalInvoke(name,options);
      return result;
    };
    Object.defineProperty(client,'__evolutionAuthRecovery',{value:true,enumerable:false});
    return client;
  }

  supabase.createClient=function createResilientClient(url,key,options={}){
    return wrapClient(originalCreateClient(url,key,options));
  };
  Object.defineProperty(supabase,'__evolutionResilientClient',{value:true,enumerable:false});
})();
