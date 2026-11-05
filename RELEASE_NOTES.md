# Gestock 1.0.2

Corrigido erro pós-login «ensureGESTOCKAccess is not defined»: a sincronização chama a função de controlo de acesso herdada existente. Mantida a verificação de contas bloqueadas.
Nome apresentado da aplicação alterado para Gestock, incluindo janela e instalador. Identificadores técnicos e nomes dos artefactos de distribuição mantidos por compatibilidade.
Adicionado teste de regressão de carregamento após autenticação e de bloqueio antes de consultar o catálogo. Todos os testes locais passaram. Instalador de testes sem assinatura digital; login real deve ser validado pelo utilizador.