-- Executar depois de criar e confirmar a conta Auth do proprietário.
DO $guard$ BEGIN IF (SELECT count(*) FROM auth.users) <> 1 THEN RAISE EXCEPTION 'Esperada exatamente uma conta: proprietário'; END IF; END $guard$;

-- FICHEIRO: migration_v241.sql
-- SpawnVault 2.4.1. Aplicar após migration_v24.sql.
-- Preserva UUIDs, emails, passwords, papéis, bloqueios e dados existentes.
BEGIN;
CREATE TABLE IF NOT EXISTS public.spawnvault_accounts (
 user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
 username text NOT NULL CHECK(username ~ '^[A-Za-z0-9_$][A-Za-z0-9._$-]{2,39}$'),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS spawnvault_username_unique ON public.spawnvault_accounts(lower(username));
ALTER TABLE public.spawnvault_accounts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.spawnvault_accounts FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.spawnvault_accounts TO authenticated;
GRANT ALL ON public.spawnvault_accounts TO service_role;
DROP POLICY IF EXISTS "SpawnVault account names" ON public.spawnvault_accounts;
CREATE POLICY "SpawnVault account names" ON public.spawnvault_accounts FOR SELECT TO authenticated
 USING(NOT public.spawnvault_is_blocked() AND (user_id=(SELECT auth.uid()) OR public.is_spawnvault_admin()));

-- Migração determinística dos nomes; colisões recebem um sufixo, sem perder contas.
DO $$ DECLARE u record; candidate text; stem text; n integer; BEGIN
 FOR u IN SELECT id,email,raw_user_meta_data FROM auth.users ORDER BY id LOOP
  IF EXISTS(SELECT 1 FROM public.spawnvault_accounts WHERE user_id=u.id) THEN CONTINUE; END IF;
  stem=left(regexp_replace(coalesce(nullif(btrim(u.raw_user_meta_data->>'username'),''),nullif(btrim(u.raw_user_meta_data->>'user_name'),''),nullif(split_part(u.email,'@',1),''),'user'),'[^A-Za-z0-9._$-]','_','g'),30);
  IF stem !~ '^[A-Za-z0-9_$]' THEN stem='u_'||stem; END IF;
  IF length(stem)<3 THEN stem='user_'||stem; END IF;
  candidate=stem;n=0;
  WHILE EXISTS(SELECT 1 FROM public.spawnvault_accounts WHERE lower(username)=lower(candidate)) LOOP
   n=n+1;candidate=left(stem,25)||'_'||left(replace(u.id::text,'-',''),8)||CASE WHEN n>1 THEN n::text ELSE '' END;
  END LOOP;
  INSERT INTO public.spawnvault_accounts(user_id,username) VALUES(u.id,candidate);
 END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.spawnvault_list_accounts()
RETURNS TABLE(user_id uuid,email text,role text,username text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT public.is_spawnvault_admin() THEN RAISE EXCEPTION 'Acesso não autorizado' USING ERRCODE='42501'; END IF;
 RETURN QUERY SELECT u.id,u.email::text,coalesce(r.role,'user')::text,a.username
 FROM auth.users u LEFT JOIN public.user_roles r ON r.user_id=u.id
 LEFT JOIN public.spawnvault_accounts a ON a.user_id=u.id ORDER BY lower(a.username),u.id;
END;
$$;
REVOKE ALL ON FUNCTION public.spawnvault_list_accounts() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.spawnvault_list_accounts() TO authenticated;

CREATE OR REPLACE FUNCTION public.spawnvault_set_username(target_user uuid,new_username text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE old_username text;
BEGIN
 PERFORM pg_catalog.pg_advisory_xact_lock(236023,1);
 IF NOT public.is_spawnvault_admin() THEN RAISE EXCEPTION 'Acesso não autorizado' USING ERRCODE='42501'; END IF;
 IF new_username IS NULL OR new_username !~ '^[A-Za-z0-9_$][A-Za-z0-9._$-]{2,39}$' THEN RAISE EXCEPTION 'Username inválido: usa 3 a 40 letras, números, ponto, _, $ ou -'; END IF;
 SELECT username INTO old_username FROM public.spawnvault_accounts WHERE user_id=target_user FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Utilizador inexistente'; END IF;
 UPDATE public.spawnvault_accounts SET username=new_username WHERE user_id=target_user;
 IF old_username IS DISTINCT FROM new_username THEN
  INSERT INTO public.item_audit(actor_id,actor_email,action,item_name)
  VALUES(auth.uid(),(SELECT email FROM auth.users WHERE id=auth.uid()),'users:USERNAME',old_username||' → '||new_username);
 END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.spawnvault_set_username(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.spawnvault_set_username(uuid,text) TO authenticated;

-- Apenas a função de servidor resolve usernames para emails. Nunca disponibiliza emails anónimos.
CREATE OR REPLACE FUNCTION public.spawnvault_resolve_login(login_username text)
RETURNS TABLE(user_id uuid,email text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT a.user_id,u.email::text FROM public.spawnvault_accounts a JOIN auth.users u ON u.id=a.user_id
 WHERE lower(a.username)=lower(login_username);
$$;
REVOKE ALL ON FUNCTION public.spawnvault_resolve_login(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.spawnvault_resolve_login(text) TO service_role;

-- Limites persistentes, partilhados por todas as instâncias da função de login.
CREATE TABLE IF NOT EXISTS public.spawnvault_login_limits (
 bucket text PRIMARY KEY,window_start timestamptz NOT NULL,hits integer NOT NULL
);
ALTER TABLE public.spawnvault_login_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.spawnvault_login_limits FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.spawnvault_take_login_limit(bucket_key text,max_hits integer)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE count_hits integer;
BEGIN
 IF length(bucket_key)>150 OR max_hits NOT IN (20,60) THEN RAISE EXCEPTION 'Limite inválido'; END IF;
 INSERT INTO public.spawnvault_login_limits(bucket,window_start,hits) VALUES(bucket_key,now(),1)
 ON CONFLICT(bucket) DO UPDATE SET
  window_start=CASE WHEN spawnvault_login_limits.window_start<now()-interval '15 minutes' THEN now() ELSE spawnvault_login_limits.window_start END,
  hits=CASE WHEN spawnvault_login_limits.window_start<now()-interval '15 minutes' THEN 1 ELSE spawnvault_login_limits.hits+1 END
 RETURNING hits INTO count_hits;
 DELETE FROM public.spawnvault_login_limits WHERE window_start<now()-interval '1 day';
 RETURN count_hits<=max_hits;
END;
$$;
REVOKE ALL ON FUNCTION public.spawnvault_take_login_limit(text,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.spawnvault_take_login_limit(text,integer) TO service_role;

-- Inscrição pública não cria contas. Só aceita dados privados enviados pela função administrativa.
-- Não verifica passwords nem escreve diretamente credenciais: essa tarefa pertence ao Supabase Auth.
CREATE OR REPLACE FUNCTION public.spawnvault_provision_account()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE creator uuid; requested_role text; chosen_username text;
BEGIN
 PERFORM pg_catalog.pg_advisory_xact_lock(236023,1);
 BEGIN creator=(NEW.raw_app_meta_data->>'spawnvault_created_by')::uuid;
 EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'As contas são criadas apenas pela administração do SpawnVault'; END;
 IF creator IS NULL OR NOT EXISTS(SELECT 1 FROM public.user_roles r WHERE r.user_id=creator AND r.role='admin')
 OR EXISTS(SELECT 1 FROM public.spawnvault_user_access a WHERE a.user_id=creator AND a.blocked)
 THEN RAISE EXCEPTION 'As contas são criadas apenas pela administração do SpawnVault'; END IF;
 chosen_username=NEW.raw_app_meta_data->>'spawnvault_username';requested_role=NEW.raw_app_meta_data->>'spawnvault_role';
 IF chosen_username IS NULL OR chosen_username !~ '^[A-Za-z0-9_$][A-Za-z0-9._$-]{2,39}$'
 OR requested_role IS NULL OR requested_role NOT IN ('user','moderator','admin') THEN RAISE EXCEPTION 'Dados da conta inválidos'; END IF;
 INSERT INTO public.spawnvault_accounts(user_id,username) VALUES(NEW.id,chosen_username);
 INSERT INTO public.user_roles(user_id,role) VALUES(NEW.id,requested_role);
 INSERT INTO public.item_audit(actor_id,actor_email,action,item_name)
 VALUES(creator,(SELECT email FROM auth.users WHERE id=creator),'users:CREATE',chosen_username);
 RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.spawnvault_provision_account() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS spawnvault_provision_account ON auth.users;
CREATE TRIGGER spawnvault_provision_account AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.spawnvault_provision_account();

-- Os pedidos passam a usar o username de acesso, protegido contra alterações pelo utilizador.
CREATE OR REPLACE FUNCTION public.spawnvault_list_requests()
RETURNS SETOF jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF auth.uid() IS NULL OR public.spawnvault_is_blocked() THEN RAISE EXCEPTION 'Acesso não autorizado' USING ERRCODE='42501'; END IF;
 RETURN QUERY SELECT to_jsonb(r)||jsonb_build_object(
  'requester_username',coalesce(u.username,r.requested_by::text),
  'reviewer_username',v.username,
  'is_archived',EXISTS(SELECT 1 FROM public.item_request_archives a WHERE a.request_id=r.id AND a.user_id=auth.uid()))
 FROM public.item_requests r LEFT JOIN public.spawnvault_accounts u ON u.user_id=r.requested_by
 LEFT JOIN public.spawnvault_accounts v ON v.user_id=r.reviewed_by
 WHERE r.requested_by=auth.uid() OR public.is_spawnvault_staff() ORDER BY r.created_at DESC,r.id;
END;
$$;
NOTIFY pgrst,'reload schema';
COMMIT;


-- FICHEIRO: migration_gestock_v1.sql
-- Additive migration. Apply AFTER the inherited SpawnVault migrations in a NEW GESTOCK project.
-- No owner is inferred from email or first signup. Provision the one owner via SQL, see GESTOCK.md.
begin;
create table public.gestock_owner (
 singleton boolean primary key default true check(singleton),
 user_id uuid not null unique references auth.users(id) on delete restrict
);
create table public.gestock_roles (
 user_id uuid primary key references auth.users(id) on delete cascade,
 role text not null check(role in ('admin','moderator','user'))
);
create table public.gestock_permissions (
 role text not null check(role in ('admin','moderator','user')),
 action text not null check(action in ('read','receive','consume','replenish','products','targets','reports')),
 primary key(role,action)
);
insert into public.gestock_permissions values
 ('admin','read'),('admin','receive'),('admin','consume'),('admin','replenish'),('admin','products'),('admin','targets'),('admin','reports'),
 ('moderator','read'),('moderator','receive'),('moderator','consume'),('moderator','replenish'),('moderator','reports'),('user','read'),('user','consume');
create table public.gestock_products (
 id uuid primary key default gen_random_uuid(),
 name text not null check(length(trim(name)) between 1 and 120),
 brand text not null check(length(trim(brand)) between 1 and 120),
 target integer not null default 0 check(target>=0), unique(name,brand)
);
create table public.gestock_batches (
 id uuid primary key default gen_random_uuid(),
 product_id uuid not null references public.gestock_products(id),
 lot text not null check(length(trim(lot)) between 1 and 120),
 expiry date not null,
 central integer not null default 0 check(central>=0),
 medical integer not null default 0 check(medical>=0),
 unique(product_id,lot,expiry)
);
create table public.gestock_movements (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.gestock_batches(id),
 kind text not null check(kind in ('receive','consume','replenish')),
 quantity integer not null check(quantity>0),
 actor uuid not null references auth.users(id),
 created_at timestamptz not null default now()
);
create function public.gestock_can(p_action text) returns boolean
language sql stable security definer set search_path=public as $$
 select auth.uid() is not null and not public.spawnvault_is_blocked() and
 (exists(select 1 from gestock_owner where user_id=auth.uid()) or
 exists(select 1 from gestock_permissions where role=coalesce((select role from gestock_roles where user_id=auth.uid()),'user') and action=p_action
 -- Central warehouse access never granted to ordinary users, even via the matrix.
 and not (role='user' and p_action in ('receive','replenish'))));
$$;
create function public.gestock_developer() returns boolean
language sql stable security definer set search_path=public as $$
 select auth.uid() is not null and not public.spawnvault_is_blocked() and exists(select 1 from gestock_owner where user_id=auth.uid());
$$;
create function public.gestock_product(p_name text,p_brand text) returns uuid
language plpgsql security definer set search_path=public as $$
declare result uuid;
begin
 if not gestock_can('products') then raise exception 'Sem permissão'; end if;
 insert into gestock_products(name,brand) values(trim(p_name),trim(p_brand)) returning id into result;
 return result;
end $$;
create function public.gestock_target(p_product uuid,p_target integer) returns void
language plpgsql security definer set search_path=public as $$
begin
 if not gestock_can('targets') then raise exception 'Sem permissão'; end if;
 update gestock_products set target=p_target where id=p_product;
 if not found then raise exception 'Produto inexistente'; end if;
end $$;
create function public.gestock_move(p_kind text,p_quantity integer,p_batch uuid default null,p_product uuid default null,p_lot text default null,p_expiry date default null) returns uuid
language plpgsql security definer set search_path=public as $$
declare b gestock_batches; result uuid;
begin
 if p_kind is null or p_kind not in ('receive','consume','replenish') or not gestock_can(p_kind) then raise exception 'Sem permissão'; end if;
 if p_quantity is null or p_quantity<=0 then raise exception 'Quantidade inválida'; end if;
 if p_kind='receive' then
  if p_expiry is null or p_expiry<current_date then raise exception 'Validade inválida'; end if;
  insert into gestock_batches(product_id,lot,expiry) values(p_product,trim(p_lot),p_expiry)
  on conflict(product_id,lot,expiry) do nothing;
  select * into b from gestock_batches where product_id=p_product and lot=trim(p_lot) and expiry=p_expiry for update;
 else
  select * into b from gestock_batches where id=p_batch for update;
 end if;
 if b.id is null then raise exception 'Lote inexistente'; end if;
 if b.expiry<current_date then raise exception 'Lote expirado'; end if;
 if p_kind='consume' and b.medical<p_quantity or p_kind='replenish' and b.central<p_quantity then raise exception 'Stock insuficiente'; end if;
 update gestock_batches set
 central=central+case p_kind when 'receive' then p_quantity when 'replenish' then -p_quantity else 0 end,
 medical=medical+case p_kind when 'consume' then -p_quantity when 'replenish' then p_quantity else 0 end where id=b.id;
 insert into gestock_movements(batch_id,kind,quantity,actor) values(b.id,p_kind,p_quantity,auth.uid()) returning id into result;
 return result;
end $$;
create function public.gestock_set_role(p_user uuid,p_role text) returns void
language plpgsql security definer set search_path=public as $$
begin
 if not gestock_developer() then raise exception 'Apenas Developer'; end if;
 if exists(select 1 from gestock_owner where user_id=p_user) then raise exception 'Developer protegido'; end if;
 insert into gestock_roles values(p_user,p_role) on conflict(user_id) do update set role=excluded.role;
end $$;
create function public.gestock_set_permission(p_role text,p_action text,p_enabled boolean) returns void
language plpgsql security definer set search_path=public as $$
begin
 if not gestock_developer() then raise exception 'Apenas Developer'; end if;
 if p_enabled is null then raise exception 'Estado inválido'; end if;
 if p_enabled then insert into gestock_permissions values(p_role,p_action) on conflict do nothing;
 else delete from gestock_permissions where role=p_role and action=p_action; end if;
end $$;
create function public.gestock_snapshot() returns jsonb
language plpgsql stable security definer set search_path=public as $$
begin
 if not gestock_can('read') then raise exception 'Sem permissão de consulta'; end if;
 return jsonb_build_object(
 'role',case when gestock_developer() then 'developer' else coalesce((select role from gestock_roles where user_id=auth.uid()),'user') end,
 'permissions',(select coalesce(jsonb_agg(action),'[]') from unnest(array['read','receive','consume','replenish','products','targets','reports']) action where gestock_can(action)),
 'products',(select coalesce(jsonb_agg(p),'[]') from gestock_products p),
 'batches',(select coalesce(jsonb_agg(b),'[]') from gestock_batches b),
 'movements',case when gestock_can('reports') then (select coalesce(jsonb_agg(m order by created_at desc),'[]') from gestock_movements m) else '[]'::jsonb end,
 'matrix',case when gestock_developer() then (select coalesce(jsonb_agg(p),'[]') from gestock_permissions p) else '[]'::jsonb end);
end $$;
-- No direct client writes. All stock mutations are checked, locked and logged by RPC.
do $$ declare t text; begin
 foreach t in array array['gestock_owner','gestock_roles','gestock_permissions','gestock_products','gestock_batches','gestock_movements'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon, authenticated',t);
 end loop;
end $$;
-- Revoke PostgreSQL's default PUBLIC execute privilege, including helper functions.
do $$ declare f record; begin
 for f in select oid::regprocedure signature from pg_proc where pronamespace='public'::regnamespace and proname like 'gestock_%' loop
 execute format('revoke all on function %s from public, anon',f.signature);
 execute format('grant execute on function %s to authenticated',f.signature);
 end loop;
end $$;
commit;
