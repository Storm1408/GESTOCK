-- Gestock 1.4: scoped lot removal, active inventories and immutable history.
begin;
alter table public.gestock_permissions drop constraint gestock_permissions_action_check;
alter table public.gestock_permissions add constraint gestock_permissions_action_check check(action in ('read','receive','consume','replenish','products','targets','reports','vehicles','images','stock','users','remove_medical_lot','remove_central_lot'));
insert into public.gestock_permissions(role,action) values('admin','remove_medical_lot'),('moderator','remove_medical_lot'),('admin','remove_central_lot') on conflict do nothing;
create or replace function public.gestock_set_permission(p_role text,p_action text,p_enabled boolean) returns void language plpgsql security definer set search_path='' as $$ begin
 if not public.gestock_developer() then raise exception 'Apenas Developer';end if;
 if p_role is null or p_role not in ('admin','moderator','user') or p_action is null or p_action not in ('read','receive','consume','replenish','products','targets','reports','vehicles','images','stock','users','remove_medical_lot','remove_central_lot') or p_enabled is null then raise exception 'Permissão inválida';end if;
 if p_enabled and ((p_action='remove_medical_lot' and p_role='user') or (p_action='remove_central_lot' and p_role<>'admin')) then raise exception 'Este cargo não satisfaz o acesso mínimo para eliminar lotes neste local';end if;
 if p_enabled then insert into public.gestock_permissions(role,action) values(p_role,p_action) on conflict do nothing;
 else delete from public.gestock_permissions where role=p_role and action=p_action;end if;
end $$;
create or replace function public.gestock_access_status() returns jsonb language plpgsql stable security definer set search_path='' as $$ begin
 if auth.uid() is null or public.spawnvault_is_blocked() or not exists(select 1 from public.spawnvault_accounts where user_id=auth.uid()) then raise exception 'Acesso não autorizado' using errcode='42501';end if;
 return jsonb_build_object('role',case when exists(select 1 from public.gestock_owner where user_id=auth.uid()) then 'developer' else coalesce((select role from public.user_roles where user_id=auth.uid()),'user') end,'password_required',exists(select 1 from public.gestock_password_state where user_id=auth.uid() and required),'permissions',(select coalesce(jsonb_agg(a),'[]') from unnest(array['read','receive','consume','replenish','products','targets','reports','vehicles','images','stock','users','remove_medical_lot','remove_central_lot']) a where public.gestock_can(a)));
end $$;
create function public.gestock_remove_lot(p_batch uuid,p_location text,p_expected bigint,p_reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare r text:=public.gestock_role();b public.gestock_batches;before bigint;result uuid;begin
 if r is null or p_location is null or p_location not in ('medical','central') then raise exception 'Acesso não autorizado' using errcode='42501';end if;
 if (p_location='medical' and (r not in ('developer','admin','moderator') or not public.gestock_can('remove_medical_lot'))) or (p_location='central' and (r not in ('developer','admin') or not public.gestock_can('remove_central_lot'))) then raise exception 'Sem permissão para eliminar lotes neste local' using errcode='42501';end if;
 if p_reason is null or length(trim(p_reason)) not between 3 and 300 then raise exception 'Indica o motivo da eliminação (3 a 300 caracteres)';end if;
 if p_expected is null or p_expected<=0 then raise exception 'Quantidade esperada inválida';end if;
 -- Match the lock order used by receipts, issues and corrections.
 perform 1 from public.gestock_products where id=(select product_id from public.gestock_batches where id=p_batch) for update;
 select * into b from public.gestock_batches where id=p_batch for update;if not found then raise exception 'Lote inexistente';end if;
 before=case p_location when 'medical' then b.medical else b.central end;
 if before<>p_expected then raise exception 'O stock mudou entretanto. Fecha e volta a abrir o painel antes de eliminar o lote.';end if;
 update public.gestock_batches set medical=case p_location when 'medical' then 0 else medical end,central=case p_location when 'central' then 0 else central end where id=p_batch;
 -- A zero quantity removes the lot from that location's active inventory. Keep the batch
 -- metadata and references so previous issues, reports and audit records remain intact.
 insert into public.gestock_adjustments(batch_id,location,previous_quantity,quantity,reason,actor) values(p_batch,p_location,before,0,trim(p_reason),auth.uid()) returning id into result;
 insert into public.item_audit(actor_id,actor_email,action,item_name) select auth.uid(),u.email,'stock:REMOVE_LOT',p.name||' · '||case p_location when 'medical' then 'Posto Médico' else 'Armazém de Saúde' end||' · Lote '||b.lot||' · '||before||' → 0 · '||trim(p_reason)||' · '||result::text from public.gestock_products p left join auth.users u on u.id=auth.uid() where p.id=b.product_id;
 return result;end $$;
revoke all on function public.gestock_remove_lot(uuid,text,bigint,text) from public,anon;
grant execute on function public.gestock_remove_lot(uuid,text,bigint,text) to authenticated;
create or replace function public.gestock_report(p_kind text,p_start date default null,p_end date default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;begin
 result=public.gestock_report_v110(p_kind,p_start,p_end);
 if p_kind in ('medical','inventory') then result=jsonb_set(result,'{rows}',(select coalesce(jsonb_agg(x),'[]'::jsonb) from jsonb_array_elements(result->'rows') x where (x->>'quantity')::numeric>0));end if;
 return result||jsonb_build_object('issuer',(select upper(username) from public.spawnvault_accounts where user_id=auth.uid()));
end $$;
notify pgrst,'reload schema';
commit;
