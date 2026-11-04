# Validação realizada em 04/11/2026

- Extraído o ZIP SpawnVault-Source-2.4.1.zip; código preservado em módulos herdados, com alterações de identidade/configuração.
- Sintaxe JavaScript validada via node:vm do runtime da ferramenta: main.js, preload.js, renderer.js, branding.js, access.js, updates.js, stock.js e app-config.js.
- scripts/check-source.cjs passou: versões package/lock, nomes de IDs, sintaxe e consistência da configuração de atualizações.
- tests-updates.cjs passou com exitCode 0: agendamento, adiamento, instalação, rede, concorrência e configuração ausente.
- tests-moderation.cjs e tests-accounts.cjs não executados: falta @electric-sql/pglite (npm ci não disponível neste terminal).
- tests-accounts-server.cjs não concluído no ambiente alternativo de VM: importações e comparação de objetos entre contextos impedem usar esse resultado como validação. Reexecutar com Node.js normal.
- Adicionado tests-gestock.cjs com verificações SQL de proprietário único, autorização, saldos, rollback por stock insuficiente, RLS, bloqueios e relatórios. Ainda não executado, pois depende de PGlite.
- Sem validação visual, teste de ponta a ponta, servidor remoto, compilação Electron, instalação Windows, pacotes mobile ou deploy.

Para completar: instalar Node.js 24, executar npm ci, npm run check, npm test e testar npm start com um projeto Supabase de ensaio. Rever GESTOCK.md antes de publicar.
## Executável de testes — 04/11/2026

Node.js 24.22.2 descarregado da origem oficial com SHA256 verificado, guardado em .tools (sem instalação global). npm ci concluído. npm run check e npm test passaram, incluindo testes-gestock.cjs (SQL via PGlite), moderação, contas e atualizações.
Instalador NSIS x64 gerado: dist/GESTOCK-Setup-1.0.0.exe. verify-release passou (checksum SHA512, versão e blockmap). Compilado sem publicação, com win.signAndEditExecutable=false por falha de privilégios de links simbólicos na ferramenta de metadados. Sem assinatura digital; ícone/metadados internos podem continuar os do Electron.
Smoke test Electron: título GESTOCK, diálogo de stocks abre e apresenta ausência de sessão/configuração. Exit code 0. Não equivale a teste completo do instalador ou a ligação cloud. Não foi instalado nem lançado servidor.
O npm audit reportou 18 vulnerabilidades nas dependências herdadas (4 moderadas, 13 altas, 1 crítica). A atualização de dependências e Electron fica pendente antes de distribuição de produção.
