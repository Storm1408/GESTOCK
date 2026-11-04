-- GESTOCK: APENAS projeto novo e vazio. Não executar no SpawnVault.
DO $guard$ BEGIN IF to_regclass('public.items') IS NOT NULL THEN RAISE EXCEPTION 'Projeto já inicializado: interromper e rever migrações'; END IF; END $guard$;

-- FICHEIRO: schema.sql
-- Executar no SQL Editor do projeto Supabase.
create extension if not exists pgcrypto;

create table if not exists public.items (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 120),
  spawn_name text not null check (length(trim(spawn_name)) between 1 and 120),
  category text not null default '',
  description text not null default '',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists items_name_idx on public.items (lower(name));
create index if not exists items_spawn_idx on public.items (lower(spawn_name));
create index if not exists items_category_idx on public.items (category);

alter table public.items enable row level security;

-- Utilizadores autenticados podem consultar o catálogo partilhado.
create policy "Authenticated users can read items"
on public.items for select to authenticated using (true);

-- Utilizadores autenticados podem criar itens.
create policy "Authenticated users can add items"
on public.items for insert to authenticated with check (auth.uid() = created_by);

-- Nesta versão, qualquer utilizador autenticado pode editar ou apagar itens.
-- Restringe estas políticas se quiseres separar administradores e editores.
create policy "Authenticated users can update items"
on public.items for update to authenticated using (true) with check (true);

create policy "Authenticated users can delete items"
on public.items for delete to authenticated using (true);

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists items_updated_at on public.items;
create trigger items_updated_at before update on public.items
for each row execute function public.set_updated_at();


-- FICHEIRO: migration_v2.sql
-- SpawnVault v2: executar UMA VEZ no SQL Editor do Supabase (como proprietário).
-- Mantém os itens existentes. Faz uma cópia de segurança antes de executar.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.user_roles (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'user' CHECK (role IN ('admin','user'))
);

CREATE OR REPLACE FUNCTION public.is_spawnvault_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
 SELECT EXISTS(SELECT 1 FROM public.user_roles WHERE user_id = (SELECT auth.uid()) AND role = 'admin');
$$;
REVOKE ALL ON FUNCTION public.is_spawnvault_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_spawnvault_admin() TO authenticated;

CREATE TABLE IF NOT EXISTS public.groups (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 60),
 created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS groups_name_casefold_idx ON public.groups (lower(btrim(name)));
ALTER TABLE public.items ADD COLUMN IF NOT EXISTS group_id uuid;

-- Migrar as categorias existentes para grupos sem perder os itens.
INSERT INTO public.groups(name)
SELECT DISTINCT btrim(coalesce(nullif(category,''),'Sem grupo'))
FROM public.items
ON CONFLICT DO NOTHING;
UPDATE public.items AS i SET group_id=g.id
FROM public.groups AS g
WHERE i.group_id IS NULL
  AND lower(btrim(g.name))=lower(btrim(coalesce(nullif(i.category,''),'Sem grupo')));

-- Evitar grupos em falta se ainda não houver itens.
ALTER TABLE public.items DROP CONSTRAINT IF EXISTS items_group_id_fkey;
ALTER TABLE public.items ADD CONSTRAINT items_group_id_fkey
 FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE RESTRICT;
ALTER TABLE public.items ALTER COLUMN group_id SET NOT NULL;
CREATE INDEX IF NOT EXISTS items_group_id_idx ON public.items(group_id);

-- Os utilizadores não podem atribuir a si próprios o papel de administrador.
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can read items" ON public.items;
DROP POLICY IF EXISTS "Authenticated users can add items" ON public.items;
DROP POLICY IF EXISTS "Authenticated users can update items" ON public.items;
DROP POLICY IF EXISTS "Authenticated users can delete items" ON public.items;
DROP POLICY IF EXISTS "SpawnVault read items" ON public.items;
DROP POLICY IF EXISTS "SpawnVault add items" ON public.items;
DROP POLICY IF EXISTS "SpawnVault update items" ON public.items;
DROP POLICY IF EXISTS "SpawnVault delete items" ON public.items;
CREATE POLICY "SpawnVault read items" ON public.items FOR SELECT TO authenticated USING (true);
CREATE POLICY "SpawnVault add items" ON public.items FOR INSERT TO authenticated
 WITH CHECK (public.is_spawnvault_admin() AND created_by=(SELECT auth.uid()));
CREATE POLICY "SpawnVault update items" ON public.items FOR UPDATE TO authenticated
 USING (public.is_spawnvault_admin()) WITH CHECK (public.is_spawnvault_admin());
CREATE POLICY "SpawnVault delete items" ON public.items FOR DELETE TO authenticated
 USING (public.is_spawnvault_admin());

DROP POLICY IF EXISTS "SpawnVault read groups" ON public.groups;
DROP POLICY IF EXISTS "SpawnVault add groups" ON public.groups;
DROP POLICY IF EXISTS "SpawnVault update groups" ON public.groups;
DROP POLICY IF EXISTS "SpawnVault delete groups" ON public.groups;
CREATE POLICY "SpawnVault read groups" ON public.groups FOR SELECT TO authenticated USING (true);
CREATE POLICY "SpawnVault add groups" ON public.groups FOR INSERT TO authenticated
 WITH CHECK (public.is_spawnvault_admin() AND created_by=(SELECT auth.uid()));
