-- Gestock 1.1: single-vehicle issues, protected roles, images and reports.
begin;
create or replace function public.gestock_role() returns text language sql stable security definer set search_path='' as $$
 select case when auth.uid() is null or public.spawnvault_is_blocked() then null
 when public.gestock_developer() then 'developer'
 else coalesce((select role from public.user_roles where user_id=auth.uid()),'user') end;
$$;
create or replace function public.gestock_manager() returns boolean language sql stable security definer set search_path='' as $$ select coalesce(public.gestock_role() in ('developer','admin'),false); $$;
create or replace function public.gestock_access_status() returns jsonb language plpgsql stable security definer set search_path='' as $$ begin
 if public.gestock_role() is null then raise exception 'Acesso não autorizado' using errcode='42501'; end if;
 return jsonb_build_object('role',public.gestock_role());end $$;
create or replace function public.gestock_can(p_action text) returns boolean language sql stable security definer set search_path='' as $$
 select public.gestock_role() is not null and (public.gestock_developer() or
 exists(select 1 from public.gestock_permissions where role=public.gestock_role() and action=p_action
 and not (role='user' and p_action in ('receive','replenish','reports','products','targets'))
 and not (p_action='products') and not (p_action='targets' and role<>'admin')));
$$;
create table public.gestock_vehicles(id uuid primary key default gen_random_uuid(),name text not null check(length(trim(name)) between 1 and 80),active boolean not null default true);
create unique index gestock_vehicle_name on public.gestock_vehicles(lower(trim(name))) where active;
create table public.gestock_issues(id uuid primary key default gen_random_uuid(),request_id uuid not null unique,vehicle_id uuid not null references public.gestock_vehicles(id),vehicle_name text not null,actor uuid not null references auth.users(id),created_at timestamptz not null default now(),lines jsonb not null);
alter table public.gestock_movements add column issue_id uuid references public.gestock_issues(id);
create index gestock_movements_issue on public.gestock_movements(issue_id);
create index gestock_movements_date on public.gestock_movements(created_at);
create index gestock_fefo on public.gestock_batches(product_id,expiry,id);
alter table public.gestock_products add column image_path text;
alter table public.gestock_vehicles enable row level security;
alter table public.gestock_issues enable row level security;
revoke all on public.gestock_vehicles,public.gestock_issues from public,anon,authenticated;
create function public.gestock_vehicle(p_name text,p_id uuid default null,p_delete boolean default false) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;begin
 if not public.gestock_manager() then raise exception 'Apenas administradores';end if;
 if p_delete then update public.gestock_vehicles set active=false where id=p_id and active returning id into result;
 elsif p_id is null then insert into public.gestock_vehicles(name) values(trim(p_name)) returning id into result;
 else update public.gestock_vehicles set name=trim(p_name) where id=p_id and active returning id into result;end if;
 if result is null then raise exception 'Veículo inexistente';end if;return result;end $$;
create or replace function public.gestock_product(p_name text,p_brand text) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;begin if not public.gestock_developer() then raise exception 'Apenas Developer pode adicionar itens';end if;
 insert into public.gestock_products(name,brand) values(trim(p_name),trim(p_brand)) returning id into result;return result;end $$;
create function public.gestock_product_edit(p_product uuid,p_name text,p_brand text,p_image text default null) returns void language plpgsql security definer set search_path='' as $$
declare old_path text;begin if not public.gestock_manager() then raise exception 'Apenas administradores';end if;
 select image_path into old_path from public.gestock_products where id=p_product for update;
 if not found then raise exception 'Produto inexistente';end if;
 if p_image is not null and p_image is distinct from old_path and p_image not like auth.uid()::text||'/%' then raise exception 'Imagem inválida';end if;
 update public.gestock_products set name=trim(p_name),brand=trim(p_brand),image_path=p_image where id=p_product;end $$;
create or replace function public.gestock_target(p_product uuid,p_target integer) returns void language plpgsql security definer set search_path='' as $$ begin
 if not public.gestock_manager() or not public.gestock_can('targets') then raise exception 'Sem permissão';end if;
 if p_target is null or p_target<0 or p_target>999 then raise exception 'Quantidade: máximo 3 dígitos';end if;
 update public.gestock_products set target=p_target where id=p_product;if not found then raise exception 'Produto inexistente';end if;end $$;
