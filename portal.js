// Navigation and login feedback. No access is granted by UI state.
(() => {
 const $=id=>document.getElementById(id),sidebar=document.querySelector('.sidebar');
 function button(id,text){const b=document.createElement('button');b.type='button';b.id=id;b.className='nav-item';b.textContent=text;return b;}
 const medical=button('openMedical','🏥 Posto Médico'),warehouse=button('openWarehouse','📦 Armazém de Saúde'),reports=button('openReports','📋 Relatórios'),movements=button('openMovements','↔ Movimentos');
 const heading=(id,text)=>{const d=document.createElement('div');d.className='side-label';d.id=id;d.textContent=text;return d;};
 const brand=sidebar.querySelector('.brand'),bottom=sidebar.querySelector('.sidebar-bottom');
 const library=heading('libraryLabel','Biblioteca'),moderation=heading('moderationLabel','Moderação'),admin=heading('administrationLabel','Administração');
 sidebar.querySelectorAll('.side-label').forEach(n=>n.remove());$('categoryList').hidden=true;
 $('openStock').textContent='⚙ Gestão de stocks';
 sidebar.append(brand,library,$('navDashboard'),$('navAll'),$('navFavorites'),medical,reports,movements,moderation,warehouse,$('navRequests'),admin,$('manageUsersBtn'),$('openStock'),$('navTrash'),$('checkUpdatesBtn'),bottom,$('signOutBtn'));
 $('signOutBtn').classList.add('logout-button');
 const footer=document.querySelector('main>footer');footer.textContent='Developer: HVVLF | Todos os direitos reservados aos Bombeiros Voluntários de Montijo ©';footer.className='developer-footer';
 const credit=document.createElement('div');credit.className='login-credit';credit.textContent=footer.textContent;document.querySelector('.auth-stage').append(credit);
 const dashboard=$('dashboardPanel');dashboard.innerHTML='<h3>O que pretendes fazer?</h3><div id="dashboardActions" class="dashboard-actions"></div><div id="dashboardGrid" hidden></div><div id="dashboardRecent" hidden></div>';
 function sync(){
  const active=Boolean(session),manager=active&&['developer','admin'].includes(role),moderator=active&&['developer','admin','moderator'].includes(role);
  medical.hidden=!active;warehouse.hidden=!moderator;reports.hidden=!moderator;movements.hidden=!moderator;$('openStock').hidden=!manager;
  moderation.hidden=!moderator;admin.hidden=!manager;const roleText=$('userText');if(active)roleText.textContent=(sessionUsername||session.user.email?.split('@')[0]||'')+' · '+roleName(role);
  if(active)$('connectionText').textContent='Ligado à nuvem';
  $('dashboardActions').replaceChildren();
  for(const nav of sidebar.querySelectorAll('button.nav-item')){if(nav.id==='signOutBtn'||nav.hidden||nav.closest('[hidden]'))continue;const tile=document.createElement('button');tile.type='button';tile.className='dashboard-action';tile.textContent=nav.textContent.trim();tile.addEventListener('click',()=>nav.click());$('dashboardActions').append(tile);}
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
