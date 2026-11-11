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
const migrations=fs.readdirSync(path.join(__dirname,'supabase/migrations'));
await db.exec(fs.readFileSync(path.join(__dirname,'supabase/migrations',migrations.find(x=>x.endsWith('_gestock_v141.sql'))),'utf8'));
const product=async name=>(await as('dev',"select gestock_product($1,'Marca') id",[name]))[0].id;
const plan=async who=>(await as(who,'select gestock_planning() data'))[0].data;
const alerts=async who=>(await as(who,'select gestock_alerts() data'))[0].data;
const supplierArgs=[null,'Material de Saúde','Ana','210 000 000','ana@example.test'];
const p=await product('Compressas');
const second=await product('Ligaduras');
const empty=await product('Máscaras');
const supplier=(await as('admin','select gestock_supplier($1,$2,$3,$4,$5) id',supplierArgs))[0].id;
await deny('mod','select gestock_supplier($1,$2,$3,$4,$5)',supplierArgs);
await deny('user','select gestock_planning()');
await deny('user','select gestock_alerts()');
await deny('admin','select * from gestock_suppliers');
await deny('admin','select gestock_supplier($1,$2,$3,$4,$5)',[null,'material de saúde','','','']);
await as('admin','select gestock_supplier($1,$2,$3,$4,$5)',[supplier,'Fornecedor Saúde','João','','joao@example.test']);
await as('admin','select gestock_material_plan($1,$2,10,8,20)',[p,supplier]);
await as('admin','select gestock_material_plan($1,null,null,5,10)',[second]);
await as('admin','select gestock_material_plan($1,null,1,0,100)',[empty]);
await deny('mod','select gestock_material_plan($1,null,10,8,20)',[p]);
assert.equal((await plan('admin')).suppliers[0].contact,'João');
assert.deepEqual((await plan('mod')).products.map(x=>x.id),[second,p]);
assert.deepEqual((await plan('mod')).suppliers,[]);
assert.equal((await plan('mod')).products[1].central_minimum,null);
assert.equal((await as('user','select gestock_snapshot() data'))[0].data.products.find(x=>x.id===p).supplier_id,undefined);
await as('admin','select gestock_supplier(p_id=>$1,p_delete=>true)',[supplier]);
assert.equal((await plan('admin')).products.find(x=>x.id===p).supplier_id,null);

await db.query(`insert into gestock_batches(product_id,lot,expiry,central,medical) values
  ($1,'Fora do prazo',(now() at time zone 'Europe/Lisbon')::date-1,99,0),
  ($1,'A vencer',(now() at time zone 'Europe/Lisbon')::date+30,11,2),
  ($2,'Longe',(now() at time zone 'Europe/Lisbon')::date+31,1,0),
  ($3,'Vazio',(now() at time zone 'Europe/Lisbon')::date,0,0)`,[p,second,empty]);
const alert=await alerts('mod');
assert.deepEqual(alert.expiries.map(x=>[x.lot,x.central,x.medical]),[['Fora do prazo','99','0'],['A vencer','11','2']]);
assert.deepEqual(alert.minimums.map(x=>[x.name,x.available,x.minimum]),[['Compressas','11',10],['Máscaras','0',1]]);
await as('dev',"select gestock_set_permission('moderator','read',false)");
await deny('mod','select gestock_alerts()');
await as('dev',"select gestock_set_permission('moderator','read',true)");

const request='20000000-0000-4000-8000-000000000001';
const restock=(who,id,lines)=>as(who,'select gestock_restock($1,$2) id',[id,JSON.stringify(lines)]);
const line={product:p,counted:4,quantity:4,target:8,expected:'2'};
const low={product:second,counted:0,quantity:2,target:5,expected:'0'};
await assert.rejects(()=>restock('mod',request,[line,{...line,product:empty,target:0,expected:'0'}]),/ultrapassa/);
assert.equal((await plan('mod')).products.find(x=>x.id===p).system_medical,'2');
assert.equal((await db.query("select count(*)::int n from gestock_movements where kind='replenish'")).rows[0].n,0);
await assert.rejects(()=>restock('mod',request,[line,low]),/Stock insuficiente/);
await as('admin',"select gestock_transfer('receive',$1,4,'Novo','2099-12-31')",[second]);
await assert.rejects(()=>restock('mod',request,[{...line,expected:'3'}]),/mudou/);
await assert.rejects(()=>restock('mod',request,[{...line,quantity:5}]),/ultrapassa/);
await assert.rejects(()=>restock('user',request,[line]),/Sem permissão/);
assert.equal((await restock('mod',request,[line,low]))[0].id,request);
assert.equal((await restock('mod',request,[line,low]))[0].id,request);
await assert.rejects(()=>restock('admin',request,[line,low]),/já utilizado/);
const actual=await plan('mod');
assert.equal(actual.products.find(x=>x.id===p).system_medical,'6');
assert.equal(actual.products.find(x=>x.id===second).system_medical,'2');
const movements=(await db.query("select actor,quantity::int from gestock_movements where kind='replenish'")).rows;
assert.equal(movements.length,3);
assert(movements.every(m=>m.actor===ids.mod));
assert.equal((await db.query('select count(*)::int n from gestock_restock_runs')).rows[0].n,1);
assert.equal((await db.query("select has_function_privilege('anon','public.gestock_alerts()','EXECUTE') allowed")).rows[0].allowed,false);
console.log('Gestock 1.4.1 SQL passed: suppliers, scoped access, alert thresholds, ordered atomic restock and safe retries.');
}finally{await db.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
