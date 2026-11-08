-- Gestock 1.2: account provisioning, first password change, editable permissions and audit.
begin;
create table public.gestock_password_state(user_id uuid primary key references auth.users(id) on delete cascade,required boolean not null default true);
create table public.gestock_account_reservations(id uuid primary key,creator uuid not null references auth.users(id),username text not null,role text not null check(role in ('admin','moderator','user')),expires_at timestamptz not null default now()+interval '5 minutes');
create unique index gestock_reserved_username on public.gestock_account_reservations(lower(username));
alter table public.gestock_password_state enable row level security;
alter table public.gestock_account_reservations enable row level security;
revoke all on public.gestock_password_state,public.gestock_account_reservations from public,anon,authenticated;
create function public.gestock_ready() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and not public.spawnvault_is_blocked() and exists(select 1 from public.spawnvault_accounts where user_id=auth.uid()) and not exists(select 1 from public.gestock_password_state where user_id=auth.uid() and required);
$$;
create or replace function public.gestock_developer() returns boolean language sql stable security definer set search_path='' as $$ select public.gestock_ready() and exists(select 1 from public.gestock_owner where user_id=auth.uid()); $$;
create or replace function public.gestock_role() returns text language sql stable security definer set search_path='' as $$ select case when not public.gestock_ready() then null when public.gestock_developer() then 'developer' else coalesce((select role from public.user_roles where user_id=auth.uid()),'user') end; $$;
alter table public.gestock_permissions drop constraint gestock_permissions_action_check;
alter table public.gestock_permissions add constraint gestock_permissions_action_check check(action in ('read','receive','consume','replenish','products','targets','reports','vehicles','images','stock','users'));
-- Old products grants were inert in 1.1: preserve the effective defaults while making them editable.
delete from public.gestock_permissions where action='products';
insert into public.gestock_permissions(role,action) values('admin','vehicles'),('admin','images'),('admin','stock'),('admin','users') on conflict do nothing;
create or replace function public.gestock_can(p_action text) returns boolean language sql stable security definer set search_path='' as $$ select public.gestock_ready() and (public.gestock_developer() or exists(select 1 from public.gestock_permissions where role=public.gestock_role() and action=p_action)); $$;
create or replace function public.gestock_access_status() returns jsonb language plpgsql stable security definer set search_path='' as $$ begin
 if auth.uid() is null or public.spawnvault_is_blocked() or not exists(select 1 from public.spawnvault_accounts where user_id=auth.uid()) then raise exception 'Acesso não autorizado' using errcode='42501';end if;
 return jsonb_build_object('role',case when exists(select 1 from public.gestock_owner where user_id=auth.uid()) then 'developer' else coalesce((select role from public.user_roles where user_id=auth.uid()),'user') end,'password_required',exists(select 1 from public.gestock_password_state where user_id=auth.uid() and required),'permissions',(select coalesce(jsonb_agg(a),'[]') from unnest(array['read','receive','consume','replenish','products','targets','reports','vehicles','images','stock','users']) a where public.gestock_can(a)));
end $$;
create function public.gestock_reserve_account(p_id uuid,p_creator uuid,p_username text,p_role text) returns void language plpgsql security definer set search_path='' as $$ begin
 perform pg_catalog.pg_advisory_xact_lock(236023,1);
 if p_id is null or p_creator is null or p_username is null or p_username !~ '^[A-Za-z0-9_$][A-Za-z0-9._$-]{2,39}$' or p_role is null or p_role not in ('user','moderator','admin') then raise exception 'Dados inválidos';end if;
 if exists(select 1 from public.spawnvault_user_access where user_id=p_creator and blocked) or exists(select 1 from public.gestock_password_state where user_id=p_creator and required) or not exists(select 1 from public.spawnvault_accounts where user_id=p_creator) then raise exception 'Criador indisponível';end if;
 if not exists(select 1 from public.gestock_owner where user_id=p_creator) and not exists(select 1 from public.user_roles r join public.gestock_permissions p on p.role=r.role where r.user_id=p_creator and p.action='users') then raise exception 'Sem permissão para criar contas';end if;
 if p_role<>'user' and not exists(select 1 from public.gestock_owner where user_id=p_creator) then raise exception 'Apenas Developer pode atribuir cargos';end if;
 delete from public.gestock_account_reservations where expires_at<now();
 if exists(select 1 from public.spawnvault_accounts where lower(username)=lower(p_username)) then raise exception 'Username já existente';end if;
 insert into public.gestock_account_reservations(id,creator,username,role) values(p_id,p_creator,upper(p_username),p_role);
