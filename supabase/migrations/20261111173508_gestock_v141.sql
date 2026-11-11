-- Gestock 1.4.1: suppliers, ordered replenishment and login alerts.
begin;

create table public.gestock_suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 120),
  contact text not null default '' check (length(contact) <= 120),
  phone text not null default '' check (length(phone) <= 40),
  email text not null default '' check (length(email) <= 254)
);
create unique index gestock_suppliers_name on public.gestock_suppliers (lower(trim(name)));
alter table public.gestock_suppliers enable row level security;
revoke all on public.gestock_suppliers from public, anon, authenticated;

alter table public.gestock_products
  add column supplier_id uuid references public.gestock_suppliers(id) on delete set null,
  add column central_minimum integer check (central_minimum >= 0),
  add column restock_order integer not null default 100 check (restock_order between 1 and 9999);
create index gestock_products_supplier on public.gestock_products(supplier_id) where supplier_id is not null;

create table public.gestock_restock_runs (
  id uuid primary key,
  actor uuid not null references auth.users(id),
  lines jsonb not null,
  created_at timestamptz not null default now()
);
create index gestock_restock_runs_actor on public.gestock_restock_runs(actor);
alter table public.gestock_restock_runs enable row level security;
revoke all on public.gestock_restock_runs from public, anon, authenticated;

create function public.gestock_supplier(p_id uuid, p_name text default null, p_contact text default null, p_phone text default null, p_email text default null, p_delete boolean default false)
returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
  if public.gestock_role() is null or public.gestock_role() not in ('admin','developer') or not public.gestock_can('stock') then
    raise exception 'Sem permissão para gerir fornecedores' using errcode='42501';
  end if;

  if p_delete then
    delete from public.gestock_suppliers where id=p_id returning id into result;
  else
    if coalesce(length(trim(p_name)),0) not between 1 and 120
      or length(coalesce(p_contact,''))>120 or length(coalesce(p_phone,''))>40
      or length(coalesce(p_email,''))>254
      or (coalesce(trim(p_email),'')<>'' and trim(p_email) !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$') then
      raise exception 'Confirma o nome e os dados de contacto do fornecedor';
    end if;
    if p_id is null then
      insert into public.gestock_suppliers(name,contact,phone,email)
        values(trim(p_name),trim(coalesce(p_contact,'')),trim(coalesce(p_phone,'')),trim(coalesce(p_email,'')))
        returning id into result;
    else
      update public.gestock_suppliers set name=trim(p_name),contact=trim(coalesce(p_contact,'')),
        phone=trim(coalesce(p_phone,'')),email=trim(coalesce(p_email,''))
        where id=p_id returning id into result;
    end if;
  end if;
  if result is null then raise exception 'Fornecedor inexistente';end if;
  return result;
end $$;

create function public.gestock_material_plan(p_product uuid, p_supplier uuid, p_minimum integer, p_target integer, p_order integer)
returns void language plpgsql security definer set search_path='' as $$
begin
  if public.gestock_role() is null or public.gestock_role() not in ('admin','developer') or not public.gestock_can('stock') then
    raise exception 'Sem permissão para configurar materiais' using errcode='42501';
  end if;
  if (p_minimum is not null and p_minimum<0) or p_target is null or p_target not between 0 and 999
    or p_order is null or p_order not between 1 and 9999 then raise exception 'Confirma as quantidades e a ordem de reposição';end if;
  update public.gestock_products set supplier_id=p_supplier,central_minimum=p_minimum,target=p_target,restock_order=p_order
    where id=p_product;
  if not found then raise exception 'Material inexistente';end if;
end $$;

create function public.gestock_planning() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor_role text:=public.gestock_role();
declare manager boolean;
begin
  manager:=coalesce(actor_role in ('admin','developer'),false) and public.gestock_can('stock');
  if not manager and (actor_role is null or actor_role not in ('admin','developer','moderator') or not public.gestock_can('replenish')) then
    raise exception 'Sem permissão para consultar a reposição' using errcode='42501';
  end if;
  return jsonb_build_object(
    'suppliers',case when manager then (select coalesce(jsonb_agg(to_jsonb(s) order by s.name),'[]') from public.gestock_suppliers s) else '[]'::jsonb end,
    'products',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'brand',p.brand,
      'target',p.target,'restock_order',p.restock_order,
      'system_medical',coalesce(t.medical,0)::text,
      'supplier_id',case when manager then p.supplier_id end,
      'central_minimum',case when manager then p.central_minimum end)
      order by p.restock_order,p.name,p.id),'[]')
      from public.gestock_products p
      left join (select product_id,sum(medical) medical from public.gestock_batches where medical>0 group by product_id) t on t.product_id=p.id
      where manager or p.target>0 or coalesce(t.medical,0)>0));
end $$;

