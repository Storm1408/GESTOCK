# Gestock 1.4.2

- Logótipo da fénix e novos fundos em cinzento claro, vermelho e branco no ecrã de bloqueio e nas janelas da aplicação.
- Fénix com fundo transparente nos ícones do Windows e nos relatórios PDF.

# Gestock 1.4.1

- Fornecedores com dados de contacto e associação a materiais.
- Lista ordenada de reposição do Posto Médico, com quantidade exigida, contagem física e sugestão de reposição.
- Consulta separada do stock do Posto Médico para moderadores e administradores.
- Alertas no login para lotes vencidos ou com validade nos próximos 30 dias e para stock disponível no Armazém de Saúde até 10% acima do mínimo.
- Navegação atualizada, ícone do histórico em azul e recursos do logótipo para a pesquisa do Windows.

A versão usa a migração `20261111173508_gestock_v141.sql`.

## Gestock 1.4.0

Lotes agrupados por material e remoção de um lote apenas no local escolhido, com motivo e auditoria. No Posto Médico, acesso mínimo de Moderador; no Armazém de Saúde, Administrador. Lotes sem quantidade deixam automaticamente de aparecer no inventário ativo e nos relatórios de stock, preservando o histórico das operações. Histórico pessoal com uma linha por saída e botão de detalhes. Dashboard corrigida no primeiro login. Gestão de stocks renomeada para Gestão de Material, sem quantidades obrigatórias; opções individuais na barra lateral, com as permissões anteriores e eliminação de lotes configurável pelo Developer dentro dos cargos mínimos.

## Gestock 1.3.2

Correção da identidade e dos ícones Windows: o logótipo inclui as resoluções usadas pelo menu Iniciar, pesquisa e barra de tarefas. A aplicação declara o mesmo AppID do instalador e a atualização renova os ícones dos atalhos existentes. Mantém o nome Gestock, o instalador Gestock.exe e a versão no canto inferior direito.

## Gestock 1.3.1

O programa, o atalho, o nome no Windows e o instalador apresentam apenas Gestock. A versão instalada aparece discretamente no canto inferior direito, incluindo no ecrã de login e nos painéis. O nome do instalador passa a Gestock.exe; os metadados de versão e a atualização automática são mantidos.

## Gestock 1.3.0

Histórico pessoal de saídas, navegação reorganizada com secção Atualizações e gestor de permissões autónomo. Todos os itens e Pedidos de itens retirados do menu. Campos de entrada/reposição alinhados; quantidades indisponíveis assinaladas a vermelho por material. Correções administrativas de stock por lote nos dois locais, com motivo, auditoria e recusa de valores desatualizados. Migração gestock_v130 aplicada e verificada no Supabase.

## Gestock 1.2.0

Correções na gravação de veículos e imagens; criação administrativa de contas corrigida; alteração obrigatória da palavra-passe no primeiro acesso das novas contas (mínimo de 6 caracteres exigido pelo Supabase). Matriz de permissões de stock editável pelo Developer com validação no servidor. Entradas e reposições separadas; entradas sem limite de três dígitos. Movimentos auditados com utilizador, incluindo o histórico. Símbolos SVG, cores mais vivas, logout compacto, favoritos removidos da navegação, usernames em maiúsculas e slogan Gestão de armazenamentos. PDF com emissor/data/hora e rodapé Gestock/direitos reservados.

# Gestock 1.1.0

Saídas por veículo único com vários materiais e idempotência; gestão administrativa de veículos e mini imagens; sugestões com seleção obrigatória; quantidades de três dígitos; stocks ocultos para utilizadores; relatórios PDF sem coluna de checkboxes; dashboard e navegação por cargo; Developer exclusivo; CSV/criação exclusivos do Developer; permissões em Português; cores mais vivas, crédito e terminação de sessão revista.

Migração e função de contas ativadas no servidor autorizado. Os scripts de migração não devem ser reaplicados. O modelo público app-config.js permanece vazio; configurar localmente antes de compilar. Instalador de testes sem assinatura digital. Consultar VALIDATION-v110.md.
