# Gestock 1.1.0 — ativação concluída

Migração gestock_v110 aplicada ao projeto GESTOCK após autorização explícita do utilizador. Função spawnvault-accounts v2 publicada e ativa. Não foram introduzidas contas, veículos ou materiais fictícios no servidor.

Verificações remotas: identidade proprietária continua Developer; snapshot e dados de relatório acessíveis ao proprietário; acesso anónimo ao snapshot negado; edição direta de saldos negada; função interna de movimentos não exposta; perfil Utilizador sem lotes/quantidades, relatórios ou gestão de veículos. A verificação de username devolve true/false corretamente e o login rejeita credenciais inválidas. Login real com password é validado pelo utilizador.

Verificações locais: todos os testes passaram; nova saída com um veículo, carrinho atómico, limites de três dígitos, seleção explícita de sugestões, stock oculto por cargo, idempotência, veículos removidos preservando histórico, PDF sem coluna de checkboxes, navegação e cores. PDF de teste de 65 linhas com paginação e texto verificados.

Instalador Windows sem assinatura digital. A versão 1.0.3 foi preservada; instalar 1.1.0 para utilizar as novas funções. Novas saídas exigem um veículo ativo, a criar em Administração > Veículos.

Advisors: tabelas sem políticas de acesso direto são geridas por RPCs e grants restritos. Funções SECURITY DEFINER autenticadas fazem parte da API autorizada e devem continuar a ser revistas: https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable . O servidor também indica proteção contra passwords comprometidas desativada; rever disponibilidade/configuração antes de produção: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection . Não foi alterada essa definição.

Limites mantidos: ainda não existem clientes mobile nativos, assinatura de código nem uma revisão completa de produção. Esta versão não constitui garantia de disponibilidade 24/7 nem de segurança absoluta.
