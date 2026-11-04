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