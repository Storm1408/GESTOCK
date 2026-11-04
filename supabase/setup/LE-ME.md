# Configuração inicial Supabase GESTOCK

Estado: apenas ficheiros preparados. Nenhum projeto remoto criado nem SQL aplicado.

1. Ligar a integração Supabase à conta do proprietário e selecionar/criar projeto dedicado GESTOCK. Não usar o projeto SpawnVault. Confirmar organização e custos antes de criação, caso aplicável.
2. No projeto vazio, aplicar 01-base-projeto-novo.sql. O ficheiro agrega as migrações herdadas até v24. Se falhar, parar: contém transações por migração e pode já ter aplicado etapas anteriores. Não repetir automaticamente o pacote.
3. Criar uma única conta em Authentication através do Dashboard/Admin Auth, com email real do proprietário e password definida em privado. Confirmar o email para permitir testes. Ainda não há trigger v241 a bloquear a primeira conta. Desativar inscrições públicas no projeto.
4. Aplicar 02-contas-e-stocks.sql. A migração v241 cria o username da conta existente e ativa o bloqueio a novas contas fora do serviço administrativo.
5. Aplicar 03-proprietario.sql apenas após confirmar que a única conta existente é a do proprietário. Atribui Developer de stocks e Admin do catálogo herdado à mesma identidade. Consultar o username devolvido; pode ser alterado posteriormente.
6. Publicar a função spawnvault-accounts, preservando o nome usado pelo cliente. A implementação está em supabase/functions/spawnvault-accounts/index.ts e _shared/accounts.mjs. verify_jwt=false permite login público; o handler valida JWT/admin nas operações de criação. Segredos Supabase permanecem no servidor.
7. Configurar app-config.js apenas com URL e chave pública/publishable do projeto. Nunca colocar service_role, secret key, password de base de dados ou access token no cliente.
8. Testar autenticação, Developer, criação de utilizador, permissões, entrada, reposição, consumo e relatórios. Validar acesso anónimo recusado e bloqueios. Recompilar o instalador para incluir a configuração nova.

O Developer de stocks ainda não substitui todos os mecanismos administrativos herdados. Não distribuir em produção antes da revisão e unificação descritas em GESTOCK.md. Nenhum material nem utilizador de demonstração é criado pelos scripts.