end $$;
create function public.gestock_cancel_reservation(p_id uuid) returns void language sql security definer set search_path='' as $$ delete from public.gestock_account_reservations where id=p_id; $$;
create function public.gestock_finish_password(p_user uuid) returns void language plpgsql security definer set search_path='' as $$ begin
 update public.gestock_password_state set required=false where user_id=p_user and required;
 if found then insert into public.item_audit(actor_id,actor_email,action,item_name) values(p_user,(select email from auth.users where id=p_user),'users:PASSWORD_CHANGED','Alteração inicial da palavra-passe');end if;
end $$;
-- GoTrue applies app_metadata after INSERT. Use a short-lived server-only reservation instead.
create function public.gestock_prepare_account() returns trigger language plpgsql security definer set search_path='' as $$ declare r public.gestock_account_reservations;begin
 select * into r from public.gestock_account_reservations where id=new.id and expires_at>now() for update;
 if r.id is null then raise exception 'As contas são criadas apenas pela administração Gestock';end if;
 new.raw_app_meta_data=coalesce(new.raw_app_meta_data,'{}'::jsonb)||jsonb_build_object('spawnvault_created_by',r.creator,'spawnvault_username',r.username,'spawnvault_role',r.role);
 return new;end $$;
create trigger gestock_prepare_account before insert on auth.users for each row execute function public.gestock_prepare_account();
create or replace function public.spawnvault_provision_account() returns trigger language plpgsql security definer set search_path='' as $$ declare r public.gestock_account_reservations;begin
 select * into r from public.gestock_account_reservations where id=new.id and expires_at>now() for update;
 if r.id is null then raise exception 'Reserva de conta inexistente';end if;
 -- Recheck permissions at INSERT, even if revoked after reserving.
 if exists(select 1 from public.spawnvault_user_access where user_id=r.creator and blocked) or exists(select 1 from public.gestock_password_state where user_id=r.creator and required) then raise exception 'Criador indisponível';end if;
 if not exists(select 1 from public.gestock_owner where user_id=r.creator) and not exists(select 1 from public.user_roles u join public.gestock_permissions p on p.role=u.role where u.user_id=r.creator and p.action='users') then raise exception 'Sem permissão';end if;
 if r.role<>'user' and not exists(select 1 from public.gestock_owner where user_id=r.creator) then raise exception 'Apenas Developer';end if;
 insert into public.spawnvault_accounts(user_id,username) values(new.id,r.username);
 insert into public.user_roles(user_id,role) values(new.id,r.role);
 insert into public.gestock_password_state(user_id,required) values(new.id,true);
 insert into public.item_audit(actor_id,actor_email,action,item_name) values(r.creator,(select email from auth.users where id=r.creator),'users:CREATE',r.username);
 delete from public.gestock_account_reservations where id=new.id;return new;end $$;
-- Protect every inherited table API while the initial password change is pending.
do $$ declare t record;begin for t in select distinct c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relrowsecurity and exists(select 1 from pg_policy p where p.polrelid=c.oid) loop
 execute format('create policy gestock_password_gate on public.%I as restrictive for all to authenticated using(public.gestock_ready()) with check(public.gestock_ready())',t.relname);end loop;end $$;
create or replace function public.is_spawnvault_admin() returns boolean language sql stable security definer set search_path='' as $$ select public.gestock_ready() and exists(select 1 from public.user_roles where user_id=auth.uid() and role='admin'); $$;
-- Existing API helpers now follow the Developer-managed permissions.
create or replace function public.gestock_product(p_name text,p_brand text) returns uuid language plpgsql security definer set search_path='' as $$ declare r uuid;begin if not public.gestock_can('products') then raise exception 'Sem permissão';end if;insert into public.gestock_products(name,brand) values(trim(p_name),trim(p_brand)) returning id into r;return r;end $$;
create or replace function public.gestock_target(p_product uuid,p_target integer) returns void language plpgsql security definer set search_path='' as $$ begin if not public.gestock_can('targets') then raise exception 'Sem permissão';end if;if p_target is null or p_target not between 0 and 999 then raise exception 'Quantidade entre 0 e 999';end if;update public.gestock_products set target=p_target where id=p_product;if not found then raise exception 'Produto inexistente';end if;end $$;
create or replace function public.gestock_vehicle(p_name text,p_id uuid default null,p_delete boolean default false) returns uuid language plpgsql security definer set search_path='' as $$ declare r uuid;begin
 if not public.gestock_can('vehicles') then raise exception 'Sem permissão para gerir veículos';end if;
 if p_delete then update public.gestock_vehicles set active=false where id=p_id and active returning id into r;
 elsif p_id is null then insert into public.gestock_vehicles(name) values(trim(p_name)) returning id into r;
 else update public.gestock_vehicles set name=trim(p_name) where id=p_id and active returning id into r;end if;
 if r is null then raise exception 'Veículo inexistente';end if;return r;end $$;
