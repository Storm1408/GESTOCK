// Configure the packaged public client from CI variables; never use a server key.
const fs=require('node:fs'),path=require('node:path');
const url=process.env.GESTOCK_SUPABASE_URL?.trim(),key=process.env.GESTOCK_SUPABASE_PUBLISHABLE_KEY?.trim();
try{
 if(!url||!key)throw Error('Configura GESTOCK_SUPABASE_URL e GESTOCK_SUPABASE_PUBLISHABLE_KEY nas variables/secrets do GitHub antes de publicar.');
 const parsed=new URL(url);if(parsed.protocol!=='https:'||!parsed.hostname.endsWith('.supabase.co')||parsed.username||parsed.password||parsed.search||parsed.hash)throw Error('URL público do Supabase inválido.');
 let allowed=key.startsWith('sb_publishable_');if(!allowed&&key.split('.').length===3){try{allowed=JSON.parse(Buffer.from(key.split('.')[1],'base64url')).role==='anon'}catch{}}
 if(!allowed)throw Error('A distribuição só aceita uma chave publishable ou anon. Chaves de servidor são recusadas.');
 fs.writeFileSync(path.join(__dirname,'..','app-config.js'),'// Public client configuration. Never a service-role key.\nwindow.GESTOCK_CONFIG = '+JSON.stringify({supabaseUrl:parsed.origin,supabaseKey:key})+';\n');
 console.log('Configuração pública do cliente preparada para a distribuição.');
}catch(e){console.error(e.message);process.exitCode=1;}