create function public.gestock_restock(p_request uuid,p_lines jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare actor_role text:=public.gestock_role();
declare previous public.gestock_restock_runs;
declare line jsonb;
declare material public.gestock_products;
declare quantity integer;
declare counted numeric;
declare recorded numeric;
begin
  if actor_role is null or actor_role not in ('admin','developer','moderator') or not public.gestock_can('replenish') then
    raise exception 'Sem permissão para repor material' using errcode='42501';
  end if;
  if p_request is null or p_lines is null or jsonb_typeof(p_lines)<>'array' then raise exception 'Lista de reposição inválida';end if;
  if jsonb_array_length(p_lines) not between 1 and 500 then raise exception 'Seleciona entre 1 e 500 materiais';end if;

  perform pg_advisory_xact_lock(hashtextextended('gestock-restock:'||p_request::text,0));
  select * into previous from public.gestock_restock_runs where id=p_request;
  if found then
    if previous.actor=auth.uid() and previous.lines=p_lines then return p_request;end if;
    raise exception 'Identificador de reposição já utilizado';
  end if;
  if (select count(distinct (x->>'product')::uuid) from jsonb_array_elements(p_lines) x) <> jsonb_array_length(p_lines) then
    raise exception 'A lista contém um material repetido ou inválido';
  end if;

  -- Lock the same material rows in the same order as the issue and transfer functions.
  perform 1 from public.gestock_products p
    where p.id in (select (x->>'product')::uuid from jsonb_array_elements(p_lines) x)
    order by p.id for update;
  if (select count(*) from public.gestock_products p where p.id in
    (select (x->>'product')::uuid from jsonb_array_elements(p_lines) x)) <> jsonb_array_length(p_lines) then
    raise exception 'Um dos materiais já não existe';
  end if;

  for line in select x from jsonb_array_elements(p_lines) x
    join public.gestock_products p on p.id=(x->>'product')::uuid
    order by p.restock_order,p.name,p.id
  loop
    select * into material from public.gestock_products where id=(line->>'product')::uuid;
    if coalesce(line->>'counted','') !~ '^[0-9]{1,16}$'
      or coalesce(line->>'quantity','') !~ '^[0-9]{1,3}$'
      or coalesce(line->>'target','') !~ '^[0-9]{1,3}$'
      or coalesce(line->>'expected','') !~ '^[0-9]{1,30}$' then
      raise exception 'Contagem ou quantidade inválida para %',material.name;
    end if;
    counted:=(line->>'counted')::numeric;
    quantity:=(line->>'quantity')::integer;
    select coalesce(sum(medical),0) into recorded from public.gestock_batches where product_id=material.id;
    if material.target<>(line->>'target')::integer or recorded<>(line->>'expected')::numeric then
      raise exception 'O stock ou a quantidade exigida de % mudou. Reabre a reposição e confirma a contagem.',material.name;
    end if;
    if quantity<1 or counted+quantity>material.target then
      raise exception 'A quantidade a repor de % ultrapassa a falta indicada',material.name;
    end if;
    perform public.gestock_transfer('replenish',material.id,quantity);
  end loop;

  insert into public.gestock_restock_runs(id,actor,lines) values(p_request,auth.uid(),p_lines);
  return p_request;
end $$;

create function public.gestock_alerts() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor_role text:=public.gestock_role();
declare today date:=(now() at time zone 'Europe/Lisbon')::date;
begin
  if actor_role is null or actor_role not in ('admin','developer','moderator') or not public.gestock_can('read') then
    raise exception 'Sem permissão para consultar alertas' using errcode='42501';
  end if;
  return jsonb_build_object(
    'expiries',(select coalesce(jsonb_agg(to_jsonb(e) order by e.expiry,e.name,e.lot),'[]') from (
      select p.name,p.brand,b.lot,b.expiry,b.central::text,b.medical::text
      from public.gestock_batches b join public.gestock_products p on p.id=b.product_id
      where (b.central>0 or b.medical>0) and b.expiry<=today+30
    ) e),
    'minimums',(select coalesce(jsonb_agg(to_jsonb(m) order by m.name,m.brand),'[]') from (
      select p.name,p.brand,p.central_minimum minimum,coalesce(b.available,0)::text available
      from public.gestock_products p
      left join (select product_id,sum(central) available from public.gestock_batches where expiry>=today and central>0 group by product_id) b on b.product_id=p.id
      where p.central_minimum is not null and coalesce(b.available,0)<=p.central_minimum::numeric*1.10
    ) m));
end $$;

-- Keep supplier and planning metadata scoped to gestock_planning.
create or replace function public.gestock_snapshot() returns jsonb language plpgsql stable security definer set search_path='' as $$ declare r text:=public.gestock_role();begin
 if not public.gestock_ready() then raise exception 'Acesso não autorizado';end if;
 return jsonb_build_object('role',r,'permissions',(public.gestock_access_status()->'permissions'),
 'products',(select coalesce(jsonb_agg((to_jsonb(p)-ARRAY['supplier_id','central_minimum','restock_order'])||case when r='user' then jsonb_build_object('target',null) else '{}'::jsonb end order by p.name),'[]') from public.gestock_products p where public.gestock_can('read') or public.gestock_can('stock')),
 'batches',case when r='user' then '[]'::jsonb else(select coalesce(jsonb_agg(b),'[]') from public.gestock_batches b where public.gestock_can('read') or public.gestock_can('stock')) end,
 'vehicles',(select coalesce(jsonb_agg(v order by name),'[]') from public.gestock_vehicles v where active),
 'movements',case when r in ('developer','admin') and public.gestock_can('reports') then(select coalesce(jsonb_agg(to_jsonb(m)||jsonb_build_object('username',upper(a.username)) order by m.created_at desc),'[]') from public.gestock_movements m left join public.spawnvault_accounts a on a.user_id=m.actor) else '[]'::jsonb end,
 'matrix',case when public.gestock_developer() then(select coalesce(jsonb_agg(p),'[]') from public.gestock_permissions p) else '[]'::jsonb end);end $$;

revoke all on function public.gestock_supplier(uuid,text,text,text,text,boolean),
  public.gestock_material_plan(uuid,uuid,integer,integer,integer),public.gestock_planning(),
  public.gestock_restock(uuid,jsonb),public.gestock_alerts() from public,anon;
grant execute on function public.gestock_supplier(uuid,text,text,text,text,boolean),
  public.gestock_material_plan(uuid,uuid,integer,integer,integer),public.gestock_planning(),
  public.gestock_restock(uuid,jsonb),public.gestock_alerts() to authenticated;
notify pgrst,'reload schema';
commit;
