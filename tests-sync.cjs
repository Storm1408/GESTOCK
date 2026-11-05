const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const renderer=fs.readFileSync(__dirname+'/renderer.js','utf8');
const access=fs.readFileSync(__dirname+'/access.js','utf8').split('async function refreshAccessStatus()')[0];
const load=renderer.match(/^async function loadOnline\(\).*$/m)?.[0];
assert(load,'loadOnline function must exist');
function context(blocked=false){
 const calls=[];let renders=0;
 const ctx={session:{user:{id:'test-user',email:'test@example.invalid',user_metadata:{}}},role:'user',groups:[],items:[],sessionUsername:'',
 document:{querySelectorAll:()=>[],getElementById:()=>({value:'',textContent:''})},
 normalizeRow:x=>x,loadFavorites:async()=>{},loadRequests:async()=>{},loadTrash:async()=>{},refreshImageUrls:async()=>{},render:()=>{renders++;},updateConnection:()=>{},isAdmin:()=>ctx.role==='admin',onSession:async value=>{ctx.session=value;},
 client:{rpc:async name=>{calls.push(name);return{data:{blocked,reason:'Suspenso'}};},auth:{signOut:async()=>{}},from:table=>{
 calls.push(table);const result={data:table==='user_roles'?{role:'admin'}:table==='spawnvault_accounts'?{username:'owner'}:[],error:null};
 const query={select(){return this;},order(){return this;},is(){return this;},eq(){return this;},maybeSingle(){return this;},then(resolve,reject){return Promise.resolve(result).then(resolve,reject);}};return query;
 }}};
 vm.createContext(ctx);vm.runInContext(access+'\n'+load,ctx);
 return {ctx,calls,renders:()=>renders};
}
(async()=>{
 const allowed=context();await vm.runInContext('loadOnline()',allowed.ctx);
 assert.equal(allowed.calls[0],'spawnvault_access_status');assert(allowed.calls.includes('items'));assert.equal(allowed.ctx.sessionUsername,'owner');assert.equal(allowed.renders(),1);
 const blocked=context(true);await assert.rejects(()=>vm.runInContext('loadOnline()',blocked.ctx),e=>e.code==='SPAWNVAULT_BLOCKED');assert.equal(blocked.ctx.session,null);assert(!blocked.calls.includes('items'));assert.equal(blocked.renders(),0);
 console.log('Sync regression passed: post-login loads with real access helper; blocked sessions cannot load catalogue.');
})().catch(e=>{console.error(e);process.exitCode=1;});