-- Preserve the original batch movement implementation under a private name, then guard the legacy API.
alter function public.gestock_move(text,integer,uuid,uuid,text,date) rename to gestock_move_internal;
revoke all on function public.gestock_move_internal(text,integer,uuid,uuid,text,date) from public,anon,authenticated;
create function public.gestock_move(p_kind text,p_quantity integer,p_batch uuid default null,p_product uuid default null,p_lot text default null,p_expiry date default null) returns uuid language plpgsql security definer set search_path='' as $$ begin
 if p_kind='consume' then raise exception 'Seleciona um único veículo e confirma uma nova saída';end if;
 if p_quantity is null or p_quantity not between 1 and 999 then raise exception 'Quantidade entre 1 e 999';end if;
 return public.gestock_move_internal(p_kind,p_quantity,p_batch,p_product,p_lot,p_expiry);end $$;
create function public.gestock_transfer(p_kind text,p_product uuid,p_quantity integer,p_lot text default null,p_expiry date default null) returns void language plpgsql security definer set search_path='' as $$
declare b record;remaining integer:=p_quantity;take integer;begin
 if p_kind is null or p_kind not in ('receive','replenish') or not public.gestock_can(p_kind) then raise exception 'Sem permissão';end if;
 if p_quantity is null or p_quantity not between 1 and 999 then raise exception 'Quantidade entre 1 e 999';end if;
 if p_kind='receive' then perform public.gestock_move('receive',p_quantity,null,p_product,p_lot,p_expiry);return;end if;
 for b in select * from public.gestock_batches where product_id=p_product and expiry>=current_date and central>0 order by expiry,id for update loop
 take=least(remaining,b.central);perform public.gestock_move('replenish',take,b.id);remaining=remaining-take;exit when remaining=0;end loop;
 if remaining<>0 then raise exception 'Stock insuficiente no Armazém de Saúde';end if;end $$;
