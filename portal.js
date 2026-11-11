// Navigation and login feedback. No access is granted by UI state.
(() => {
 const $=id=>document.getElementById(id),sidebar=document.querySelector('.sidebar');
 const paths={medical:'M12 4v16M4 12h16',warehouse:'M3 9l9-6 9 6v12H3V9zm5 12v-9h8v9',reports:'M8 3h8v3H8zM7 4H4v18h16V4h-3M8 11h8M8 16h8',movements:'M3 7h17l-4-4M21 17H4l4 4',stock:'M12 3v18M3 12h18M5 5l14 14M5 19L19 5',history:'M3 11a9 9 0 1 1 3 8M3 4v7h7M12 7v5l3 2',permissions:'M12 3l9 4v5c0 5-9 9-9 9s-9-4-9-9V7l9-4M9 12l2 2 4-4',receive:'M12 3v12m-5-5l5 5 5-5M4 16v5h16v-5',suppliers:'M3 21h18M5 21V5h14v16M9 9h1m4 0h1m-6 4h1m4 0h1m-4 8v-4h2v4',replenish:'M4 7h16l-4-4M20 17H4l4 4'};
 const icon=key=>'<span class="nav-icon" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="'+paths[key]+'"/></svg></span>';
 function button(id,text,key){const b=document.createElement('button');b.type='button';b.id=id;b.title=text;b.className='nav-item';b.innerHTML=icon(key)+'<span>'+text+'</span>';return b;}
 const medical=button('openMedical','Levantamento Material Posto Médico','medical'),warehouse=button('openWarehouse','Armazém de Saúde','warehouse'),reports=button('openReports','Relatórios','reports'),movements=button('openMovements','Movimentos','movements');
 const medicalStock=button('openMedicalStock','Stock do Posto Médico','stock'),suppliers=button('openSuppliers','Fornecedores','suppliers');
 const receive=button('openReceive','Entrada de material','receive'),replenish=button('openReplenish','Reposição do Posto Médico','replenish');
 const addMaterial=button('openAddMaterial','Adicionar material','medical');
 const history=button('openHistory','Histórico','history'),permissions=button('openPermissions','Gestor de permissões','permissions');
 const heading=(id,text)=>{const d=document.createElement('div');d.className='side-label';d.id=id;d.textContent=text;return d;};
 const brand=sidebar.querySelector('.brand'),bottom=sidebar.querySelector('.sidebar-bottom');
 const library=heading('libraryLabel','Biblioteca'),moderation=heading('moderationLabel','Moderação'),admin=heading('administrationLabel','Administração'),updates=heading('updatesLabel','Atualizações');
 sidebar.querySelectorAll('.side-label').forEach(n=>n.remove());$('categoryList').hidden=true;
 $('openStock').innerHTML=icon('stock')+'<span>Gestão de Material</span>';
 $('navFavorites').hidden=true;$('navAll').hidden=true;$('navRequests').hidden=true;
 sidebar.append(brand,library,$('navDashboard'),medical,history,reports,moderation,medicalStock,warehouse,receive,replenish,admin,$('manageUsersBtn'),$('openStock'),addMaterial,suppliers,movements,permissions,$('navTrash'),updates,$('checkUpdatesBtn'),bottom,$('signOutBtn'));
 $('signOutBtn').classList.add('logout-button');
 const footer=document.querySelector('main>footer');footer.textContent='Developer: HVVLF | Todos os direitos reservados aos Bombeiros Voluntários de Montijo ©';footer.className='developer-footer';
 const credit=document.createElement('div');credit.className='login-credit';credit.textContent=footer.textContent;document.querySelector('.auth-stage').append(credit);
 const dashboard=$('dashboardPanel');dashboard.innerHTML='<h3>O que pretendes fazer?</h3><div id="dashboardActions" class="dashboard-actions"></div><div id="dashboardGrid" hidden></div><div id="dashboardRecent" hidden></div>';
 function sync(){
  $('adminVehiclesTab').hidden=!canPermission('vehicles');$('adminUsersTab').hidden=!canPermission('users');$('adminLogsTab').hidden=!canPermission('users');$('newUserBtn').hidden=!canPermission('users');$('adminGroupsTab').hidden=!isAdmin();$('adminBlocksTab').hidden=!isAdmin();
  const active=Boolean(session),manager=active&&['developer','admin'].includes(role),moderator=active&&['developer','admin','moderator'].includes(role);
  addMaterial.hidden=!canPermission('products');history.hidden=!active;permissions.hidden=!isDeveloper();medical.hidden=!active;warehouse.hidden=!moderator;receive.hidden=!canPermission('receive');replenish.hidden=!moderator||!canPermission('replenish');reports.hidden=!canPermission('reports');movements.hidden=!manager||!canPermission('reports');medicalStock.hidden=!moderator||!canPermission('read');suppliers.hidden=!manager||!canPermission('stock');$('openStock').hidden=!canPermission('stock');$('navFavorites').hidden=true;$('navAll').hidden=true;$('navRequests').hidden=true;
  moderation.hidden=medicalStock.hidden&&warehouse.hidden&&receive.hidden&&replenish.hidden;admin.hidden=!manager&&!canPermission('stock')&&!canPermission('users');const roleText=$('userText');if(active)roleText.textContent=(sessionUsername||session.user.email?.split('@')[0]||'').toUpperCase()+' · '+roleName(role);
  if(active)$('connectionText').textContent='Ligado à nuvem';
  $('dashboardActions').replaceChildren();
  for(const nav of sidebar.querySelectorAll('button.nav-item')){const hidden=nav.closest('[hidden]');if(['signOutBtn','navDashboard','checkUpdatesBtn'].includes(nav.id)||nav.hidden||(hidden&&sidebar.contains(hidden)))continue;const tile=document.createElement('button');tile.type='button';tile.className='dashboard-action';tile.innerHTML=nav.innerHTML;tile.addEventListener('click',()=>nav.click());$('dashboardActions').append(tile);}
 }
 window.addEventListener('gestock:render',sync);sync();
 // Existing accounts can be checked by name only through the rate-limited Edge endpoint.
 let timer,ticket=0;const input=$('authUsername'),field=input.closest('.login-field');
 const hint=document.createElement('span');hint.className='sr-only';hint.id='usernameLookupStatus';hint.setAttribute('aria-live','polite');field.after(hint);input.setAttribute('aria-describedby',hint.id);
 input.addEventListener('input',()=>{clearTimeout(timer);const current=++ticket,name=input.value.trim();field.classList.remove('username-found','username-missing');hint.textContent='';if(!usernamePattern.test(name))return;
  timer=setTimeout(async()=>{try{const r=await accountService({action:'lookup',username:name});if(current!==ticket||input.value.trim()!==name)return;field.classList.add(r.exists?'username-found':'username-missing');hint.textContent=r.exists?'Utilizador encontrado.':'Utilizador não encontrado.';}catch{if(current===ticket)hint.textContent='Não foi possível verificar o utilizador.';}},450);
 });
 new MutationObserver(()=>{for(const node of $('userManagerList').querySelectorAll('[data-user-role]')){node.disabled=!isDeveloper()||node.dataset.userRole===session?.user.id;}}).observe($('userManagerList'),{childList:true,subtree:true});
})();

// Check permission changes in other sessions without requiring another login.
(()=>{let checking=false;async function refresh(){if(checking||!client||!session||document.hidden)return;checking=true;const id=session.user.id;try{const r=await client.rpc('gestock_access_status');if(r.error||session?.user.id!==id)return;if(r.data.password_required){await window.GestockPasswordGate.check();return;}const next=JSON.stringify([r.data.role,[...(r.data.permissions||[])].sort()]);const current=JSON.stringify([role,[...effectivePermissions].sort()]);if(next!==current){role=r.data.role;effectivePermissions=new Set(r.data.permissions||[]);render();await window.GestockInventory.refresh();}}finally{checking=false;}}setInterval(()=>refresh().catch(()=>{}),3000);window.addEventListener('focus',()=>refresh().catch(()=>{}));})();
