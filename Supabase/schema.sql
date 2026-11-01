-- Hogar Finanzas. Ejecutar una vez en un proyecto Supabase dedicado.
-- Ninguna service_role key se incluye en la app. Todas las operaciones derivan el actor de auth.uid().
begin;
create schema if not exists hogar_private;
revoke all on schema hogar_private from public, anon, authenticated;
create table hogar_private.households (
 id uuid primary key default gen_random_uuid(), data jsonb not null, revision bigint not null default 0 check(revision>=0)
);
create table hogar_private.members (
 home uuid not null references hogar_private.households(id) on delete cascade,
 user_id uuid not null references auth.users(id), name text not null check(length(name) between 1 and 100),
 role text not null check(role in ('admin','member')), active boolean not null default true,
 primary key(home,user_id)
);
create table hogar_private.receipts (
 home uuid not null references hogar_private.households(id) on delete cascade, operation uuid not null,
 actor uuid not null, fingerprint bytea not null, revision bigint not null,
 primary key(home,operation)
);
create table hogar_private.invites (
 id uuid primary key default gen_random_uuid(), home uuid not null references hogar_private.households(id) on delete cascade,
 email text not null, token_hash bytea not null unique, expires_at timestamptz not null default(now()+interval '7 days'),
 accepted_by uuid, revoked boolean not null default false
);
alter table hogar_private.households enable row level security;
alter table hogar_private.members enable row level security;
alter table hogar_private.receipts enable row level security;
alter table hogar_private.invites enable row level security;
revoke all on all tables in schema hogar_private from public,anon,authenticated;

create function hogar_private.actor() returns uuid language plpgsql stable security definer set search_path='' as $$
declare u uuid:=auth.uid();
begin
 if u is null then raise exception using errcode='PT401',message='authentication_required'; end if;
 if not exists(select 1 from auth.users where id=u and email_confirmed_at is not null) then
  raise exception using errcode='PT403',message='email_unconfirmed';
 end if;
 return u;
end $$;
create function hogar_private.authorize(h uuid, admin_required boolean default false) returns uuid language plpgsql stable security definer set search_path='' as $$
declare u uuid:=hogar_private.actor();
begin
 if not exists(select 1 from hogar_private.members where home=h and user_id=u and active) then
  raise exception using errcode='PT403',message='access_revoked';
 end if;
 if admin_required and not exists(select 1 from hogar_private.members where home=h and user_id=u and active and role='admin') then
  raise exception using errcode='PT403',message='admin_required';
 end if;
 return u;
end $$;
create function hogar_private.decorate(h uuid, d jsonb) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_set(d,'{members}',coalesce((select jsonb_agg(jsonb_build_object('id',user_id,'name',name,'role',role,'active',active) order by user_id)
 from hogar_private.members where home=h),'[]'::jsonb))
$$;
create function hogar_private.trimmed(v text) returns text language sql immutable set search_path='' as $$
 select btrim(v,U&' \0009\000a\000b\000c\000d\0085\00a0\1680\180e\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200a\200b\2028\2029\202f\205f\3000\feff')