create function public.gestock_issue(p_vehicle uuid,p_lines jsonb,p_request uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare v public.gestock_vehicles;prev public.gestock_issues;result uuid;line jsonb;prod uuid;q integer;b record;remaining integer;take integer;begin
 if not public.gestock_can('consume') then raise exception 'Sem permissão para saídas';end if;
 if p_request is null then raise exception 'Identificador obrigatório';end if;
 perform pg_catalog.pg_advisory_xact_lock(hashtextextended(p_request::text,110));
 select * into prev from public.gestock_issues where request_id=p_request;
 if found then if prev.actor<>auth.uid() or prev.vehicle_id is distinct from p_vehicle or prev.lines is distinct from p_lines then raise exception 'Pedido de saída já utilizado';end if;return prev.id;end if;
 select * into v from public.gestock_vehicles where id=p_vehicle and active for share;
 if v.id is null then raise exception 'Seleciona um veículo válido';end if;
 if p_lines is null or jsonb_typeof(p_lines)<>'array' then raise exception 'Seleciona os materiais';end if;
 if jsonb_array_length(p_lines) not between 1 and 100 then raise exception 'Seleciona entre 1 e 100 materiais';end if;
 if (select count(distinct x->>'product') from jsonb_array_elements(p_lines) x)<>jsonb_array_length(p_lines) then raise exception 'Material repetido na saída';end if;
 insert into public.gestock_issues(request_id,vehicle_id,vehicle_name,actor,lines) values(p_request,v.id,v.name,auth.uid(),p_lines) returning id into result;
 -- Lock products in a stable order across concurrent baskets to avoid deadlocks.
 for line in select x from jsonb_array_elements(p_lines) x order by x->>'product' loop
 if not coalesce(line->>'quantity','') ~ '^[0-9]{1,3}$' then raise exception 'Quantidade entre 1 e 999';end if;
 q=(line->>'quantity')::integer;if q<1 then raise exception 'Quantidade entre 1 e 999';end if;
 prod=(line->>'product')::uuid;remaining=q;
 perform 1 from public.gestock_products where id=prod for update;if not found then raise exception 'Seleciona um material válido';end if;
 for b in select * from public.gestock_batches where product_id=prod and expiry>=current_date and medical>0 order by expiry,id for update loop
 take=least(remaining,b.medical);
 update public.gestock_batches set medical=medical-take where id=b.id;
 insert into public.gestock_movements(batch_id,kind,quantity,actor,issue_id) values(b.id,'consume',take,auth.uid(),result);
 remaining=remaining-take;exit when remaining=0;end loop;
 if remaining<>0 then raise exception 'Quantidade indisponível para o material selecionado';end if;
 end loop;return result;end $$;
create or replace function public.gestock_snapshot() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r text:=public.gestock_role();begin
 if not public.gestock_can('read') then raise exception 'Sem permissão de consulta';end if;
 return jsonb_build_object('role',r,
 'permissions',(select coalesce(jsonb_agg(action),'[]') from unnest(array['read','receive','consume','replenish','products','targets','reports']) action where public.gestock_can(action)),
 'products',(select coalesce(jsonb_agg(to_jsonb(p)||case when r='user' then jsonb_build_object('target',null) else '{}'::jsonb end order by p.name),'[]') from public.gestock_products p),
 'batches',case when r='user' then '[]'::jsonb else (select coalesce(jsonb_agg(b),'[]') from public.gestock_batches b) end,
 'vehicles',(select coalesce(jsonb_agg(v order by name),'[]') from public.gestock_vehicles v where active),
 'movements',case when public.gestock_can('reports') then (select coalesce(jsonb_agg(m order by created_at desc),'[]') from public.gestock_movements m) else '[]'::jsonb end,
 'matrix',case when public.gestock_developer() then (select coalesce(jsonb_agg(p),'[]') from public.gestock_permissions p) else '[]'::jsonb end);end $$;
create function public.gestock_report(p_kind text,p_start date default null,p_end date default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;begin
 if not public.gestock_can('reports') then raise exception 'Sem permissão para relatórios';end if;
 if p_start>p_end then raise exception 'Período inválido';end if;
 if p_kind in ('medical','inventory') then
 select coalesce(jsonb_agg(jsonb_build_object('name',p.name,'brand',p.brand,'lot',b.lot,'expiry',b.expiry,'quantity',case p_kind when 'medical' then b.medical else b.central end) order by p.name,b.expiry,b.lot),'[]') into rows
 from public.gestock_batches b join public.gestock_products p on p.id=b.product_id;
 elsif p_kind in ('consume','replenish','receive') then
 select coalesce(jsonb_agg(jsonb_build_object('name',p.name,'brand',p.brand,'lot',b.lot,'expiry',b.expiry,'quantity',m.quantity,'date',m.created_at,'actor',coalesce(a.username,m.actor::text),'vehicle',coalesce(i.vehicle_name,'Sem veículo (histórico)'),'reference',coalesce(i.id,m.id)) order by m.created_at desc,p.name),'[]') into rows
 from public.gestock_movements m join public.gestock_batches b on b.id=m.batch_id join public.gestock_products p on p.id=b.product_id
 left join public.gestock_issues i on i.id=m.issue_id left join public.spawnvault_accounts a on a.user_id=m.actor
 where m.kind=p_kind and (p_start is null or m.created_at >= p_start::timestamp at time zone 'Europe/Lisbon') and (p_end is null or m.created_at < (p_end+1)::timestamp at time zone 'Europe/Lisbon');
 else raise exception 'Relatório inválido';end if;
 return jsonb_build_object('kind',p_kind,'rows',rows,'generated_at',now(),'start',p_start,'end',p_end);end $$;
-- Enforce catalogue creation and image administration even against direct API calls.
create policy "Gestock Developer creates catalogue" on public.items as restrictive for insert to authenticated with check(public.gestock_developer());
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('gestock-images','gestock-images',false,3145728,array['image/png','image/jpeg','image/webp']) on conflict(id) do nothing;
create policy "Gestock image read" on storage.objects for select to authenticated using(bucket_id='gestock-images' and public.gestock_role() is not null and (public.gestock_manager() or exists(select 1 from public.gestock_products where image_path=name)));
create policy "Gestock image add" on storage.objects for insert to authenticated with check(bucket_id='gestock-images' and public.gestock_manager() and split_part(name,'/',1)=auth.uid()::text);
create policy "Gestock image remove" on storage.objects for delete to authenticated using(bucket_id='gestock-images' and public.gestock_manager());
create policy "Gestock catalogue image admins" on storage.objects as restrictive for insert to authenticated with check(bucket_id<>'item-images' or public.gestock_manager());
-- Read policy uses a definer lookup because product tables intentionally have no direct grants.
create function public.gestock_image_visible(p_path text) returns boolean language sql stable security definer set search_path='' as $$
 select public.gestock_role() is not null and (public.gestock_manager() or exists(select 1 from public.gestock_products where image_path=p_path));$$;
alter policy "Gestock image read" on storage.objects using(bucket_id='gestock-images' and public.gestock_image_visible(name));
-- Owner protections apply to role and block mutations; owner assignment remains server-only.
create function public.gestock_protect_owner_v110() returns trigger language plpgsql security definer set search_path='' as $$ begin
 if exists(select 1 from public.gestock_owner where user_id=coalesce(old.user_id,new.user_id)) then
 if TG_OP='DELETE' then raise exception 'Developer protegido';end if;
 if new.user_id<>old.user_id then raise exception 'Developer protegido';end if;
 if TG_TABLE_NAME='user_roles' then if new.role<>'admin' then raise exception 'Developer protegido';end if;end if;
 if TG_TABLE_NAME='spawnvault_user_access' then if new.blocked then raise exception 'Developer protegido';end if;end if;
 end if;return new;end $$;
create trigger gestock_protect_owner_role_v110 before update or delete on public.user_roles for each row execute function public.gestock_protect_owner_v110();
create trigger gestock_protect_owner_block_v110 before insert or update or delete on public.spawnvault_user_access for each row execute function public.gestock_protect_owner_v110();
do $$ declare f record;begin for f in select oid::regprocedure sig from pg_proc where pronamespace='public'::regnamespace and proname like 'gestock_%' loop
 execute format('revoke all on function %s from public,anon',f.sig);
 if f.sig::text not like '%gestock_move_internal(%' and f.sig::text not like '%gestock_protect_owner_v110(%' then execute format('grant execute on function %s to authenticated',f.sig);end if;
 end loop;end $$;

create or replace function public.gestock_set_role(p_user uuid,p_role text) returns void language plpgsql security definer set search_path='' as $$
declare previous text;begin
 perform pg_catalog.pg_advisory_xact_lock(236023,1);
 if not public.gestock_developer() then raise exception 'Apenas Developer';end if;
 if p_role is null or p_role not in ('admin','moderator','user') then raise exception 'Papel inválido';end if;
 if exists(select 1 from public.gestock_owner where user_id=p_user) then raise exception 'Developer protegido';end if;
 if not exists(select 1 from auth.users where id=p_user) then raise exception 'Utilizador inexistente';end if;
 select role into previous from public.user_roles where user_id=p_user;
 insert into public.user_roles(user_id,role) values(p_user,p_role) on conflict(user_id) do update set role=excluded.role;
 insert into public.gestock_roles(user_id,role) values(p_user,p_role) on conflict(user_id) do update set role=excluded.role;
 if previous is distinct from p_role then insert into public.item_audit(actor_id,actor_email,action,item_name) values(auth.uid(),(select email from auth.users where id=auth.uid()),'users:ROLE',p_user::text||': '||coalesce(previous,'user')||' → '||p_role);end if;
end $$;
create function public.gestock_catalogue_create_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if not public.gestock_developer() then raise exception 'Apenas Developer pode adicionar itens';end if;return new;end $$;
create trigger gestock_catalogue_create_guard before insert on public.items for each row execute function public.gestock_catalogue_create_guard();

revoke all on function public.gestock_catalogue_create_guard() from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