CREATE POLICY "SpawnVault update groups" ON public.groups FOR UPDATE TO authenticated
 USING (public.is_spawnvault_admin()) WITH CHECK (public.is_spawnvault_admin());
CREATE POLICY "SpawnVault delete groups" ON public.groups FOR DELETE TO authenticated
 USING (public.is_spawnvault_admin());

DROP POLICY IF EXISTS "SpawnVault own role" ON public.user_roles;
CREATE POLICY "SpawnVault own role" ON public.user_roles FOR SELECT TO authenticated
 USING (user_id=(SELECT auth.uid()));
REVOKE ALL ON public.user_roles FROM anon, authenticated;
GRANT SELECT ON public.user_roles TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.groups TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.items TO authenticated;
COMMIT;

-- DEPOIS de executar este ficheiro, promover manualmente o administrador:
-- 1. Authentication > Users > copiar o UUID da tua conta.
-- 2. Substituir UUID_DO_ADMINISTRADOR e executar a instrução seguinte SEM os '--':
-- INSERT INTO public.user_roles(user_id,role) VALUES ('UUID_DO_ADMINISTRADOR','admin')
-- ON CONFLICT (user_id) DO UPDATE SET role=EXCLUDED.role;
-- Os restantes utilizadores não precisam de registo: por omissão são 'user'.


-- FICHEIRO: migration_v21.sql
-- SpawnVault 2.1: executar UMA VEZ no SQL Editor, após migration_v2.sql.
-- Faz cópia de segurança antes de executar. Mantém os itens existentes.
BEGIN;
ALTER TABLE public.items ADD COLUMN IF NOT EXISTS image_path text;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('item-images', 'item-images', false, 3145728, ARRAY['image/png','image/jpeg','image/webp','image/gif'])
ON CONFLICT (id) DO UPDATE SET public=false, file_size_limit=3145728,
 allowed_mime_types=ARRAY['image/png','image/jpeg','image/webp','image/gif'];

DROP POLICY IF EXISTS "SpawnVault image read" ON storage.objects;
DROP POLICY IF EXISTS "SpawnVault image add" ON storage.objects;
DROP POLICY IF EXISTS "SpawnVault image delete" ON storage.objects;
CREATE POLICY "SpawnVault image read" ON storage.objects FOR SELECT TO authenticated
 USING (bucket_id='item-images');
CREATE POLICY "SpawnVault image add" ON storage.objects FOR INSERT TO authenticated
 WITH CHECK (bucket_id='item-images' AND public.is_spawnvault_admin());
CREATE POLICY "SpawnVault image delete" ON storage.objects FOR DELETE TO authenticated
 USING (bucket_id='item-images' AND public.is_spawnvault_admin());

-- Registo de alterações; apenas administradores o consultam.
CREATE TABLE IF NOT EXISTS public.item_audit (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 created_at timestamptz NOT NULL DEFAULT now(),
 actor_id uuid,
 actor_email text,
 action text NOT NULL,
 item_id uuid,
 item_name text
);
ALTER TABLE public.item_audit ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "SpawnVault audit read" ON public.item_audit;
CREATE POLICY "SpawnVault audit read" ON public.item_audit FOR SELECT TO authenticated
 USING (public.is_spawnvault_admin());
REVOKE ALL ON public.item_audit FROM anon,authenticated;
GRANT SELECT ON public.item_audit TO authenticated;

CREATE OR REPLACE FUNCTION public.spawnvault_audit_item()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE record_id uuid; record_name text;
BEGIN
 IF TG_OP='DELETE' THEN record_id=OLD.id;record_name=OLD.name;
 ELSE record_id=NEW.id;record_name=NEW.name; END IF;
 INSERT INTO public.item_audit(actor_id,actor_email,action,item_id,item_name)
 VALUES (auth.uid(),(SELECT email FROM auth.users WHERE id=auth.uid()),TG_OP,record_id,record_name);
 RETURN COALESCE(NEW,OLD);
END;
$$;
DROP TRIGGER IF EXISTS spawnvault_items_audit ON public.items;
CREATE TRIGGER spawnvault_items_audit AFTER INSERT OR UPDATE OR DELETE ON public.items
 FOR EACH ROW EXECUTE FUNCTION public.spawnvault_audit_item();

