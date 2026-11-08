-- Gestock 1.3: private issue history and per-material quantity feedback.
begin;
create or replace function public.gestock_issue(p_vehicle uuid,p_lines jsonb,p_request uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare v public.gestock_vehicles;prev public.gestock_issues;result uuid;line jsonb;prod uuid;q integer;b record;remaining integer;take integer;invalid jsonb:='[]'::jsonb;begin
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
 -- Validate every line before writing, without disclosing stock balances.
 for line in select x from jsonb_array_elements(p_lines) x order by x->>'product' loop
 if not coalesce(line->>'quantity','') ~ '^[0-9]{1,3}$' then raise exception 'Quantidade entre 1 e 999';end if;
 q=(line->>'quantity')::integer;if q<1 then raise exception 'Quantidade entre 1 e 999';end if;
 prod=(line->>'product')::uuid;
 perform 1 from public.gestock_products where id=prod for update;if not found then raise exception 'Seleciona um material válido';end if;
 if coalesce((select sum(medical) from public.gestock_batches where product_id=prod and expiry>=current_date),0)<q then invalid=invalid||jsonb_build_array(prod);end if;
 end loop;
 if jsonb_array_length(invalid)>0 then raise exception using message='Quantidade indisponível. Verifica os valores assinalados a vermelho.',detail=jsonb_build_object('code','GESTOCK_INSUFFICIENT_STOCK','products',invalid)::text;end if;
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

-- No actor argument: every authenticated account can only read its own 50 latest issues.
create function public.gestock_history() returns jsonb language plpgsql stable security definer set search_path='' as $$ declare result jsonb;begin
 if not public.gestock_ready() then raise exception 'Acesso não autorizado' using errcode='42501';end if;
 with recent as (
 select coalesce(i.id,m.id) id,max(coalesce(i.created_at,m.created_at)) created_at,max(coalesce(i.vehicle_name,'Sem veículo (histórico)')) vehicle
 from public.gestock_movements m left join public.gestock_issues i on i.id=m.issue_id
 where m.actor=auth.uid() and m.kind='consume' group by coalesce(i.id,m.id)
 order by max(coalesce(i.created_at,m.created_at)) desc,coalesce(i.id,m.id) desc limit 50
 ), lines as (
 select r.id,p.id product,p.name,p.brand,sum(m.quantity) quantity
 from recent r join public.gestock_movements m on coalesce(m.issue_id,m.id)=r.id
 join public.gestock_batches b on b.id=m.batch_id join public.gestock_products p on p.id=b.product_id
 where m.actor=auth.uid() and m.kind='consume' group by r.id,p.id,p.name,p.brand
 ) select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'created_at',r.created_at,'vehicle',r.vehicle,'lines',(select jsonb_agg(jsonb_build_object('name',l.name,'brand',l.brand,'quantity',l.quantity) order by l.name,l.product) from lines l where l.id=r.id)) order by r.created_at desc,r.id desc),'[]') into result from recent r;
 return result;end $$;
revoke all on function public.gestock_history() from public,anon;
grant execute on function public.gestock_history() to authenticated;
create index gestock_personal_issues on public.gestock_movements(actor,created_at desc) where kind='consume';


-- Manual stock corrections are independent of receipts/consumption and have immutable audit records.
create table public.gestock_adjustments(
 id uuid primary key default gen_random_uuid(),batch_id uuid not null references public.gestock_batches(id),
 location text not null check(location in ('central','medical')),previous_quantity bigint not null check(previous_quantity>=0),
 quantity bigint not null check(quantity>=0),reason text not null check(length(trim(reason)) between 3 and 300),
 actor uuid not null references auth.users(id),created_at timestamptz not null default now()
);
alter table public.gestock_adjustments enable row level security;
revoke all on public.gestock_adjustments from public,anon,authenticated;
create index gestock_adjustment_batch on public.gestock_adjustments(batch_id);
create index gestock_adjustment_actor on public.gestock_adjustments(actor);
create function public.gestock_adjust(p_batch uuid,p_location text,p_quantity bigint,p_expected bigint,p_reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare b public.gestock_batches;before bigint;result uuid;begin
 if public.gestock_role() is null or public.gestock_role() not in ('developer','admin') or not public.gestock_can('stock') then raise exception 'Apenas administradores podem corrigir quantidades';end if;
 if p_location is null or p_location not in ('central','medical') or p_quantity is null or p_quantity<0 or p_quantity>9007199254740991 or p_expected is null then raise exception 'Quantidade ou localização inválida';end if;
 if p_reason is null or length(trim(p_reason)) not between 3 and 300 then raise exception 'Indica o motivo da correção (3 a 300 caracteres)';end if;
 perform 1 from public.gestock_products where id=(select product_id from public.gestock_batches where id=p_batch) for update;
 select * into b from public.gestock_batches where id=p_batch for update;if not found then raise exception 'Lote inexistente';end if;
 before=case p_location when 'central' then b.central else b.medical end;
 if before<>p_expected then raise exception 'O stock mudou entretanto. Fecha e volta a abrir este painel para confirmar a quantidade atual antes de corrigir.';end if;
 if before=p_quantity then raise exception 'A quantidade indicada já é a atual';end if;
 update public.gestock_batches set central=case p_location when 'central' then p_quantity else central end,medical=case p_location when 'medical' then p_quantity else medical end where id=p_batch;
 insert into public.gestock_adjustments(batch_id,location,previous_quantity,quantity,reason,actor) values(p_batch,p_location,before,p_quantity,trim(p_reason),auth.uid()) returning id into result;
 insert into public.item_audit(actor_id,actor_email,action,item_name) select auth.uid(),u.email,'stock:ADJUST',p.name||' · '||case p_location when 'central' then 'Armazém de Saúde' else 'Posto Médico' end||' · Lote '||b.lot||' · '||before||' → '||p_quantity||' · '||trim(p_reason)||' · '||result::text from public.gestock_products p left join auth.users u on u.id=auth.uid() where p.id=b.product_id;
 return result;end $$;
revoke all on function public.gestock_adjust(uuid,text,bigint,bigint,text) from public,anon;
grant execute on function public.gestock_adjust(uuid,text,bigint,bigint,text) to authenticated;

notify pgrst,'reload schema';
commit;
