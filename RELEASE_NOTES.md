## Gestock 1.3.1

O programa, o atalho, o nome no Windows e o instalador apresentam apenas Gestock. A versão instalada aparece discretamente no canto inferior direito, incluindo no ecrã de login e nos painéis. O nome do instalador passa a Gestock.exe; os metadados de versão e a atualização automática são mantidos.

## Gestock 1.3.0

Histórico pessoal de saídas, navegação reorganizada com secção Atualizações e gestor de permissões autónomo. Todos os itens e Pedidos de itens retirados do menu. Campos de entrada/reposição alinhados; quantidades indisponíveis assinaladas a vermelho por material. Correções administrativas de stock por lote nos dois locais, com motivo, auditoria e recusa de valores desatualizados. Migração gestock_v130 aplicada e verificada no Supabase.

## Gestock 1.2.0

Correções na gravação de veículos e imagens; criação administrativa de contas corrigida; alteração obrigatória da palavra-passe no primeiro acesso das novas contas (mínimo de 6 caracteres exigido pelo Supabase). Matriz de permissões de stock editável pelo Developer com validação no servidor. Entradas e reposições separadas; entradas sem limite de três dígitos. Movimentos auditados com utilizador, incluindo o histórico. Símbolos SVG, cores mais vivas, logout compacto, favoritos removidos da navegação, usernames em maiúsculas e slogan Gestão de armazenamentos. PDF com emissor/data/hora e rodapé Gestock/direitos reservados.

# Gestock 1.1.0

Saídas por veículo único com vários materiais e idempotência; gestão administrativa de veículos e mini imagens; sugestões com seleção obrigatória; quantidades de três dígitos; stocks ocultos para utilizadores; relatórios PDF sem coluna de checkboxes; dashboard e navegação por cargo; Developer exclusivo; CSV/criação exclusivos do Developer; permissões em Português; cores mais vivas, crédito e terminação de sessão revista.

Migração e função de contas ativadas no servidor autorizado. Os scripts de migração não devem ser reaplicados. O modelo público app-config.js permanece vazio; configurar localmente antes de compilar. Instalador de testes sem assinatura digital. Consultar VALIDATION-v110.md.