create or replace function public.gestock_product_edit(p_product uuid,p_name text,p_brand text,p_image text default null) returns void language plpgsql security definer set search_path='' as $$ declare old_path text;begin
 if not public.gestock_can('images') then raise exception 'Sem permissão';end if;
 select image_path into old_path from public.gestock_products where id=p_product for update;if not found then raise exception 'Produto inexistente';end if;
 if p_image is not null and p_image is distinct from old_path and p_image not like auth.uid()::text||'/%' then raise exception 'Imagem inválida';end if;
 if p_image is not null and not exists(select 1 from storage.objects where bucket_id='gestock-images' and name=p_image) then raise exception 'Carrega a imagem antes de guardar';end if;
 update public.gestock_products set name=trim(p_name),brand=trim(p_brand),image_path=p_image where id=p_product;end $$;
alter policy "Gestock image add" on storage.objects with check(bucket_id='gestock-images' and public.gestock_can('images') and split_part(name,'/',1)=auth.uid()::text);
alter policy "Gestock image remove" on storage.objects using(bucket_id='gestock-images' and public.gestock_can('images'));
-- Larger entries; outgoing quantities remain 1..999. Bigints prevent overflow of accumulated stock.
alter table public.gestock_batches alter column central type bigint,alter column medical type bigint;
alter table public.gestock_movements alter column quantity type bigint;
drop function public.gestock_transfer(text,uuid,integer,text,date);
create function public.gestock_transfer(p_kind text,p_product uuid,p_quantity bigint,p_lot text default null,p_expiry date default null) returns void language plpgsql security definer set search_path='' as $$ declare b record;remaining bigint:=p_quantity;take integer;bid uuid;begin
 if p_kind is null or p_kind not in ('receive','replenish') or not public.gestock_can(p_kind) then raise exception 'Sem permissão';end if;
 if p_quantity is null or p_quantity<1 or p_quantity>9007199254740991 then raise exception 'Quantidade inteira positiva inválida';end if;
 perform 1 from public.gestock_products where id=p_product for update;if not found then raise exception 'Produto inexistente';end if;
 if p_kind='receive' then
 if p_expiry is null or p_expiry<current_date then raise exception 'Validade inválida';end if;
 insert into public.gestock_batches(product_id,lot,expiry) values(p_product,trim(p_lot),p_expiry) on conflict(product_id,lot,expiry) do nothing;
 select id into bid from public.gestock_batches where product_id=p_product and lot=trim(p_lot) and expiry=p_expiry for update;
 update public.gestock_batches set central=central+p_quantity where id=bid and central+p_quantity<=9007199254740991;if not found then raise exception 'Quantidade acumulada excede a precisão suportada';end if;
 insert into public.gestock_movements(batch_id,kind,quantity,actor) values(bid,'receive',p_quantity,auth.uid());return;end if;
 if p_quantity>999 then raise exception 'Reposição: quantidade entre 1 e 999';end if;
 for b in select * from public.gestock_batches where product_id=p_product and expiry>=current_date and central>0 order by expiry,id for update loop
 take=least(remaining,b.central);update public.gestock_batches set central=central-take,medical=medical+take where id=b.id;
 insert into public.gestock_movements(batch_id,kind,quantity,actor) values(b.id,'replenish',take,auth.uid());remaining=remaining-take;exit when remaining=0;end loop;
 if remaining<>0 then raise exception 'Stock insuficiente no Armazém de Saúde';end if;end $$;
create function public.gestock_audit_movement() returns trigger language plpgsql security definer set search_path='' as $$ begin
 insert into public.item_audit(actor_id,actor_email,action,item_name) select new.actor,u.email,'stock:'||upper(new.kind),p.name||' · '||new.quantity||' · Lote '||b.lot||' · '||coalesce(new.issue_id,new.id)::text from public.gestock_batches b join public.gestock_products p on p.id=b.product_id left join auth.users u on u.id=new.actor where b.id=new.batch_id;
 return new;end $$;
create trigger gestock_audit_movement after insert on public.gestock_movements for each row execute function public.gestock_audit_movement();
-- Include movements recorded before the audit trigger was introduced.
insert into public.item_audit(actor_id,actor_email,action,item_name,created_at)
select m.actor,u.email,'stock:'||upper(m.kind),p.name||' · '||m.quantity||' · Lote '||b.lot||' · '||coalesce(m.issue_id,m.id)::text,m.created_at
from public.gestock_movements m join public.gestock_batches b on b.id=m.batch_id join public.gestock_products p on p.id=b.product_id left join auth.users u on u.id=m.actor
where not exists(select 1 from public.item_audit a where a.action='stock:'||upper(m.kind) and a.item_name=p.name||' · '||m.quantity||' · Lote '||b.lot||' · '||coalesce(m.issue_id,m.id)::text);
create function public.gestock_logs() returns jsonb language plpgsql stable security definer set search_path='' as $$ declare r jsonb;begin if not public.gestock_can('users') then raise exception 'Sem permissão';end if;
 select coalesce(jsonb_agg(t),'[]') into r from (select l.created_at,l.action,l.item_name,upper(coalesce(a.username,l.actor_email,'Sistema')) actor_email from public.item_audit l left join public.spawnvault_accounts a on a.user_id=l.actor_id order by l.created_at desc limit 200) t;return r;end $$;
