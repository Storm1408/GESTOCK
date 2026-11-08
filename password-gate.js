// Access stays blocked on the server until Auth confirms the new password.
(() => {
 const dialog=()=>document.getElementById('firstPasswordDialog');let saving=false;
 window.GestockPasswordGate={check:async()=>{
  const result=await client.rpc('gestock_access_status');if(result.error)throw result.error;
  if(typeof result.data?.password_required!=='boolean')throw Error('Ativa a atualização Gestock 1.2 no Supabase antes de usar esta versão.');
  if(!result.data?.password_required){if(dialog().open)dialog().close();return true;}
  document.getElementById('appShell').hidden=true;
  for(const d of document.querySelectorAll('dialog[open]'))if(d!==dialog())d.close();
  if(!dialog().open)dialog().showModal();return false;
 }};
 document.addEventListener('DOMContentLoaded',()=>{
  dialog().addEventListener('cancel',e=>e.preventDefault());
  document.getElementById('firstPasswordSignOut').addEventListener('click',async()=>{if(saving)return;dialog().close();await client.auth.signOut();await onSession(null);});
  document.getElementById('firstPasswordForm').addEventListener('submit',async e=>{
   e.preventDefault();if(saving)return;const f=e.target,message=document.getElementById('firstPasswordMessage');
   if(f.elements.password.value!==f.elements.confirmation.value){message.textContent='As palavras-passe não coincidem.';return;}
   saving=true;f.querySelectorAll('button').forEach(b=>b.disabled=true);message.textContent='A guardar…';
   try{await accountService({action:'change-password',password:f.elements.password.value});f.reset();message.textContent='';if(await window.GestockPasswordGate.check())await onSession(session);}
   catch(error){message.textContent=error.message;}finally{saving=false;f.querySelectorAll('button').forEach(b=>b.disabled=false);}
  });
 });
})();