-- Lista de utilizadores limitada a administradores.
CREATE OR REPLACE FUNCTION public.spawnvault_list_users()
RETURNS TABLE(user_id uuid,email text,role text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF NOT public.is_spawnvault_admin() THEN RAISE EXCEPTION 'Acesso não autorizado'; END IF;
 RETURN QUERY SELECT u.id,u.email::text,coalesce(r.role,'user')::text
 FROM auth.users u LEFT JOIN public.user_roles r ON r.user_id=u.id ORDER BY u.email;
END;
$$;
CREATE OR REPLACE FUNCTION public.spawnvault_set_user_role(target_user uuid,new_role text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF NOT public.is_spawnvault_admin() THEN RAISE EXCEPTION 'Acesso não autorizado'; END IF;
 IF new_role NOT IN ('admin','user') THEN RAISE EXCEPTION 'Papel inválido'; END IF;
 IF target_user=auth.uid() AND new_role<>'admin' THEN RAISE EXCEPTION 'Não podes remover o teu próprio acesso de administrador'; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id=target_user) THEN RAISE EXCEPTION 'Utilizador inexistente'; END IF;
 INSERT INTO public.user_roles(user_id,role) VALUES(target_user,new_role)
 ON CONFLICT(user_id) DO UPDATE SET role=EXCLUDED.role;
END;
$$;
REVOKE ALL ON FUNCTION public.spawnvault_list_users() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.spawnvault_set_user_role(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.spawnvault_list_users() TO authenticated;
GRANT EXECUTE ON FUNCTION public.spawnvault_set_user_role(uuid,text) TO authenticated;
COMMIT;


-- FICHEIRO: migration_v22.sql
-- SpawnVault 2.2 — executar APÓS migration_v2.sql e migration_v21.sql.
-- Fazer cópia de segurança das tabelas items, groups, user_roles e storage antes de aplicar.
-- Migração preserva os itens e os UUID existentes. Pode ser repetida sem recriar dados.
BEGIN;

-- Hierarquia: grupos principais (parent_id NULL) e subgrupos (parent_id UUID).
ALTER TABLE public.groups ADD COLUMN IF NOT EXISTS parent_id uuid;
ALTER TABLE public.groups DROP CONSTRAINT IF EXISTS groups_parent_id_fkey;
ALTER TABLE public.groups ADD CONSTRAINT groups_parent_id_fkey FOREIGN KEY(parent_id) REFERENCES public.groups(id) ON DELETE RESTRICT;
CREATE INDEX IF NOT EXISTS groups_parent_id_idx ON public.groups(parent_id);

-- Converter grupos antigos em subgrupos de um grupo principal, sem perder associações.
DO $$
DECLARE root_id uuid;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.groups WHERE parent_id IS NOT NULL)
    AND EXISTS (SELECT 1 FROM public.groups WHERE parent_id IS NULL AND name <> 'Catálogo anterior') THEN
  SELECT id INTO root_id FROM public.groups WHERE name='Catálogo anterior' AND parent_id IS NULL LIMIT 1;
  IF root_id IS NULL THEN
   INSERT INTO public.groups(name) VALUES ('Catálogo anterior') RETURNING id INTO root_id;
  END IF;
  UPDATE public.groups SET parent_id=root_id WHERE parent_id IS NULL AND id<>root_id;
 END IF;
END $$;

-- Impedir que um subgrupo seja pai e que existam ciclos na hierarquia.
CREATE OR REPLACE FUNCTION public.spawnvault_validate_group() RETURNS trigger
LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF NEW.parent_id IS NOT NULL THEN
  IF NEW.id=NEW.parent_id OR NOT EXISTS (SELECT 1 FROM public.groups p WHERE p.id=NEW.parent_id AND p.parent_id IS NULL)
  THEN RAISE EXCEPTION 'O pai tem de ser um grupo principal'; END IF;
  IF EXISTS (SELECT 1 FROM public.groups c WHERE c.parent_id=NEW.id)
  THEN RAISE EXCEPTION 'Não podes transformar um grupo principal com subgrupos num subgrupo'; END IF;
 END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS spawnvault_groups_validate ON public.groups;
CREATE TRIGGER spawnvault_groups_validate BEFORE INSERT OR UPDATE OF parent_id ON public.groups
 FOR EACH ROW EXECUTE FUNCTION public.spawnvault_validate_group();

-- Os itens só podem pertencer a subgrupos.
CREATE OR REPLACE FUNCTION public.spawnvault_validate_item_group() RETURNS trigger
LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.groups g WHERE g.id=NEW.group_id AND g.parent_id IS NOT NULL)
 THEN RAISE EXCEPTION 'Seleciona um subgrupo válido'; END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS spawnvault_items_group_validate ON public.items;
CREATE TRIGGER spawnvault_items_group_validate BEFORE INSERT OR UPDATE OF group_id ON public.items
 FOR EACH ROW EXECUTE FUNCTION public.spawnvault_validate_item_group();

-- Reciclagem: eliminar passa a ser uma atualização de deleted_at.
ALTER TABLE public.items ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
CREATE INDEX IF NOT EXISTS items_deleted_at_idx ON public.items(deleted_at);
DROP POLICY IF EXISTS "SpawnVault read items" ON public.items;
CREATE POLICY "SpawnVault read items" ON public.items FOR SELECT TO authenticated
 USING (deleted_at IS NULL OR public.is_spawnvault_admin());

