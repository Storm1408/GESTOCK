const { app, BrowserWindow, clipboard, ipcMain, shell, dialog, powerMonitor } = require('electron');
const path = require('node:path');
const { autoUpdater } = require('electron-updater');
const { createUpdateService } = require('./updates');
let installingUpdate = false;
if(process.platform==='win32')app.setAppUserModelId('pt.gestock.app');


function createWindow() {
  const win = new BrowserWindow({
    width: 1180, height: 780, minWidth: 900, minHeight: 620,
    backgroundColor: '#0d1210',
    title: 'Gestock',
    icon: path.join(__dirname, 'assets', 'gestock-icon-v1.ico'),
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  });
  if(process.platform==='win32')win.setAppDetails({appId:'pt.gestock.app',appIconPath:app.isPackaged?path.join(process.resourcesPath,'gestock-shell-icon-v2.ico'):path.join(__dirname,'assets','gestock-icon-v1.ico'),appIconIndex:0});
  win.loadFile('index.html');
  win.on('focus', () => updates.resume());
  let closeConfirmed = false;
  win.on('close', e => {
    if (installingUpdate || closeConfirmed || win.webContents.isDestroyed()) return;
    e.preventDefault();
    win.webContents.send('app:before-close');
    const fallback = setTimeout(() => { closeConfirmed = true; if (!win.isDestroyed()) win.close(); }, 2200);
    ipcMain.once('app:close-ready', event => { if(event.sender!==win.webContents)return; clearTimeout(fallback); closeConfirmed = true; if (!win.isDestroyed()) win.close(); });
  });
}
app.whenReady().then(() => {
  createWindow();
  updates.start();
  powerMonitor.on('resume', () => updates.resume());
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
});
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });

ipcMain.handle('clipboard:write', (_event, text) => {
  clipboard.writeText(String(text ?? ''));
  return true;
});
ipcMain.handle('external:open', (_event, url) => {
  if (typeof url === 'string' && /^https:\/\/[^ ]+$/i.test(url)) return shell.openExternal(url);
  throw new Error('URL inválido');
});
// Allow the renderer to sign out before the update closes application windows.
async function prepareForUpdateInstall() {
  installingUpdate = true;
  await Promise.all(BrowserWindow.getAllWindows().filter(win => !win.isDestroyed()).map(win => new Promise(resolve => {
    const finish = () => { clearTimeout(timer); ipcMain.removeListener('app:close-ready', ready); resolve(); };
    const ready = event => { if(event.sender === win.webContents) finish(); };
    const timer = setTimeout(finish,1800);
    ipcMain.on('app:close-ready',ready);
    win.webContents.send('app:before-close');
  })));
}
const updates = createUpdateService({
 app,autoUpdater,dialog,publish:require('./update-config.json'),
 beforeInstall:prepareForUpdateInstall,
 setProgress:value=>BrowserWindow.getAllWindows().forEach(win=>{if(!win.isDestroyed())win.setProgressBar(value);})
});
ipcMain.handle('app:version',()=>app.getVersion());
ipcMain.handle('updates:check',()=>updates.check({manual:true}));

// Reports are built from escaped structured data in the main process.
ipcMain.handle('reports:save',async(event,report)=>{
 const {fileURLToPath}=require('node:url');
 if(!event.senderFrame||!event.senderFrame.url.startsWith('file:')||path.resolve(fileURLToPath(event.senderFrame.url))!==path.resolve(__dirname,'index.html'))throw Error('Origem inválida.');
 const {buildReportHTML}=require('./reports');const fs=require('node:fs/promises');
 const logo='data:image/png;base64,'+(await fs.readFile(path.join(__dirname,'assets/identity/gestock-logo-refined-dark.png'))).toString('base64');
 const html=buildReportHTML(report,logo);
 const result=await dialog.showSaveDialog(BrowserWindow.fromWebContents(event.sender),{title:'Guardar relatório PDF',defaultPath:'Gestock-'+report.kind+'-'+new Date().toISOString().slice(0,10)+'.pdf',filters:[{name:'PDF',extensions:['pdf']}]});
 if(result.canceled||!result.filePath)return {cancelled:true};
 const output=new BrowserWindow({show:false,webPreferences:{sandbox:true,contextIsolation:true,nodeIntegration:false}});
 try{output.webContents.setWindowOpenHandler(()=>({action:'deny'}));await output.loadURL('data:text/html;charset=utf-8,'+encodeURIComponent(html));await output.webContents.executeJavaScript('Promise.all([...document.images].map(i=>i.decode().catch(()=>{})))');
 const pdf=await output.webContents.printToPDF({printBackground:true,preferCSSPageSize:true,displayHeaderFooter:true,headerTemplate:'<span></span>',footerTemplate:'<div style="font-size:8px;color:#65735b;width:100%;padding:0 45px;display:flex;justify-content:space-between"><span>Gestock | Todos os direitos reservados aos Bombeiros Voluntários de Montijo ©</span><span><span class="pageNumber"></span> / <span class="totalPages"></span></span></div>'});
 await fs.writeFile(result.filePath,pdf);return {cancelled:false};}finally{output.destroy();}
});
