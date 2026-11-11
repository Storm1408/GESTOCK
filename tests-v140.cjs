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

const migration3=fs.readdirSync('supabase/migrations').find(x=>x.endsWith('_gestock_v130.sql'));await db.exec(fs.readFileSync('supabase/migrations/'+migration3,'utf8'));

const migration4=fs.readdirSync('supabase/migrations').find(x=>x.endsWith('_gestock_v140.sql'));await db.exec(fs.readFileSync('supabase/migrations/'+migration4,'utf8'));
const p=(await as('dev',"select gestock_product('Compressas','Marca') id"))[0].id;
const vehicle=(await as('admin',"select gestock_vehicle('ABSC 01') id"))[0].id;
for(const [lot,expiry] of [['L1','2099-12-30'],['L2','2099-12-31']]){
  await as('admin',"select gestock_transfer('receive',$1,20,$2,$3)",[p,lot,expiry]);
}
await as('admin',"select gestock_transfer('replenish',$1,5)",[p]);
const batch=(await db.query("select * from gestock_batches where product_id=$1 and lot='L1'",[p])).rows[0];
const lines=JSON.stringify([{product:p,quantity:2}]);await as('user','select gestock_issue($1,$2,gen_random_uuid())',[vehicle,lines]);
const beforeHistory=(await as('user','select gestock_history() h'))[0].h;
await deny('user',"select gestock_remove_lot($1,'medical',3,'Retirar lote')",[batch.id]);
await deny('mod',"select gestock_remove_lot($1,'central',15,'Retirar lote')",[batch.id]);
await deny('mod',"select gestock_remove_lot($1,'medical',5,'Valor desatualizado')",[batch.id]);
await as('mod',"select gestock_remove_lot($1,'medical',3,'Lote danificado')",[batch.id]);
let row=(await db.query('select * from gestock_batches where id=$1',[batch.id])).rows[0];assert.equal(Number(row.medical),0);assert.equal(Number(row.central),15);
assert.deepEqual((await as('user','select gestock_history() h'))[0].h,beforeHistory);
let stockReport=(await as('admin',"select gestock_report('medical') r"))[0].r;assert.equal(stockReport.rows.length,0);
let issueReport=(await as('admin',"select gestock_report('consume') r"))[0].r;assert.equal(issueReport.rows[0].quantity,2);assert.equal(issueReport.rows[0].lot,'L1');
await as('admin',"select gestock_remove_lot($1,'central',15,'Retirada do lote')",[batch.id]);
assert.equal((await db.query('select count(*)::int n from gestock_batches where id=$1',[batch.id])).rows[0].n,1,'Historical batch metadata must remain available');
assert.equal(Number((await db.query("select central from gestock_batches where product_id=$1 and lot='L2'",[p])).rows[0].central),20);
stockReport=(await as('admin',"select gestock_report('inventory') r"))[0].r;assert.equal(stockReport.rows.length,1);assert.equal(stockReport.rows[0].lot,'L2');
const logs=(await as('admin','select gestock_logs() l'))[0].l;assert(logs.some(l=>l.action==='stock:REMOVE_LOT'&&l.actor_email==='MOD'));assert.equal((await db.query('select count(*)::int n from gestock_adjustments')).rows[0].n,2);
// Reaching zero through a normal issue keeps its report but no active inventory entry.
await as('admin',"select gestock_transfer('receive',$1,6,'L3','2099-11-30')",[p]);await as('mod',"select gestock_transfer('replenish',$1,6)",[p]);
const b3=(await db.query("select * from gestock_batches where product_id=$1 and lot='L3'",[p])).rows[0];await as('user','select gestock_issue($1,$2,gen_random_uuid())',[vehicle,JSON.stringify([{product:p,quantity:6}])]);
assert.equal(Number((await db.query('select medical from gestock_batches where id=$1',[b3.id])).rows[0].medical),0);assert.equal((await as('admin',"select gestock_report('medical') r"))[0].r.rows.length,0);assert.equal((await as('user','select gestock_history() h'))[0].h.length,2);
// Default grants, Developer revocation, and mandatory minimum roles are server checked.
assert((await as('mod','select gestock_access_status() s'))[0].s.permissions.includes('remove_medical_lot'));
await as('dev',"select gestock_set_permission('moderator','remove_medical_lot',false)");assert(!(await as('mod','select gestock_access_status() s'))[0].s.permissions.includes('remove_medical_lot'));
await as('admin',"select gestock_transfer('replenish',$1,1)",[p]);const remaining=(await db.query('select * from gestock_batches where medical>0')).rows[0];await deny('mod',"select gestock_remove_lot($1,'medical',1,'Permissão retirada')",[remaining.id]);
await as('dev',"select gestock_set_permission('moderator','remove_medical_lot',true)");await as('mod',"select gestock_remove_lot($1,'medical',1,'Permissão reposta')",[remaining.id]);
await deny('dev',"select gestock_set_permission('user','remove_medical_lot',true)");await deny('dev',"select gestock_set_permission('moderator','remove_central_lot',true)");
await db.query('insert into spawnvault_user_access values($1,true)',[ids.admin]);await deny('admin',"select gestock_remove_lot($1,'central',19,'Conta bloqueada')",[remaining.id]);
assert.equal((await db.query("select has_function_privilege('anon','public.gestock_remove_lot(uuid,text,bigint,text)','EXECUTE') allowed")).rows[0].allowed,false);
console.log('Gestock 1.4 SQL passed: scoped lot removal, minimum roles, live permission revocation, audit, stale-value rejection, zero-stock reports and historical preservation.');
}finally{await db.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
