const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('spawnVault', {
 getVersion: () => ipcRenderer.invoke('app:version'),
 saveReport: report => ipcRenderer.invoke('reports:save', report),
 checkUpdates: () => ipcRenderer.invoke('updates:check'),
 copyText: text => ipcRenderer.invoke('clipboard:write', text),
 openExternal: url => ipcRenderer.invoke('external:open', url),
 onBeforeClose: callback => ipcRenderer.on('app:before-close', callback),
 closeReady: () => ipcRenderer.send('app:close-ready')
});