$$;
create function hogar_private.is_text(v jsonb, limit_length integer default 1000, allow_empty boolean default false) returns boolean language sql immutable set search_path='' as $$
 select coalesce(jsonb_typeof(v)='string' and length(v#>>'{}')<=limit_length and (allow_empty or length(hogar_private.trimmed(v#>>'{}'))>0),false)
$$;
create function hogar_private.money(v jsonb, positive boolean default false) returns numeric language plpgsql immutable set search_path='' as $$
declare n numeric;
begin
 if jsonb_typeof(v) is distinct from 'object' or v-array['cents'] <> '{}'::jsonb or jsonb_typeof(v->'cents') is distinct from 'number' or (v->>'cents') !~ '^-?[0-9]+$' then
  raise exception using errcode='PT422',message='invalid_money';
 end if;
 n:=(v->>'cents')::numeric;
 if abs(n)>9000000000000 or (positive and n<=0) then raise exception using errcode='PT422',message='invalid_money'; end if;
 return n;
end $$;
create function hogar_private.tag_key(v text) returns text language sql immutable set search_path='' as $$
 select translate(regexp_replace(normalize(hogar_private.trimmed(v),NFD),U&'[\0300-\036f]','','g'),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz')
$$;
create function hogar_private.validate(h uuid,d jsonb) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb; b jsonb; t jsonb; k text; n numeric; target numeric; reserved numeric; ids uuid[]; member_ids uuid[]; keys text[];
begin
 if jsonb_typeof(d) is distinct from 'object' or jsonb_typeof(d->'schema') is distinct from 'number' or (d->>'schema')::int is distinct from 1 or (d->>'id')::uuid is distinct from h or
 not hogar_private.is_text(d->'name') or octet_length(d::text)>16777216 or
 d-array['schema','id','name','members','accounts','entries','budgets','goals','appliedOperations']<>'{}'::jsonb then
  raise exception using errcode='PT422',message='invalid_data';
 end if;
 foreach k in array array['accounts','entries','budgets','goals'] loop
  if jsonb_typeof(d->k) is distinct from 'array' or jsonb_array_length(d->k)>(case when k in ('accounts','goals') then 1000 else 100000 end) then
   raise exception using errcode='PT422',message='invalid_data';
  end if;
  if (select count(*)<>count(distinct (value->>'id')::uuid) or count(*)<>count(value->>'id') from jsonb_array_elements(d->k)) then
   raise exception using errcode='PT422',message='duplicate_id';
  end if;
 end loop;
 select array_agg(user_id) into member_ids from hogar_private.members where home=h;
 select coalesce(array_agg((value->>'id')::uuid),array[]::uuid[]) into ids from jsonb_array_elements(d->'accounts');
 for a in select value from jsonb_array_elements(d->'accounts') loop
  if a-array['id','name','kind','opening']<>'{}'::jsonb or not hogar_private.is_text(a->'name') or (a->>'kind') not in ('Banco','Efectivo','Ahorro') or a->>'kind' is null then raise exception using errcode='PT422',message='invalid_account'; end if;
  perform hogar_private.money(a->'opening');
 end loop;
 for a in select value from jsonb_array_elements(d->'entries') loop
  if a-array['id','authorID','memberID','accountID','destinationID','kind','amount','date','category','title','notes','tags','revision','deleted']<>'{}'::jsonb or not coalesce((a->>'memberID')::uuid=any(member_ids),false) or
   (a->>'authorID' is not null and not coalesce((a->>'authorID')::uuid=any(member_ids),false)) or
   not coalesce((a->>'accountID')::uuid=any(ids),false) or not hogar_private.is_text(a->'title') or not hogar_private.is_text(a->'notes',1000,true) or
   jsonb_typeof(a->'revision') is distinct from 'number' or jsonb_typeof(a->'deleted') is distinct from 'boolean' or jsonb_typeof(a->'date') is distinct from 'number' or
   not coalesce((a->>'date')::numeric between -3187296000 and 252423907200,false) or
   not coalesce((a->>'revision')::int between 0 and 1000000,false) or (a->>'revision') !~ '^[0-9]+$' or
   not coalesce(a->>'kind' in ('Ingreso','Gasto','Transferencia'),false) or
   not coalesce(a->>'category' in ('Vivienda','Alimentación','Transporte','Salud','Educación','Ocio','Suscripciones','Otros'),false) then
   raise exception using errcode='PT422',message='invalid_entry';
  end if;
  perform hogar_private.money(a->'amount',true);
  if a->>'kind'='Transferencia' then
   if not coalesce((a->>'destinationID')::uuid=any(ids),false) or (a->>'destinationID')::uuid=(a->>'accountID')::uuid then raise exception using errcode='PT422',message='invalid_transfer'; end if;
  elsif a->>'destinationID' is not null then raise exception using errcode='PT422',message='invalid_transfer'; end if;
  if jsonb_typeof(a->'tags') is distinct from 'array' or jsonb_array_length(a->'tags')>10 then raise exception using errcode='PT422',message='invalid_tags'; end if;
  keys:=array[]::text[];
  for t in select value from jsonb_array_elements(a->'tags') loop
   if not hogar_private.is_text(t,32) or (t#>>'{}')<>hogar_private.trimmed(t#>>'{}') or (t#>>'{}') ~ U&'[[:cntrl:],\00ad\0600-\0605\061c\06dd\070f\0890-\0891\08e2\180e\200b-\200f\202a-\202e\2060-\206f\feff\fff9-\fffb\+0110bd\+0110cd\+013430-\+013455\+01bca0-\+01bca3\+01d173-\+01d17a\+0e0001\+0e0020-\+0e007f]' or hogar_private.tag_key(t#>>'{}')=any(keys) then
    raise exception using errcode='PT422',message='invalid_tags';
   end if;
   keys:=array_append(keys,hogar_private.tag_key(t#>>'{}'));
  end loop;
 end loop;
 if (select count(*)<>count(distinct ((value->'month'->>'year')::int,(value->'month'->>'month')::int,value->>'category')) from jsonb_array_elements(d->'budgets')) then raise exception using errcode='PT422',message='duplicate_budget'; end if;
 for a in select value from jsonb_array_elements(d->'budgets') loop
  if a-array['id','month','category','limit']<>'{}'::jsonb or (a->'month')-array['year','month']<>'{}'::jsonb or jsonb_typeof(a->'month'->'year') is distinct from 'number' or jsonb_typeof(a->'month'->'month') is distinct from 'number' or not coalesce((a->'month'->>'year')::int between 1900 and 9999,false) or not coalesce((a->'month'->>'month')::int between 1 and 12,false) or
   not coalesce(a->>'category' in ('Vivienda','Alimentación','Transporte','Salud','Educación','Ocio','Suscripciones','Otros'),false) or
   (a->'month'->>'year') !~ '^[0-9]+$' or (a->'month'->>'month') !~ '^[0-9]+$' then raise exception using errcode='PT422',message='invalid_budget'; end if;
 
  perform hogar_private.money(a->'limit',true);
 end loop;
 for a in select value from jsonb_array_elements(d->'goals') loop
  target:=hogar_private.money(a->'target',true); reserved:=hogar_private.money(a->'reserved');
  if a-array['id','name','target','reserved','due']<>'{}'::jsonb or not hogar_private.is_text(a->'name') or reserved<0 or reserved>target or jsonb_typeof(a->'due') is distinct from 'number' or not coalesce((a->>'due')::numeric between -3187296000 and 252423907200,false) then raise exception using errcode='PT422',message='invalid_goal'; end if;
 end loop;
exception when invalid_text_representation or numeric_value_out_of_range then raise exception using errcode='PT422',message='invalid_data';
end $$;

create function public.family_create(p_name text,p_display_name text,p_id uuid default gen_random_uuid()) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=hogar_private.actor(); h uuid:=p_id; d jsonb; r bigint;
begin
 if h is null then raise exception using errcode='PT422',message='invalid_data'; end if;
 perform pg_advisory_xact_lock(hashtextextended(h::text,0));
 if exists(select 1 from hogar_private.households where id=h) then
  perform hogar_private.authorize(h,true);
  select data,revision into d,r from hogar_private.households where id=h;
  return jsonb_build_object('revision',r,'household',hogar_private.decorate(h,d));
 end if;
 if not hogar_private.is_text(to_jsonb(p_name)) or not hogar_private.is_text(to_jsonb(p_display_name),100) then raise exception using errcode='PT422',message='invalid_data'; end if;
 if (select count(*) from hogar_private.members where user_id=u and active)>=10 then raise exception using errcode='PT422',message='limit_reached'; end if;
 d:=jsonb_build_object('schema',1,'id',h,'name',p_name,'members','[]'::jsonb,'accounts','[]'::jsonb,'entries','[]'::jsonb,'budgets','[]'::jsonb,'goals','[]'::jsonb,'appliedOperations','[]'::jsonb);
 insert into hogar_private.households(id,data) values(h,d);
 insert into hogar_private.members values(h,u,p_display_name,'admin',true);
 return jsonb_build_object('revision',0,'household',hogar_private.decorate(h,d));
end $$;
create function public.family_list() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare u uuid:=hogar_private.actor();
begin
 return coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'name',h.data->>'name','role',m.role) order by h.id) from hogar_private.households h join hogar_private.members m on m.home=h.id where m.user_id=u and m.active),'[]'::jsonb);
end $$;
create function public.family_get(p_home uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d jsonb; r bigint;
begin
 perform hogar_private.authorize(p_home);
 select data,revision into d,r from hogar_private.households where id=p_home;
 return jsonb_build_object('revision',r,'household',hogar_private.decorate(p_home,d));
end $$;
create function public.family_commit(p_home uuid,p_operation uuid,p_expected bigint,p_snapshot jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=hogar_private.actor(); h hogar_private.households%rowtype; receipt hogar_private.receipts%rowtype;
 d jsonb; old_entry jsonb; e jsonb; admin boolean; old_reserved numeric; new_reserved numeric; balance numeric; increased boolean; fingerprint bytea; old_entries jsonb; new_entries jsonb;
begin
 -- Todas las mutaciones de un hogar, incluidas las de miembros, bloquean esta misma fila.
 select * into h from hogar_private.households where id=p_home for update;
 perform hogar_private.authorize(p_home);
 if octet_length(p_snapshot::text)>16777216 then raise exception using errcode='PT422',message='limit_reached'; end if;
 fingerprint:=sha256(convert_to(p_snapshot::text,'UTF8'));
 select * into receipt from hogar_private.receipts where home=p_home and operation=p_operation;
 if found then
  if receipt.actor<>u or receipt.fingerprint<>fingerprint then raise exception using errcode='PT409',message='operation_reused'; end if;
  return jsonb_build_object('operationID',p_operation,'revision',receipt.revision);
 end if;
 if p_operation is null or p_expected is distinct from h.revision then raise exception using errcode='PT409',message='conflict'; end if;
 d:=hogar_private.decorate(p_home,jsonb_set(jsonb_set(p_snapshot,'{id}',to_jsonb(p_home)),'{appliedOperations}','[]'::jsonb));
 select role='admin' into admin from hogar_private.members where home=p_home and user_id=u;
 if not admin and (d-array['entries','members','appliedOperations']) is distinct from (h.data-array['entries','members','appliedOperations']) then raise exception using errcode='PT403',message='admin_required'; end if;
 perform hogar_private.validate(p_home,d);
 select coalesce(jsonb_object_agg(((value->>'id')::uuid)::text,value),'{}'::jsonb) into old_entries from jsonb_array_elements(h.data->'entries');
 select coalesce(jsonb_object_agg(((value->>'id')::uuid)::text,value),'{}'::jsonb) into new_entries from jsonb_array_elements(d->'entries');
 for old_entry in select value from jsonb_array_elements(h.data->'entries') loop
  e:=new_entries->((old_entry->>'id')::uuid)::text;
  if e is null then raise exception using errcode='PT422',message='tombstone_required'; end if;
 end loop;
 for e in select value from jsonb_array_elements(d->'entries') loop
  old_entry:=old_entries->((e->>'id')::uuid)::text;
  if old_entry is null then
   if ((e->>'authorID')::uuid is distinct from u and not(admin and e->>'authorID' is null)) or (e->>'revision')::int<>0 or (e->>'deleted')::boolean then raise exception using errcode='PT403',message='author_required'; end if;
  elsif old_entry is distinct from e then
   if not admin and (old_entry->>'authorID')::uuid is distinct from u then raise exception using errcode='PT403',message='author_required'; end if;
   if (old_entry->>'deleted')::boolean or (e->>'authorID')::uuid is distinct from (old_entry->>'authorID')::uuid or (e->>'revision')::int<>(old_entry->>'revision')::int+1 then raise exception using errcode='PT409',message='entry_conflict'; end if;
  else continue;
  end if;
  if (old_entry is null or (e->>'memberID')::uuid is distinct from (old_entry->>'memberID')::uuid) and not exists(select 1 from hogar_private.members where home=p_home and user_id=(e->>'memberID')::uuid and active) then raise exception using errcode='PT422',message='inactive_attribution'; end if;
 end loop;
 select coalesce(sum(hogar_private.money(value->'reserved')),0) into new_reserved from jsonb_array_elements(d->'goals');
 select coalesce(sum(hogar_private.money(value->'opening')),0) into balance from jsonb_array_elements(d->'accounts');
 select balance+coalesce(sum(case value->>'kind' when 'Ingreso' then hogar_private.money(value->'amount') when 'Gasto' then -hogar_private.money(value->'amount') else 0 end),0) into balance from jsonb_array_elements(d->'entries') where not(value->>'deleted')::boolean;
 select exists(select 1 from jsonb_array_elements(d->'goals') n where hogar_private.money(n->'reserved')>coalesce((select hogar_private.money(o->'reserved') from jsonb_array_elements(h.data->'goals') o where (o->>'id')::uuid=(n->>'id')::uuid),0)) into increased;
 if increased and new_reserved>balance then raise exception using errcode='PT422',message='insufficient_unreserved'; end if;
 update hogar_private.households set data=d,revision=revision+1 where id=p_home;
 insert into hogar_private.receipts values(p_home,p_operation,u,fingerprint,h.revision+1);
 return jsonb_build_object('operationID',p_operation,'revision',h.revision+1);
end $$;

create function public.family_invite(p_home uuid,p_email text) returns jsonb language plpgsql security definer set search_path='' as $$
declare token text:=replace(gen_random_uuid()::text||gen_random_uuid()::text,'-',''); i hogar_private.invites%rowtype;
begin
 perform 1 from hogar_private.households where id=p_home for update;
 perform hogar_private.authorize(p_home,true);
 if p_email is null or length(p_email)>254 or btrim(p_email) !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception using errcode='PT422',message='invalid_email'; end if;
 if (select count(*) from hogar_private.invites where home=p_home and not revoked and accepted_by is null and expires_at>now())>=20 then raise exception using errcode='PT422',message='limit_reached'; end if;
 insert into hogar_private.invites(home,email,token_hash) values(p_home,lower(btrim(p_email)),sha256(convert_to(token,'UTF8'))) returning * into i;
 return jsonb_build_object('id',i.id,'token',token,'email',i.email,'expiresAt',extract(epoch from i.expires_at));
end $$;
create function public.family_accept(p_token text,p_display_name text) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=hogar_private.actor(); i hogar_private.invites%rowtype; email text; h uuid;
begin
 if p_token is null or p_token !~ '^[0-9a-f]{64}$' or not hogar_private.is_text(to_jsonb(p_display_name),100) then raise exception using errcode='PT422',message='invalid_invite'; end if;
 select home into h from hogar_private.invites where token_hash=sha256(convert_to(p_token,'UTF8'));
 perform 1 from hogar_private.households where id=h for update;
 select * into i from hogar_private.invites where token_hash=sha256(convert_to(p_token,'UTF8')) for update;
 select lower(auth.users.email) into email from auth.users where id=u;
 if i.id is null or i.revoked or i.expires_at<=now() or i.email<>email or (i.accepted_by is not null and i.accepted_by<>u) then raise exception using errcode='PT422',message='invalid_invite'; end if;
 if i.accepted_by=u then
  perform hogar_private.authorize(h);
  return public.family_get(h);
 end if;
 if (select count(*) from hogar_private.members where home=h)>=1000 then raise exception using errcode='PT422',message='limit_reached'; end if;
 if exists(select 1 from hogar_private.members where home=h and user_id=u and active) then
  update hogar_private.invites set accepted_by=u where id=i.id;
  return public.family_get(h);
 end if;
 insert into hogar_private.members values(h,u,p_display_name,'member',true)
 on conflict(home,user_id) do update set active=true,name=excluded.name,role='member';
 update hogar_private.invites set accepted_by=u where id=i.id;
 update hogar_private.households set revision=revision+1 where id=h;
 return public.family_get(h);
end $$;
create function public.family_membership(p_home uuid,p_user uuid,p_role text,p_active boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=hogar_private.actor(); old hogar_private.members%rowtype;
begin
 perform 1 from hogar_private.households where id=p_home for update;
 perform hogar_private.authorize(p_home);
 select * into old from hogar_private.members where home=p_home and user_id=p_user;
 if old.user_id is null or p_active is null or p_role not in ('admin','member') or p_role is null then raise exception using errcode='PT422',message='invalid_member'; end if;
 if not(u=p_user and not p_active and p_role=old.role) then perform hogar_private.authorize(p_home,true); end if;
 if old.active and old.role='admin' and (not p_active or p_role<>'admin') and
  (select count(*) from hogar_private.members where home=p_home and active and role='admin')<=1 then raise exception using errcode='PT422',message='last_admin'; end if;
 update hogar_private.members set role=p_role,active=p_active where home=p_home and user_id=p_user;
 update hogar_private.households set revision=revision+1 where id=p_home;
 return jsonb_build_object('ok',true);
end $$;
create function public.family_invitations(p_home uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform hogar_private.authorize(p_home,true);
 return coalesce((select jsonb_agg(jsonb_build_object('id',id,'email',email,'expiresAt',extract(epoch from expires_at))) from hogar_private.invites where home=p_home and not revoked and accepted_by is null and expires_at>now()),'[]'::jsonb);
end $$;
create function public.family_cancel_invite(p_home uuid,p_invite uuid) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform 1 from hogar_private.households where id=p_home for update;
 perform hogar_private.authorize(p_home,true);
 update hogar_private.invites set revoked=true where home=p_home and id=p_invite;
 return jsonb_build_object('ok',true);
end $$;
-- No hay acceso directo a tablas. Las funciones privadas tampoco son invocables por clientes.
revoke all on all functions in schema hogar_private from public,anon,authenticated;
revoke all on function public.family_create(text,text,uuid),public.family_list(),public.family_get(uuid),public.family_commit(uuid,uuid,bigint,jsonb),public.family_invite(uuid,text),public.family_accept(text,text),public.family_membership(uuid,uuid,text,boolean),public.family_invitations(uuid),public.family_cancel_invite(uuid,uuid) from public,anon;
grant execute on function public.family_create(text,text,uuid),public.family_list(),public.family_get(uuid),public.family_commit(uuid,uuid,bigint,jsonb),public.family_invite(uuid,text),public.family_accept(text,text),public.family_membership(uuid,uuid,text,boolean),public.family_invitations(uuid),public.family_cancel_invite(uuid,uuid) to authenticated;
notify pgrst, 'reload schema';
commit;
