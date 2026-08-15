-- Static contract for serialized Voucher Version publishing.
-- Runtime concurrent publication is exercised separately before cutover.

select to_regprocedure('public.admin_publish_voucher_version_theme(uuid,text,numeric,numeric,text,integer,integer,numeric,numeric,integer,boolean,text,integer,boolean,text)') as publish_rpc;

do $$
declare
  v_src text;
  v_compact text;
begin
  select pg_get_functiondef('public.admin_publish_voucher_version_theme(uuid,text,numeric,numeric,text,integer,integer,numeric,numeric,integer,boolean,text,integer,boolean,text)'::regprocedure)
  into v_src;
  v_compact := lower(regexp_replace(v_src,'\s+','','g'));

  if position('forupdate' in v_compact)=0 then
    raise exception 'Publish RPC must serialize on the voucher template row before allocating version_no';
  end if;

  if position('max(version_no)' in v_compact)=0 then
    raise exception 'Publish RPC no longer derives the next version number from canonical voucher_versions';
  end if;

  if position('wherevt.id=p_template_id' in v_compact)=0 then
    raise exception 'Publish RPC template lock is not scoped to p_template_id';
  end if;
end;
$$;

select
  has_function_privilege('anon','public.admin_publish_voucher_version_theme(uuid,text,numeric,numeric,text,integer,integer,numeric,numeric,integer,boolean,text,integer,boolean,text)','EXECUTE') as anon_execute,
  has_function_privilege('authenticated','public.admin_publish_voucher_version_theme(uuid,text,numeric,numeric,text,integer,integer,numeric,numeric,integer,boolean,text,integer,boolean,text)','EXECUTE') as authenticated_execute;
