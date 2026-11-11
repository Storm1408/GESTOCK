(() => {
  let checkedUser, checkGeneration = 0;
  const dialog = document.getElementById('stockAlertsDialog');
  document.getElementById('closeStockAlerts').addEventListener('click', () => dialog.close());

  function addTable(title, headers, rows) {
    if (!rows.length) return;
    const heading = document.createElement('h3');
    heading.textContent = title;
    const wrapper = document.createElement('div');
    wrapper.className = 'stock-scroll';
    const table = document.createElement('table');
    const header = table.createTHead().insertRow();
    for (const label of headers) {
      const th = document.createElement('th');
      th.scope = 'col';
      th.textContent = label;
      header.append(th);
    }
    const body = table.createTBody();
    for (const values of rows) {
      const row = body.insertRow();
      for (const value of values) row.insertCell().textContent = value;
    }
    wrapper.append(table);
    document.getElementById('stockAlertsContent').append(heading, wrapper);
  }

  window.addEventListener('gestock:session', async () => {
    const id = session?.user.id;
    if (!id || document.getElementById('appShell').hidden) {
      checkedUser = undefined;
      checkGeneration++;
      if (dialog.open) dialog.close();
      return;
    }
    if (id === checkedUser || !['developer', 'admin', 'moderator'].includes(role) || !canPermission('read')) return;
    checkedUser = id;
    const ticket = ++checkGeneration;
    try {
      const { data, error } = await client.rpc('gestock_alerts');
      if (ticket !== checkGeneration || id !== session?.user.id ||
          !['developer', 'admin', 'moderator'].includes(role) || !canPermission('read')) return;
      if (error) throw new Error(error.message);
      if (!data.expiries.length && !data.minimums.length) return;
      document.getElementById('stockAlertsContent').replaceChildren();
      const format = value => BigInt(value).toLocaleString('pt-PT');
      addTable('Lotes vencidos ou a vencer nos próximos 30 dias',
        ['Material', 'Marca', 'Lote', 'Validade', 'Armazém', 'Posto Médico'],
        data.expiries.map(lot => [lot.name, lot.brand, lot.lot, lot.expiry.split('-').reverse().join('/'),
          format(lot.central), format(lot.medical)]));
      addTable('Materiais perto ou abaixo do mínimo no Armazém de Saúde',
        ['Material', 'Marca', 'Disponível', 'Mínimo'],
        data.minimums.map(item => [item.name, item.brand, format(item.available), format(item.minimum)]));
      if (!dialog.open) dialog.showModal();
    } catch {
      if (ticket === checkGeneration && session?.user.id === id) notify('Não foi possível consultar os alertas de stock.');
    }
  });
})();
