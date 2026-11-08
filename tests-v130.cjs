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
const p=(await as('dev',"select gestock_product('Compressas','Marca') id"))[0].id,p2=(await as('dev',"select gestock_product('Luvas','Marca') id"))[0].id;
const v=(await as('admin',"select gestock_vehicle('ABSC 01') id"))[0].id;
await as('admin',"select gestock_transfer('receive',$1,5000,'L1','2099-11-30')",[p]);await as('admin',"select gestock_transfer('receive',$1,5000,'L2','2099-12-31')",[p]);
await as('admin',"select gestock_transfer('replenish',$1,3)",[p]);await as('admin',"select gestock_transfer('replenish',$1,3)",[p]);
const b=(await db.query("select id,central,medical from gestock_batches where product_id=$1 order by expiry",[p])).rows[0];
// Invalid quantities identify every wrong material, but expose no stock quantities.
let error;try{await as('user','select gestock_issue($1,$2,gen_random_uuid())',[v,JSON.stringify([{product:p,quantity:8},{product:p2,quantity:2}])]);}catch(e){error=e;}
assert(error);const detail=JSON.parse(error.detail);assert.equal(detail.code,'GESTOCK_INSUFFICIENT_STOCK');assert.deepEqual(new Set(detail.products),new Set([p,p2]));assert(!error.detail.includes('quantity'));assert(!error.detail.includes('medical'));
assert.equal((await db.query('select count(*)::int n from gestock_issues')).rows[0].n,0);assert.equal(Number((await db.query('select medical from gestock_batches where id=$1',[b.id])).rows[0].medical),6);
await deny('user',`select gestock_adjust($1,'medical',20,6,'Correção de contagem')`,[b.id]);await deny('mod',`select gestock_adjust($1,'medical',20,6,'Correção de contagem')`,[b.id]);
await as('admin',`select gestock_adjust($1,'medical',10,6,'Correção de contagem')`,[b.id]);await deny('admin',`select gestock_adjust($1,'medical',12,6,'Contagem desatualizada')`,[b.id]);
await as('admin',`select gestock_adjust($1,'central',0,4994,'Correção de entrada')`,[b.id]);
let balances=(await db.query('select central,medical from gestock_batches where id=$1',[b.id])).rows[0];assert.equal(Number(balances.central),0);assert.equal(Number(balances.medical),10);
assert.equal((await db.query('select count(*)::int n from gestock_adjustments')).rows[0].n,2);assert((await as('admin','select gestock_logs() l'))[0].l.some(x=>x.action==='stock:ADJUST'&&x.item_name.includes('6 → 10')));
await deny('admin',`select gestock_adjust($1,'medical',-1,10,'Inválido')`,[b.id]);await deny('admin',`select gestock_adjust($1,'medical',9,10,'')`,[b.id]);
// Permission revocation applies even to administrators; no direct adjustment writes.
await as('dev',"select gestock_set_permission('admin','stock',false)");await deny('admin',`select gestock_adjust($1,'medical',9,10,'Correção recusada')`,[b.id]);await as('dev',"select gestock_set_permission('admin','stock',true)");
await deny('admin','select * from gestock_adjustments');await deny('user','select * from gestock_adjustments');
const req='30000000-0000-4000-8000-000000000001',lines=JSON.stringify([{product:p,quantity:2}]);const first=(await as('user','select gestock_issue($1,$2,$3) id',[v,lines,req]))[0].id;assert.equal((await as('user','select gestock_issue($1,$2,$3) id',[v,lines,req]))[0].id,first);
let history=(await as('user','select gestock_history() h'))[0].h;assert.equal(history.length,1);assert.equal(history[0].lines[0].quantity,2);assert.equal(history[0].vehicle,'ABSC 01');assert.equal((await as('mod','select gestock_history() h'))[0].h.length,0);
// Split batches aggregate to one material per issue; another actor's issue stays private.
await as('dev','select gestock_issue($1,$2,gen_random_uuid())',[v,JSON.stringify([{product:p,quantity:1}])]);assert.equal((await as('user','select gestock_history() h'))[0].h.length,1);
// More than 50 issues: bounded and ordered, with no actor parameter to access others.
for(let i=0;i<55;i++){const issue=(await db.query(`insert into gestock_issues(request_id,vehicle_id,vehicle_name,actor,lines,created_at) values(gen_random_uuid(),$1,'ABSC 01',$2,'[]',now()+($3::int)*interval '1 second') returning id`,[v,ids.user,i])).rows[0].id;await db.query(`insert into gestock_movements(batch_id,kind,quantity,actor,issue_id,created_at) values($1,'consume',1,$2,$3,now()+($4::int)*interval '1 second')`,[b.id,ids.user,issue,i]);}
history=(await as('user','select gestock_history() h'))[0].h;assert.equal(history.length,50);assert(new Date(history[0].created_at)>=new Date(history[49].created_at));
await db.query('insert into spawnvault_user_access values($1,true)',[ids.user]);await deny('user','select gestock_history()');
console.log('Gestock 1.3 SQL passed: precise private quantity errors, atomic rollback, own bounded history, admin-only corrections, audit and stale-data protection.');
}finally{await db.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