-- Prevenir nomes de spawn duplicados, inclusive em pedidos simultâneos.
-- Itens já duplicados podem continuar a existir; novas duplicações ficam bloqueadas.
CREATE OR REPLACE FUNCTION public.spawnvault_prevent_duplicate_spawn() RETURNS trigger
LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF NEW.deleted_at IS NULL AND EXISTS(
   SELECT 1 FROM public.items i WHERE i.id<>NEW.id AND i.deleted_at IS NULL
   AND lower(btrim(i.spawn_name))=lower(btrim(NEW.spawn_name))
 ) THEN RAISE EXCEPTION 'Já existe um item ativo com este spawn'; END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS spawnvault_items_unique_spawn ON public.items;
CREATE TRIGGER spawnvault_items_unique_spawn BEFORE INSERT OR UPDATE OF spawn_name,deleted_at ON public.items
 FOR EACH ROW EXECUTE FUNCTION public.spawnvault_prevent_duplicate_spawn();

-- Favoritos privados por utilizador.
CREATE TABLE IF NOT EXISTS public.item_favorites (
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 item_id uuid NOT NULL REFERENCES public.items(id) ON DELETE CASCADE,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,item_id)
);
ALTER TABLE public.item_favorites ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "SpawnVault favorites own" ON public.item_favorites;
CREATE POLICY "SpawnVault favorites own" ON public.item_favorites FOR ALL TO authenticated
 USING(user_id=(SELECT auth.uid())) WITH CHECK(user_id=(SELECT auth.uid()));
GRANT SELECT,INSERT,DELETE ON public.item_favorites TO authenticated;

-- Sugestões: cada utilizador vê os seus pedidos; administradores veem todos.
CREATE TABLE IF NOT EXISTS public.item_requests (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 name text NOT NULL CHECK(length(btrim(name)) BETWEEN 1 AND 120),
 spawn_name text NOT NULL CHECK(length(btrim(spawn_name)) BETWEEN 1 AND 120),
 reason text NOT NULL DEFAULT '',
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected')),
 requested_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
 reviewed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.item_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "SpawnVault requests read" ON public.item_requests;
DROP POLICY IF EXISTS "SpawnVault requests create" ON public.item_requests;
DROP POLICY IF EXISTS "SpawnVault requests review" ON public.item_requests;
CREATE POLICY "SpawnVault requests read" ON public.item_requests FOR SELECT TO authenticated
 USING(requested_by=(SELECT auth.uid()) OR public.is_spawnvault_admin());
CREATE POLICY "SpawnVault requests create" ON public.item_requests FOR INSERT TO authenticated
 WITH CHECK(requested_by=(SELECT auth.uid()) AND status='pending' AND reviewed_by IS NULL AND reviewed_at IS NULL);
CREATE POLICY "SpawnVault requests review" ON public.item_requests FOR UPDATE TO authenticated
 USING(public.is_spawnvault_admin()) WITH CHECK(public.is_spawnvault_admin());
GRANT SELECT,INSERT,UPDATE ON public.item_requests TO authenticated;

-- Histórico existente da v2.1 mantém o registo das alterações a itens.
-- Acrescentar registo de grupos e pedidos sem alterar os dados anteriores.
CREATE OR REPLACE FUNCTION public.spawnvault_audit_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE label text; entity_id uuid;
BEGIN
 IF TG_OP='DELETE' THEN label=OLD.name;entity_id=OLD.id;
 ELSE label=NEW.name;entity_id=NEW.id; END IF;
 INSERT INTO public.item_audit(actor_id,actor_email,action,item_id,item_name)
 VALUES(auth.uid(),(SELECT email FROM auth.users WHERE id=auth.uid()),TG_TABLE_NAME||':'||TG_OP,entity_id,label);
 RETURN COALESCE(NEW,OLD);
END $$;
DROP TRIGGER IF EXISTS spawnvault_groups_audit ON public.groups;
CREATE TRIGGER spawnvault_groups_audit AFTER INSERT OR UPDATE OR DELETE ON public.groups
 FOR EACH ROW EXECUTE FUNCTION public.spawnvault_audit_change();
DROP TRIGGER IF EXISTS spawnvault_requests_audit ON public.item_requests;
CREATE TRIGGER spawnvault_requests_audit AFTER INSERT OR UPDATE OR DELETE ON public.item_requests
 FOR EACH ROW EXECUTE FUNCTION public.spawnvault_audit_change();

COMMIT;

-- Publicação Realtime (requer privilégios do proprietário):
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='items') THEN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.items;
 END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='groups') THEN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.groups;
 END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='item_requests') THEN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.item_requests;
 END IF;
END $$;


-- FICHEIRO: migration_v23_access.sql
-- SpawnVault 2.3: bloqueio de acesso à aplicação, reversível e sem eliminar contas.
-- Executar como proprietário, após as migrações v2, v21 e v22.
-- Não altera auth.users, passwords, user_roles, itens ou os SQL anteriores.
BEGIN;

CREATE TABLE IF NOT EXISTS public.spawnvault_user_access (
 user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
 blocked boolean NOT NULL DEFAULT false,
 reason text NOT NULL DEFAULT '' CHECK(length(reason)<=500),
 updated_at timestamptz NOT NULL DEFAULT now(),
 updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
);
ALTER TABLE public.spawnvault_user_access ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.spawnvault_user_access FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.spawnvault_is_blocked()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM public.spawnvault_user_access WHERE user_id=(SELECT auth.uid()) AND blocked);
$$;
REVOKE ALL ON FUNCTION public.spawnvault_is_blocked() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.spawnvault_is_blocked() TO authenticated;

