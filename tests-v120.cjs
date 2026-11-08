const {PGlite}=require('@electric-sql/pglite');const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const db=new PGlite();const ids={dev:'10000000-0000-4000-8000-000000000001',admin:'10000000-0000-4000-8000-000000000002',user:'10000000-0000-4000-8000-000000000003',mod:'10000000-0000-4000-8000-000000000004'};
async function as(who,sql,args=[]){await db.exec('set role authenticated');try{await db.query("select set_config('request.jwt.claim.sub',$1,false)",[ids[who]]);return(await db.query(sql,args)).rows;}finally{await db.exec('reset role');}}
const deny=async(who,sql,args=[])=>assert.rejects(()=>as(who,sql,args));
(async()=>{try{
await db.exec(`create role anon;create role service_role;create role authenticated;create schema auth;create schema storage;
create table auth.users(id uuid primary key,email text,raw_app_meta_data jsonb);create table public.item_audit(actor_id uuid,actor_email text,action text,item_name text,created_at timestamptz default now());create table public.user_roles(user_id uuid primary key references auth.users,role text);create table public.spawnvault_accounts(user_id uuid primary key,username text);create table public.spawnvault_user_access(user_id uuid primary key,blocked boolean);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create function public.spawnvault_is_blocked() returns boolean language sql security definer as $$select exists(select 1 from public.spawnvault_user_access where user_id=auth.uid() and blocked)$$;
create table public.items(id uuid primary key default gen_random_uuid());alter table public.items enable row level security;grant insert on public.items to authenticated;create policy test_permissive on public.items for insert to authenticated with check(true);
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text);alter table storage.objects enable row level security;
grant usage on schema public,auth,storage to anon,authenticated;`);
await db.exec(fs.readFileSync(path.join(__dirname,'supabase/migration_gestock_v1.sql'),'utf8'));
const migration=fs.readdirSync(path.join(__dirname,'supabase/migrations')).find(p=>p.endsWith('_gestock_v110.sql'));await db.exec(fs.readFileSync(path.join(__dirname,'supabase/migrations',migration),'utf8'));
for(const [who,id]of Object.entries(ids)){await db.query('insert into auth.users(id) values($1)',[id]);await db.query('insert into public.user_roles values($1,$2)',[id,who==='dev'?'admin':who==='mod'?'moderator':who]);await db.query('insert into public.spawnvault_accounts values($1,$2)',[id,who]);}
await db.query('insert into public.gestock_owner(user_id) values($1)',[ids.dev]);

const migration2=fs.readdirSync('supabase/migrations').find(x=>x.endsWith('_gestock_v120.sql'));await db.exec(fs.readFileSync('supabase/migrations/'+migration2,'utf8'));
await db.exec('create trigger test_provision after insert on auth.users for each row execute function public.spawnvault_provision_account()');
const p=(await as('dev',"select gestock_product('Compressas','Marca') id"))[0].id;
const v=(await as('admin',"select gestock_vehicle('ABSC 01') id"))[0].id;
await as('admin',"select gestock_transfer('receive',$1,5000000000,'L1','2099-12-31')",[p]);
assert.equal(Number((await db.query('select central from gestock_batches')).rows[0].central),5000000000);
await as('mod',"select gestock_transfer('replenish',$1,999)",[p]);
await deny('mod',"select gestock_transfer('replenish',$1,1000)",[p]);
await as('user','select gestock_issue($1,$2,gen_random_uuid())',[v,JSON.stringify([{product:p,quantity:2}])]);
assert.equal((await db.query("select count(*)::int n from item_audit where action like 'stock:%'")).rows[0].n,3);
assert((await as('admin','select gestock_logs() r'))[0].r.some(x=>x.actor_email==='USER'));
const rpt=(await as('admin',"select gestock_report('inventory') r"))[0].r;assert.equal(rpt.issuer,'ADMIN');assert.equal(rpt.rows[0].quantity,4999999001);
// Every permission can be granted and withdrawn immediately; owner access stays protected.
for(const action of ['read','receive','consume','replenish','products','targets','reports','vehicles','images','stock','users']){
 await as('dev','select gestock_set_permission($1,$2,true)',['user',action]);assert.equal((await as('user','select gestock_can($1) c',[action]))[0].c,true);
 await as('dev','select gestock_set_permission($1,$2,false)',['user',action]);assert.equal((await as('user','select gestock_can($1) c',[action]))[0].c,false);
}
await deny('admin',"select gestock_set_permission('user','consume',true)");
await deny('admin',"select gestock_reserve_account(gen_random_uuid(),$1,'NewUser','user')",[ids.admin]);
const fresh='10000000-0000-4000-8000-000000000099';
await assert.rejects(()=>db.query('insert into auth.users(id) values($1)',[fresh]));
await db.query("select gestock_reserve_account($1,$2,'NewUser','user')",[fresh,ids.dev]);
// GoTrue inserts without the requested app metadata. Reservation must provision this safely.
await db.query('insert into auth.users(id,email) values($1,$2)',[fresh,'fixture@example.invalid']);
ids.fresh=fresh;const identity=(await as('fresh','select gestock_access_status() s'))[0].s;assert(identity.password_required);assert.equal(identity.permissions.length,0);
await deny('fresh','select gestock_snapshot()');await deny('fresh','select gestock_finish_password($1)',[fresh]);await deny('fresh',"select gestock_product('No','No')");
await db.query('select gestock_finish_password($1)',[fresh]);assert.equal((await as('fresh','select gestock_access_status() s'))[0].s.password_required,false);
assert.equal((await db.query('select username from spawnvault_accounts where user_id=$1',[fresh])).rows[0].username,'NEWUSER');
assert.equal((await db.query('select count(*)::int n from gestock_account_reservations')).rows[0].n,0);
// Metadata cannot be used to bypass the administrative reservation.
await assert.rejects(()=>db.query('insert into auth.users(id,raw_app_meta_data) values(gen_random_uuid(),$1)',[JSON.stringify({spawnvault_created_by:ids.dev,spawnvault_username:'Spoofed',spawnvault_role:'admin'})]));
console.log('Gestock 1.2 SQL passed: big entries, atomic movements/audit, editable permissions, server reservation, first-login gate and owner protection.');
}finally{await db.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