alter function public.gestock_report(text,date,date) rename to gestock_report_v110;
revoke all on function public.gestock_report_v110(text,date,date) from public,anon,authenticated;
create function public.gestock_report(p_kind text,p_start date default null,p_end date default null) returns jsonb language sql stable security definer set search_path='' as $$ select public.gestock_report_v110(p_kind,p_start,p_end)||jsonb_build_object('issuer',(select upper(username) from public.spawnvault_accounts where user_id=auth.uid())); $$;
create or replace function public.gestock_snapshot() returns jsonb language plpgsql stable security definer set search_path='' as $$ declare r text:=public.gestock_role();begin
 if not public.gestock_ready() then raise exception 'Acesso não autorizado';end if;
 return jsonb_build_object('role',r,'permissions',(public.gestock_access_status()->'permissions'),
 'products',(select coalesce(jsonb_agg(to_jsonb(p)||case when r='user' then jsonb_build_object('target',null) else '{}'::jsonb end order by p.name),'[]') from public.gestock_products p where public.gestock_can('read') or public.gestock_can('stock')),
 'batches',case when r='user' then '[]'::jsonb else(select coalesce(jsonb_agg(b),'[]') from public.gestock_batches b where public.gestock_can('read') or public.gestock_can('stock')) end,
 'vehicles',(select coalesce(jsonb_agg(v order by name),'[]') from public.gestock_vehicles v where active),
 'movements',case when public.gestock_can('reports') then(select coalesce(jsonb_agg(to_jsonb(m)||jsonb_build_object('username',upper(a.username)) order by m.created_at desc),'[]') from public.gestock_movements m left join public.spawnvault_accounts a on a.user_id=m.actor) else '[]'::jsonb end,
 'matrix',case when public.gestock_developer() then(select coalesce(jsonb_agg(p),'[]') from public.gestock_permissions p) else '[]'::jsonb end);end $$;
-- Grant only public client APIs; reservation/password completion remain service-only.
do $$ declare n text;begin foreach n in array array['gestock_ready','gestock_reserve_account','gestock_cancel_reservation','gestock_finish_password','gestock_prepare_account','gestock_audit_movement','gestock_logs','gestock_transfer','gestock_report'] loop
 declare f record;begin for f in select oid::regprocedure sig from pg_proc where pronamespace='public'::regnamespace and proname=n loop execute format('revoke all on function %s from public,anon,authenticated',f.sig);if n in ('gestock_reserve_account','gestock_cancel_reservation','gestock_finish_password') then execute format('grant execute on function %s to service_role',f.sig);elsif n in ('gestock_ready','gestock_logs','gestock_transfer','gestock_report') then execute format('grant execute on function %s to authenticated',f.sig);end if;end loop;end;
 end loop;end $$;

create or replace function public.spawnvault_list_accounts() returns table(user_id uuid,email text,role text,username text) language plpgsql stable security definer set search_path='' as $$ begin
 if not public.gestock_can('users') then raise exception 'Sem permissão';end if;
 return query select u.id,u.email::text,case when o.user_id is not null then 'developer' else coalesce(r.role,'user') end,upper(a.username) from auth.users u left join public.user_roles r on r.user_id=u.id left join public.spawnvault_accounts a on a.user_id=u.id left join public.gestock_owner o on o.user_id=u.id order by lower(a.username),u.id;end $$;
create policy gestock_storage_password_gate on storage.objects as restrictive for all to authenticated using(public.gestock_ready()) with check(public.gestock_ready());

create or replace function public.spawnvault_set_username(target_user uuid,new_username text) returns void language plpgsql security definer set search_path='' as $$ declare previous text;begin
 perform pg_catalog.pg_advisory_xact_lock(236023,1);if not public.gestock_can('users') then raise exception 'Sem permissão';end if;
 if new_username is null or new_username !~ '^[A-Za-z0-9_$][A-Za-z0-9._$-]{2,39}$' then raise exception 'Username inválido';end if;
 select username into previous from public.spawnvault_accounts where user_id=target_user for update;if not found then raise exception 'Utilizador inexistente';end if;
 update public.spawnvault_accounts set username=upper(new_username) where user_id=target_user;
 if previous is distinct from upper(new_username) then insert into public.item_audit(actor_id,actor_email,action,item_name) values(auth.uid(),(select email from auth.users where id=auth.uid()),'users:USERNAME',upper(previous)||' → '||upper(new_username));end if;end $$;
notify pgrst,'reload schema';

commit;