-- RPCs administrativas existentes reutilizam esta função e ficam igualmente protegidas.
CREATE OR REPLACE FUNCTION public.is_spawnvault_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT auth.uid() IS NOT NULL AND NOT public.spawnvault_is_blocked()
 AND EXISTS(SELECT 1 FROM public.user_roles WHERE user_id=(SELECT auth.uid()) AND role='admin');
$$;
REVOKE ALL ON FUNCTION public.is_spawnvault_admin() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.is_spawnvault_admin() TO authenticated;

CREATE OR REPLACE FUNCTION public.spawnvault_access_status()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE access_row public.spawnvault_user_access%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sessão necessária' USING ERRCODE='42501'; END IF;
 SELECT * INTO access_row FROM public.spawnvault_user_access WHERE user_id=auth.uid();
 RETURN jsonb_build_object('blocked',coalesce(access_row.blocked,false),
 'reason',CASE WHEN coalesce(access_row.blocked,false) THEN coalesce(access_row.reason,'') ELSE '' END);
END;
$$;

CREATE OR REPLACE FUNCTION public.spawnvault_list_user_access()
RETURNS TABLE(user_id uuid,email text,role text,blocked boolean,reason text,updated_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT public.is_spawnvault_admin() THEN RAISE EXCEPTION 'Acesso não autorizado' USING ERRCODE='42501'; END IF;
 RETURN QUERY SELECT u.id,u.email::text,coalesce(r.role,'user')::text,
 coalesce(a.blocked,false),coalesce(a.reason,''),a.updated_at
 FROM auth.users u LEFT JOIN public.user_roles r ON r.user_id=u.id
 LEFT JOIN public.spawnvault_user_access a ON a.user_id=u.id ORDER BY u.email;
END;
$$;

CREATE OR REPLACE FUNCTION public.spawnvault_set_user_block(target_user uuid,blocked_value boolean,block_reason text DEFAULT '')
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE target_email text; target_role text; was_blocked boolean;
BEGIN
 -- Serializa operações de bloqueio e volta a validar o administrador após a espera.
 PERFORM pg_catalog.pg_advisory_xact_lock(236023,1);
 IF NOT public.is_spawnvault_admin() THEN RAISE EXCEPTION 'Acesso não autorizado' USING ERRCODE='42501'; END IF;
 IF blocked_value IS NULL THEN RAISE EXCEPTION 'Estado inválido'; END IF;
 IF length(coalesce(block_reason,''))>500 THEN RAISE EXCEPTION 'Motivo demasiado longo'; END IF;
 IF target_user=auth.uid() AND blocked_value THEN RAISE EXCEPTION 'Não podes bloquear a tua própria conta'; END IF;
 SELECT u.email,coalesce(r.role,'user'),coalesce(a.blocked,false)
 INTO target_email,target_role,was_blocked FROM auth.users u
 LEFT JOIN public.user_roles r ON r.user_id=u.id
 LEFT JOIN public.spawnvault_user_access a ON a.user_id=u.id WHERE u.id=target_user;
 IF NOT FOUND THEN RAISE EXCEPTION 'Utilizador inexistente'; END IF;
 IF blocked_value AND NOT was_blocked AND target_role='admin' AND
 (SELECT count(*) FROM public.user_roles r LEFT JOIN public.spawnvault_user_access a ON a.user_id=r.user_id
 WHERE r.role='admin' AND NOT coalesce(a.blocked,false))<2
 THEN RAISE EXCEPTION 'Não podes bloquear o último administrador ativo'; END IF;
 INSERT INTO public.spawnvault_user_access(user_id,blocked,reason,updated_at,updated_by)
 VALUES(target_user,blocked_value,CASE WHEN blocked_value THEN btrim(coalesce(block_reason,'')) ELSE '' END,now(),auth.uid())
 ON CONFLICT(user_id) DO UPDATE SET blocked=EXCLUDED.blocked,reason=EXCLUDED.reason,updated_at=EXCLUDED.updated_at,updated_by=EXCLUDED.updated_by;
 IF was_blocked IS DISTINCT FROM blocked_value THEN
  INSERT INTO public.item_audit(actor_id,actor_email,action,item_name)
  VALUES(auth.uid(),(SELECT email FROM auth.users WHERE id=auth.uid()),
  CASE WHEN blocked_value THEN 'users:BLOCK' ELSE 'users:UNBLOCK' END,target_email);
 END IF;
END;
$$;

-- A alteração de papéis partilha o mesmo bloqueio transacional, para impedir
-- que uma despromoção simultânea deixe o catálogo sem administrador ativo.
CREATE OR REPLACE FUNCTION public.spawnvault_set_user_role(target_user uuid,new_role text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM pg_catalog.pg_advisory_xact_lock(236023,1);
 IF NOT public.is_spawnvault_admin() THEN RAISE EXCEPTION 'Acesso não autorizado' USING ERRCODE='42501'; END IF;
 IF new_role IS NULL OR new_role NOT IN ('admin','user') THEN RAISE EXCEPTION 'Papel inválido'; END IF;
 IF target_user=auth.uid() AND new_role<>'admin' THEN RAISE EXCEPTION 'Não podes remover o teu próprio acesso de administrador'; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id=target_user) THEN RAISE EXCEPTION 'Utilizador inexistente'; END IF;
 IF new_role<>'admin' AND EXISTS(SELECT 1 FROM public.user_roles r WHERE r.user_id=target_user AND r.role='admin')
 AND NOT EXISTS(SELECT 1 FROM public.spawnvault_user_access a WHERE a.user_id=target_user AND a.blocked)
 AND (SELECT count(*) FROM public.user_roles r LEFT JOIN public.spawnvault_user_access a ON a.user_id=r.user_id WHERE r.role='admin' AND NOT coalesce(a.blocked,false))<2
 THEN RAISE EXCEPTION 'Não podes remover o último administrador ativo'; END IF;
 INSERT INTO public.user_roles(user_id,role) VALUES(target_user,new_role)
 ON CONFLICT(user_id) DO UPDATE SET role=EXCLUDED.role;
END;
$$;
REVOKE ALL ON FUNCTION public.spawnvault_set_user_role(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.spawnvault_set_user_role(uuid,text) TO authenticated;

REVOKE ALL ON FUNCTION public.spawnvault_access_status() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.spawnvault_list_user_access() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.spawnvault_set_user_block(uuid,boolean,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.spawnvault_access_status() TO authenticated;
GRANT EXECUTE ON FUNCTION public.spawnvault_list_user_access() TO authenticated;
GRANT EXECUTE ON FUNCTION public.spawnvault_set_user_block(uuid,boolean,text) TO authenticated;

-- AND restritivo: preserva as políticas e permissões existentes dos utilizadores ativos.
DO $$ DECLARE tbl text; BEGIN
 FOREACH tbl IN ARRAY ARRAY['items','groups','user_roles','item_audit','item_favorites','item_requests'] LOOP
  EXECUTE format('DROP POLICY IF EXISTS "SpawnVault active account" ON public.%I',tbl);
  EXECUTE format('CREATE POLICY "SpawnVault active account" ON public.%I AS RESTRICTIVE FOR ALL TO authenticated USING ((SELECT NOT public.spawnvault_is_blocked())) WITH CHECK ((SELECT NOT public.spawnvault_is_blocked()))',tbl);
 END LOOP;
END $$;
-- Só o bucket da aplicação é restringido; outros buckets não são alterados.
DROP POLICY IF EXISTS "SpawnVault active image account" ON storage.objects;
CREATE POLICY "SpawnVault active image account" ON storage.objects AS RESTRICTIVE FOR ALL TO authenticated
 USING(bucket_id<>'item-images' OR (SELECT NOT public.spawnvault_is_blocked()))
 WITH CHECK(bucket_id<>'item-images' OR (SELECT NOT public.spawnvault_is_blocked()));

NOTIFY pgrst,'reload schema';
COMMIT;


-- FICHEIRO: migration_v23_block_reason.sql
-- Executar após migration_v23_access.sql, incluindo instalações onde esse SQL já foi aplicado.
-- Apenas devolve o motivo de bloqueio da própria conta autenticada.
BEGIN;
CREATE OR REPLACE FUNCTION public.spawnvault_access_status()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE access_row public.spawnvault_user_access%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sessão necessária' USING ERRCODE='42501'; END IF;
 SELECT * INTO access_row FROM public.spawnvault_user_access WHERE user_id=auth.uid();
 RETURN jsonb_build_object('blocked',coalesce(access_row.blocked,false),
 'reason',CASE WHEN coalesce(access_row.blocked,false) THEN coalesce(access_row.reason,'') ELSE '' END);
END;
$$;
REVOKE ALL ON FUNCTION public.spawnvault_access_status() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.spawnvault_access_status() TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;


-- FICHEIRO: migration_v24.sql
-- SpawnVault 2.4.0. Executar após as migrações v2, v21, v22 e v23.
-- Preserva contas e dados. Arquivo pessoal; decisões e criação são transacionais.
BEGIN;
ALTER TABLE public.user_roles DROP CONSTRAINT IF EXISTS user_roles_role_check;
ALTER TABLE public.user_roles ADD CONSTRAINT user_roles_role_check CHECK(role IN ('admin','moderator','user'));

CREATE OR REPLACE FUNCTION public.is_spawnvault_staff()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT auth.uid() IS NOT NULL AND NOT public.spawnvault_is_blocked()
 AND EXISTS(SELECT 1 FROM public.user_roles WHERE user_id=(SELECT auth.uid()) AND role IN ('admin','moderator'));
$$;
REVOKE ALL ON FUNCTION public.is_spawnvault_staff() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.is_spawnvault_staff() TO authenticated;

-- Serializa a verificação de spawns iguais também entre criações simultâneas.
CREATE OR REPLACE FUNCTION public.spawnvault_prevent_duplicate_spawn() RETURNS trigger
LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF NEW.deleted_at IS NULL THEN
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(lower(btrim(NEW.spawn_name)),236024));
  IF EXISTS(SELECT 1 FROM public.items i WHERE i.id<>NEW.id AND i.deleted_at IS NULL
   AND lower(btrim(i.spawn_name))=lower(btrim(NEW.spawn_name)))
  THEN RAISE EXCEPTION 'Já existe um item ativo com este spawn'; END IF;
 END IF;
 RETURN NEW;
END;
$$;

-- Moderadores criam itens ativos, mas não alteram/eliminam itens nem gerem grupos.
DROP POLICY IF EXISTS "SpawnVault staff create items" ON public.items;
CREATE POLICY "SpawnVault staff create items" ON public.items FOR INSERT TO authenticated
 WITH CHECK(public.is_spawnvault_staff() AND created_by=(SELECT auth.uid()) AND deleted_at IS NULL);
DROP POLICY IF EXISTS "SpawnVault staff upload images" ON storage.objects;
CREATE POLICY "SpawnVault staff upload images" ON storage.objects FOR INSERT TO authenticated
 WITH CHECK(bucket_id='item-images' AND public.is_spawnvault_staff() AND owner_id=(SELECT auth.uid()::text));
DROP POLICY IF EXISTS "SpawnVault staff clean own images" ON storage.objects;
CREATE OR REPLACE FUNCTION public.spawnvault_image_in_use(image_name text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM public.items WHERE image_path=image_name);
$$;
REVOKE ALL ON FUNCTION public.spawnvault_image_in_use(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.spawnvault_image_in_use(text) TO authenticated;
CREATE POLICY "SpawnVault staff clean own images" ON storage.objects FOR DELETE TO authenticated
 USING(bucket_id='item-images' AND public.is_spawnvault_staff() AND owner_id=(SELECT auth.uid()::text)
 AND NOT public.spawnvault_image_in_use(name));

DROP POLICY IF EXISTS "SpawnVault requests read" ON public.item_requests;
CREATE POLICY "SpawnVault requests read" ON public.item_requests FOR SELECT TO authenticated
 USING(requested_by=(SELECT auth.uid()) OR public.is_spawnvault_staff());
DROP POLICY IF EXISTS "SpawnVault requests cancel own" ON public.item_requests;
CREATE POLICY "SpawnVault requests cancel own" ON public.item_requests FOR DELETE TO authenticated
 USING(requested_by=(SELECT auth.uid()) AND status='pending');
GRANT DELETE ON public.item_requests TO authenticated;

-- Compatível com clientes anteriores: o servidor fixa sempre a identidade da decisão.
CREATE OR REPLACE FUNCTION public.spawnvault_validate_request_review()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF NOT public.is_spawnvault_staff() OR OLD.status<>'pending' OR NEW.status NOT IN ('approved','rejected')
 THEN RAISE EXCEPTION 'O pedido já foi analisado ou não tens permissão'; END IF;
 IF (NEW.id,NEW.name,NEW.spawn_name,NEW.reason,NEW.requested_by,NEW.created_at)
 IS DISTINCT FROM (OLD.id,OLD.name,OLD.spawn_name,OLD.reason,OLD.requested_by,OLD.created_at)
 THEN RAISE EXCEPTION 'Não podes alterar os dados do pedido'; END IF;
 NEW.reviewed_by=auth.uid(); NEW.reviewed_at=now(); RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS spawnvault_request_review_guard ON public.item_requests;
CREATE TRIGGER spawnvault_request_review_guard BEFORE UPDATE ON public.item_requests
 FOR EACH ROW EXECUTE FUNCTION public.spawnvault_validate_request_review();

CREATE OR REPLACE FUNCTION public.spawnvault_review_request(request_id uuid,decision text,item_data jsonb DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE req public.item_requests%ROWTYPE; item_id uuid;
BEGIN
 IF NOT public.is_spawnvault_staff() THEN RAISE EXCEPTION 'Acesso não autorizado' USING ERRCODE='42501'; END IF;
 IF decision IS NULL OR decision NOT IN ('approved','rejected') THEN RAISE EXCEPTION 'Decisão inválida'; END IF;
 SELECT * INTO req FROM public.item_requests WHERE id=request_id FOR UPDATE;
 IF NOT FOUND OR req.status<>'pending' THEN RAISE EXCEPTION 'O pedido foi eliminado ou já foi analisado'; END IF;
 IF decision='approved' THEN
  IF item_data IS NULL THEN RAISE EXCEPTION 'Preenche os dados do item'; END IF;
  INSERT INTO public.items(name,spawn_name,group_id,category,description,image_path,created_by)
  VALUES(btrim(item_data->>'name'),btrim(item_data->>'spawn_name'),(item_data->>'group_id')::uuid,
   coalesce(item_data->>'category',''),coalesce(item_data->>'description',''),nullif(item_data->>'image_path',''),auth.uid())
  RETURNING id INTO item_id;
 END IF;
 UPDATE public.item_requests SET status=decision WHERE id=request_id;
 RETURN item_id;
END;
$$;
REVOKE ALL ON FUNCTION public.spawnvault_review_request(uuid,text,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.spawnvault_review_request(uuid,text,jsonb) TO authenticated;

CREATE TABLE IF NOT EXISTS public.item_request_archives (
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 request_id uuid NOT NULL REFERENCES public.item_requests(id) ON DELETE CASCADE,
 archived_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(user_id,request_id)
);
ALTER TABLE public.item_request_archives ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "SpawnVault own archives read" ON public.item_request_archives;
CREATE POLICY "SpawnVault own archives read" ON public.item_request_archives FOR SELECT TO authenticated
 USING(user_id=(SELECT auth.uid()) AND NOT public.spawnvault_is_blocked());
DROP POLICY IF EXISTS "SpawnVault own archives create" ON public.item_request_archives;
CREATE POLICY "SpawnVault own archives create" ON public.item_request_archives FOR INSERT TO authenticated
 WITH CHECK(user_id=(SELECT auth.uid()) AND NOT public.spawnvault_is_blocked()
 AND EXISTS(SELECT 1 FROM public.item_requests r WHERE r.id=request_id AND r.status IN ('approved','rejected')));
DROP POLICY IF EXISTS "SpawnVault own archives remove" ON public.item_request_archives;
CREATE POLICY "SpawnVault own archives remove" ON public.item_request_archives FOR DELETE TO authenticated
 USING(user_id=(SELECT auth.uid()) AND NOT public.spawnvault_is_blocked());
GRANT SELECT,INSERT,DELETE ON public.item_request_archives TO authenticated;

-- Identidades apenas para pedidos visíveis ao chamador. Não expõe a lista de contas/emails.
CREATE OR REPLACE FUNCTION public.spawnvault_list_requests()
RETURNS SETOF jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF auth.uid() IS NULL OR public.spawnvault_is_blocked() THEN RAISE EXCEPTION 'Acesso não autorizado' USING ERRCODE='42501'; END IF;
 RETURN QUERY SELECT to_jsonb(r)||jsonb_build_object(
  'requester_username',coalesce(nullif(btrim(u.raw_user_meta_data->>'username'),''),nullif(btrim(u.raw_user_meta_data->>'user_name'),''),nullif(btrim(u.raw_user_meta_data->>'display_name'),''),nullif(split_part(u.email,'@',1),''),r.requested_by::text),
  'reviewer_username',CASE WHEN r.reviewed_by IS NULL THEN NULL ELSE coalesce(nullif(btrim(v.raw_user_meta_data->>'username'),''),nullif(btrim(v.raw_user_meta_data->>'user_name'),''),nullif(btrim(v.raw_user_meta_data->>'display_name'),''),nullif(split_part(v.email,'@',1),''),r.reviewed_by::text) END,
  'is_archived',EXISTS(SELECT 1 FROM public.item_request_archives a WHERE a.request_id=r.id AND a.user_id=auth.uid()))
 FROM public.item_requests r LEFT JOIN auth.users u ON u.id=r.requested_by LEFT JOIN auth.users v ON v.id=r.reviewed_by
 WHERE r.requested_by=auth.uid() OR public.is_spawnvault_staff() ORDER BY r.created_at DESC,r.id;
END;
$$;
REVOKE ALL ON FUNCTION public.spawnvault_list_requests() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.spawnvault_list_requests() TO authenticated;

-- Mesmas proteções da v2.3, incluindo a serialização com os bloqueios de contas.
CREATE OR REPLACE FUNCTION public.spawnvault_set_user_role(target_user uuid,new_role text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM pg_catalog.pg_advisory_xact_lock(236023,1);
 IF NOT public.is_spawnvault_admin() THEN RAISE EXCEPTION 'Acesso não autorizado' USING ERRCODE='42501'; END IF;
 IF new_role IS NULL OR new_role NOT IN ('admin','moderator','user') THEN RAISE EXCEPTION 'Papel inválido'; END IF;
 IF target_user=auth.uid() AND new_role<>'admin' THEN RAISE EXCEPTION 'Não podes remover o teu próprio acesso de administrador'; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id=target_user) THEN RAISE EXCEPTION 'Utilizador inexistente'; END IF;
 IF new_role<>'admin' AND EXISTS(SELECT 1 FROM public.user_roles r WHERE r.user_id=target_user AND r.role='admin')
 AND NOT EXISTS(SELECT 1 FROM public.spawnvault_user_access a WHERE a.user_id=target_user AND a.blocked)
 AND (SELECT count(*) FROM public.user_roles r LEFT JOIN public.spawnvault_user_access a ON a.user_id=r.user_id WHERE r.role='admin' AND NOT coalesce(a.blocked,false))<2
 THEN RAISE EXCEPTION 'Não podes remover o último administrador ativo'; END IF;
 INSERT INTO public.user_roles(user_id,role) VALUES(target_user,new_role) ON CONFLICT(user_id) DO UPDATE SET role=EXCLUDED.role;
END;
$$;
NOTIFY pgrst,'reload schema';
COMMIT;

