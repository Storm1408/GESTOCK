# GESTOCK 1.0.1 — testes com Supabase

Ligação ao projeto Supabase GESTOCK, serviço de login por username, proprietário Developer nos stocks e Admin no catálogo herdado. Feed configurado para Storm1408/GESTOCK; uma atualização só fica disponível após publicação de release com instalador, blockmap e latest.yml.

Testes locais completos passaram. Verificação remota confirmou permissões do proprietário, rejeição de credenciais inválidas e bloqueio de acesso anónimo aos stocks. Login real deve ser testado pelo proprietário com a sua password. Sem assinatura digital; arquitetura mobile e unificação de acessos ainda pendentes. Não usar em produção.