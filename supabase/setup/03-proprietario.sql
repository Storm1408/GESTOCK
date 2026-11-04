-- Confirmar no Dashboard que a única conta Auth é a do proprietário real.
-- Não cria conta nem password. Executar apenas no projeto novo GESTOCK.
begin;
do $$ declare owner_id uuid; begin
 if (select count(*) from auth.users)<>1 then raise exception 'Esperada apenas a conta real do proprietário'; end if;
 select id into owner_id from auth.users;
 if exists(select 1 from public.gestock_owner) then raise exception 'Proprietário já configurado'; end if;
 insert into public.gestock_owner(user_id) values(owner_id);
 insert into public.user_roles(user_id,role) values(owner_id,'admin') on conflict(user_id) do update set role='admin';
end $$;
commit;
-- Confirmar o username criado pela migração, sem expor credenciais:
select a.user_id,a.username from public.spawnvault_accounts a join public.gestock_owner o on o.user_id=a.user_id;