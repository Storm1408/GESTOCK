// Gestock identity and accessible interaction controls.
(() => {
  const brand = document.querySelector('.brand-icon');
  brand.textContent = '';
  brand.classList.add('gestock-symbol');
  brand.setAttribute('role','img');
  brand.setAttribute('aria-label','Símbolo Gestock');
  const toggle = document.getElementById('togglePassword');
  toggle.addEventListener('click', () => {
    const input = document.getElementById('authPassword');
    const visible = input.type === 'password';
    input.type = visible ? 'text' : 'password';
    toggle.setAttribute('aria-pressed',String(visible));
    toggle.setAttribute('aria-label',visible ? 'Ocultar palavra-passe' : 'Mostrar palavra-passe');
  });
  document.getElementById('authDialog').addEventListener('close', () => {
    document.getElementById('authPassword').type='password';
    toggle.setAttribute('aria-pressed','false');
    toggle.setAttribute('aria-label','Mostrar palavra-passe');
  });
  const adminTabs = [...document.querySelectorAll('.admin-tabs [role="tab"]')];
  function selectAdminTab(tab, focus = false) {
    adminTabs.forEach(item => {
      const active = item === tab;
      item.setAttribute('aria-selected', String(active));
      item.tabIndex = active ? 0 : -1;
      document.getElementById(item.getAttribute('aria-controls')).hidden = !active;
    });
    if (focus) tab.focus();
    tab.dispatchEvent(new CustomEvent('admin-tab-selected', {bubbles:true}));
  }
  adminTabs.forEach((tab, index) => {
    tab.addEventListener('click', () => selectAdminTab(tab));
    tab.addEventListener('keydown', event => {
      const next = {ArrowRight:(index+1)%adminTabs.length,ArrowLeft:(index+adminTabs.length-1)%adminTabs.length,Home:0,End:adminTabs.length-1}[event.key];
      if (next === undefined) return;
      event.preventDefault();
      selectAdminTab(adminTabs[next], true);
    });
  });
  document.getElementById('adminDialog').addEventListener('close', () => selectAdminTab(adminTabs[0]));
})();
