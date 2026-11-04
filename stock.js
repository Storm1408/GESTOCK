// Additive GESTOCK client. Authorization and stock calculations live in SQL RPCs.
(() => {
 const el=id=>document.getElementById(id), esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 let snapshot=null, account=null, busy=false, generation=0;
 const labels={developer:'Developer',admin:'Admin',moderator:'Moderador',user:'Utilizador',receive:'Entrada',consume:'Consumo',replenish:'Reposição'};
 const can=a=>snapshot?.permissions.includes(a);
 async function rpc(name,args={}) {
  if(!client||!session) throw Error('Inicia sessão no projeto GESTOCK configurado para gerir stocks.');
  const {data,error}=await client.rpc('gestock_'+name,args);
  if(error) throw Error(['PGRST202','42883'].includes(error.code)?'Módulo de stocks não instalado no servidor. Consulta GESTOCK.md.':error.message);
  return data;
 }
 const options=()=>snapshot.products.map(p=>`<option value="${esc(p.id)}">${esc(p.name)} · ${esc(p.brand)}</option>`).join('');
 function render() {
  const s=snapshot, product=id=>s.products.find(p=>p.id===id), productName=id=>{const p=product(id);return p?`${p.name} · ${p.brand}`:id;};
  el('stockStatus').textContent=`${labels[s.role]} · Posto Médico e Armazém de Saúde`;
  const batchOptions=s.batches.map(b=>`<option value="${esc(b.id)}">${esc(productName(b.product_id))} · ${esc(b.lot)} · ${esc(b.expiry)} · Saúde ${b.central} / Posto ${b.medical}</option>`).join('');
  el('stockContent').innerHTML=`<button type="button" class="btn" data-refresh>Atualizar</button>
  <h3>Inventário por lote</h3><label>Pesquisar produto<input type="search" id="stockSearch"></label>
  <div class="stock-scroll"><table><thead><tr><th>Produto / marca</th><th>Lote</th><th>Validade</th><th>Armazém de Saúde</th><th>Posto Médico</th></tr></thead><tbody id="stockRows">${s.batches.map(b=>`<tr><td>${esc(productName(b.product_id))}</td><td>${esc(b.lot)}</td><td>${esc(b.expiry)}</td><td>${b.central}</td><td>${b.medical}</td></tr>`).join('')}</tbody></table></div>
  <h3>Necessidades do Posto Médico</h3>${s.products.map(p=>{const total=s.batches.filter(b=>b.product_id===p.id&&b.expiry>=new Date().toLocaleDateString('sv-SE')).reduce((n,b)=>n+b.medical,0);return `<p>${esc(p.name)} · ${esc(p.brand)}: ${total} válidos / obrigatório ${p.target} · repor ${Math.max(0,p.target-total)}</p>`;}).join('')}
  ${can('products')?`<h3>Novo produto</h3><form data-operation="product"><label>Nome<input name="p_name" required maxlength="120"></label><label>Marca<input name="p_brand" required maxlength="120"></label><button class="btn">Guardar produto</button></form>`:''}
  ${can('targets')?`<h3>Quantidade obrigatória</h3><form data-operation="target"><label>Produto<select name="p_product" required>${options()}</select></label><label>Quantidade<input name="p_target" type="number" min="0" step="1" required></label><button class="btn">Guardar quantidade</button></form>`:''}
  ${can('receive')?`<h3>Entrada no Armazém de Saúde</h3><form data-operation="move"><input name="p_kind" value="receive" type="hidden"><label>Produto<select name="p_product" required>${options()}</select></label><label>Lote<input name="p_lot" required maxlength="120"></label><label>Validade<input name="p_expiry" type="date" required></label><label>Quantidade<input name="p_quantity" type="number" min="1" step="1" required></label><button class="btn">Registar entrada</button></form>`:''}
  ${['consume','replenish'].filter(can).map(kind=>`<h3>${kind==='consume'?'Consumo do Posto Médico':'Reposição: Armazém de Saúde → Posto Médico'}</h3><form data-operation="move"><input name="p_kind" type="hidden" value="${kind}"><label>Produto e lote<select name="p_batch" required>${batchOptions}</select></label><label>Quantidade<input name="p_quantity" type="number" min="1" step="1" required></label><button class="btn">Registar ${labels[kind].toLowerCase()}</button></form>`).join('')}
  ${can('reports')?`<h3>Relatórios CSV</h3><p>Incluem identificador do movimento, autor e data UTC. Inventário inclui lotes expirados.</p>${['inventory','receive','replenish','consume'].map(k=>`<button type="button" class="btn" data-report="${k}">${k==='inventory'?'Inventário':labels[k]}</button>`).join('')}`:''}
  ${s.role==='developer'?`<h3>Administração GESTOCK · Developer</h3><p>As permissões do catálogo herdado permanecem na administração original. O Developer é provisionado exclusivamente no servidor.</p><form data-operation="set_role"><label>UUID da conta existente<input name="p_user" required pattern="[0-9a-fA-F-]{36}"></label><label>Papel<select name="p_role"><option value="admin">Admin</option><option value="moderator">Moderador</option><option value="user">Utilizador</option></select></label><button class="btn">Atribuir papel</button></form><div class="stock-scroll"><table><thead><tr><th>Permissão</th><th>Admin</th><th>Moderador</th><th>Utilizador</th></tr></thead><tbody>${['read','receive','consume','replenish','products','targets','reports'].map(a=>`<tr><td>${esc(a)}</td>${['admin','moderator','user'].map(r=>`<td><input type="checkbox" aria-label="${r} ${a}" data-permission="${a}" data-role="${r}" ${s.matrix.some(p=>p.role===r&&p.action===a)?'checked':''} ${r==='user'&&['receive','replenish'].includes(a)?'disabled':''}></td>`).join('')}</tr>`).join('')}</tbody></table></div>`:''}`;
  el('stockSearch').addEventListener('input',e=>{for(const row of el('stockRows').rows)row.hidden=!row.textContent.toLocaleLowerCase('pt').includes(e.target.value.toLocaleLowerCase('pt'));});
 }
 async function load() {
  const ticket=++generation, user=session?.user.id;
  el('stockStatus').textContent='A carregar…';el('stockContent').replaceChildren();snapshot=null;
  try { const data=await rpc('snapshot');if(ticket!==generation||session?.user.id!==user)return;snapshot=data;account=user;render(); }
  catch(e){if(ticket===generation)el('stockStatus').textContent=e.message;}
 }
 function exportReport(kind) {
  if(!can('reports'))return;
  const s=snapshot, p=id=>s.products.find(x=>x.id===id)||{}, b=id=>s.batches.find(x=>x.id===id)||{};
  let rows;
  if(kind==='inventory')rows=[['produto','marca','lote','validade','armazem_saude','posto_medico','obrigatorio_produto'],...s.batches.map(x=>[p(x.product_id).name,p(x.product_id).brand,x.lot,x.expiry,x.central,x.medical,p(x.product_id).target])];
  else rows=[['movimento','data_utc','autor_uuid','produto','marca','lote','validade','quantidade'],...s.movements.filter(m=>m.kind===kind).map(m=>{const batch=b(m.batch_id),prod=p(batch.product_id);return[m.id,m.created_at,m.actor,prod.name,prod.brand,batch.lot,batch.expiry,m.quantity];})];
  const csv=rows.map(row=>row.map(v=>'"'+String(v??'').replace(/^[=+@-]/,"'$&").replace(/"/g,'""')+'"').join(';')).join('\r\n');
  const url=URL.createObjectURL(new Blob(['\ufeff',csv],{type:'text/csv;charset=utf-8'}));const a=document.createElement('a');a.href=url;a.download=`GESTOCK-${kind}-${new Date().toISOString().slice(0,10)}.csv`;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
 }
 el('openStock').addEventListener('click',()=>{el('stockDialog').showModal();load();});
 el('closeStock').addEventListener('click',()=>el('stockDialog').close());
 el('stockDialog').addEventListener('close',()=>{generation++;snapshot=null;el('stockContent').replaceChildren();});
 el('stockContent').addEventListener('click',e=>{if(e.target.closest('[data-refresh]')&&!busy)load();const button=e.target.closest('[data-report]');if(button)exportReport(button.dataset.report);});
 async function mutate(operation,args) {
  if(busy)return;busy=true;const ticket=generation,user=session?.user.id;
  for(const node of el('stockContent').querySelectorAll('button,input,select'))node.disabled=true;
  try { await rpc(operation,args);if(ticket===generation&&session?.user.id===user)await load(); }
  catch(e) { if(ticket===generation){el('stockStatus').textContent=e.message;for(const node of el('stockContent').querySelectorAll('button,input,select'))node.disabled=false;} }
  finally {busy=false;}
 }
 el('stockContent').addEventListener('submit',e=>{e.preventDefault();const form=e.target,args=Object.fromEntries(new FormData(form));for(const k of ['p_quantity','p_target'])if(k in args)args[k]=Number(args[k]);mutate(form.dataset.operation,args);});
 el('stockContent').addEventListener('change',e=>{if(e.target.dataset.permission)mutate('set_permission',{p_role:e.target.dataset.role,p_action:e.target.dataset.permission,p_enabled:e.target.checked});});
 setInterval(()=>{if(el('stockDialog').open&&account&&session?.user.id!==account){generation++;snapshot=null;account=null;el('stockContent').replaceChildren();el('stockStatus').textContent='Sessão terminada. Abre novamente após iniciar sessão.';}},500);
})();