const {PGlite}=require('@electric-sql/pglite');const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');const db=new PGlite();const ids={admin:'10000000-0000-4000-8000-000000000001',mod:'10000000-0000-4000-8000-000000000002',user:'10000000-0000-4000-8000-000000000003',same:'10000000-0000-4000-8000-000000000004'};
async function migrate(file){await db.exec(fs.readFileSync(path.join(__dirname,'supabase',file),'utf8').replace(/create extension if not exists pgcrypto;/ig,'').split('-- Publicação Realtime')[0])}
(async()=>{try{
 await db.exec(`CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role BYPASSRLS;CREATE SCHEMA auth;CREATE SCHEMA storage;
 CREATE TABLE auth.users(id uuid PRIMARY KEY,email text,raw_user_meta_data jsonb DEFAULT '{}',raw_app_meta_data jsonb DEFAULT '{}',encrypted_password text DEFAULT 'existing-hash');
 CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
 GRANT USAGE ON SCHEMA public,auth,storage TO authenticated,anon,service_role;
 CREATE TABLE storage.buckets(id text PRIMARY KEY,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 CREATE TABLE storage.objects(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),bucket_id text,name text,owner_id text);
 ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;GRANT SELECT,INSERT,UPDATE,DELETE ON storage.objects TO authenticated;`);
 for(const file of ['schema.sql','migration_v2.sql','migration_v21.sql','migration_v22.sql','migration_v23_access.sql','migration_v23_block_reason.sql','migration_v24.sql'])await migrate(file);
 for(const [who,id]of Object.entries(ids))await db.query('INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES($1,$2,$3)',[id,(who==='same'?'user':who)+'@example.invalid',who==='admin'?{username:'$torm'}:who==='mod'?{username:'Mod Storm'}:{}]);
 await db.query("INSERT INTO public.user_roles VALUES($1,'admin'),($2,'moderator')",[ids.admin,ids.mod]);

await migrate('migration_v241.sql');await migrate('migration_gestock_v1.sql');
await db.query('insert into gestock_owner(user_id) values($1)',[ids.admin]);
for(const suffix of ['_gestock_v110.sql','_gestock_v120.sql']){const f=fs.readdirSync('supabase/migrations').find(x=>x.endsWith(suffix));await db.exec(fs.readFileSync('supabase/migrations/'+f,'utf8'));}
const fresh='10000000-0000-4000-8000-000000000099';await db.query("select gestock_reserve_account($1,$2,'FreshAccount','user')",[fresh,ids.admin]);await db.query('insert into auth.users(id,email) values($1,$2)',[fresh,'fresh@example.invalid']);
await db.exec('set role authenticated');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[fresh]);assert((await db.query('select gestock_access_status() s')).rows[0].s.password_required);assert.equal((await db.query('select * from items')).rows.length,0);await assert.rejects(()=>db.query("select spawnvault_set_username($1,'Bypass')",[fresh]));await assert.rejects(()=>db.query('select gestock_snapshot()'));await db.exec('reset role');
await db.query('select gestock_finish_password($1)',[fresh]);await db.exec('set role authenticated');assert.equal((await db.query('select gestock_access_status() s')).rows[0].s.password_required,false);await db.query('select gestock_snapshot()');await db.exec('reset role');
console.log('Gestock 1.2 integration passed against all inherited migrations and actual Auth provisioning trigger.');
}finally{await db.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
