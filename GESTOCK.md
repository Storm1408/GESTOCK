# GESTOCK 1.0 — adaptação inicial, sem publicação

Base: SpawnVault-Source-2.4.1.zip. O catálogo, pedidos, favoritos, imagens, reciclagem, contas, bloqueios e controlador de atualizações foram mantidos. O novo botão Gestão de stocks abre um módulo adicional. O ícone original é temporário; não foi criado um logótipo novo.

## Implementado no código

Produtos por nome/marca, lotes/validades, quantidades por armazém, quantidade obrigatória por produto, entradas, consumos do Posto Médico e reposições do Armazém de Saúde. Movimentos e saldos são gravados numa transação SQL, com bloqueio do lote, validação de quantidades, validade e disponibilidade. Relatórios CSV de inventário, entradas, consumos e reposições, com autor UUID e data UTC.

Papéis GESTOCK: Developer único, Admin, Moderador, Utilizador. Apenas Developer pode atribuir os outros papéis e configurar a matriz. O Developer não é atribuível pelo cliente; a tabela singleton permite uma só conta. Os bloqueios herdados também impedem acesso aos stocks. Utilizador nunca pode receber ou repor o armazém central. Sem configuração, as operações online permanecem indisponíveis.

## Preparação de servidor (não executada)

Usar um projeto Supabase próprio do GESTOCK, sem apontar ao projeto SpawnVault de produção. Configurar app-config.js com URL e chave pública desse projeto. Nunca inserir service_role no cliente. Executar schema.sql e as migrações herdadas em ordem: migration_v2.sql, migration_v21.sql, migration_v22.sql, migration_v23_access.sql, migration_v23_block_reason.sql, migration_v24.sql, migration_v241.sql. Rever bootstrap e políticas herdadas antes de produção. Aplicar depois migration_gestock_v1.sql uma única vez. Nenhum destes passos foi executado remotamente.

A criação e login por username continuam a depender da função spawnvault-accounts e respetivas variáveis de servidor. O nome técnico foi preservado por compatibilidade. Criar a conta real do proprietário no Supabase Auth através de administração segura; depois inserir, no SQL Editor do servidor, o UUID real em gestock_owner (singleton=true, user_id=UUID_REAL). Não existe palavra-passe, email ou UUID de proprietário predefinido. A conta necessita também de configuração herdada de username para login.

Os papéis do catálogo herdado e os papéis de stocks estão separados nesta fase. Developer tem acesso integral ao módulo novo, mas ainda não substitui as verificações administrativas antigas. A unificação de TODOS os acessos, incluindo proteção do proprietário contra bloqueio/exclusão pela administração herdada, é trabalho pendente. Não distribuir como versão de produção antes dessa revisão. A migração não converte spawns em materiais nem modifica dados antigos.

## Windows, mobile e cloud

O código recebido é Electron Windows. Os formulários novos usam APIs web, permitindo evolução para cliente web responsivo/PWA em Windows/iOS/Android com o mesmo servidor. Não foram gerados pacotes iOS/Android nem implementados PWA/offline, notificações ou leitura de códigos de barras. A interface herdada ainda precisa de revisão mobile completa. Um serviço Supabase/cloud pode fornecer o backend partilhado; disponibilidade 24/7 depende do plano, monitorização, backups e configuração reais. Nada foi alojado ou publicado.

O controlador electron-updater e workflow GitHub foram preservados e renomeados. O feed antigo foi substituído por CONFIGURAR_OWNER/CONFIGURAR_REPO para impedir atualizações cruzadas. Configurar o repositório real com o script existente e rever workflow, scripts e artefactos antes de qualquer release. Configuração vazia desativa verificações automáticas. Não houve upload, release nem deploy.

## Validação e limites

Node.js/npm não encontrados no PATH deste computador. O instalador não foi compilado. Consultar VALIDATION.md para verificações efetivamente realizadas. SQL novo necessita de testes PostgreSQL/Supabase com concorrência, RLS, contas bloqueadas e permissões antes de produção. Ainda faltam testes de ponta a ponta e de interface.

Nesta fase relatórios usam o snapshot completo e não têm paginação/filtros de datas. Reposições são registadas por lote e podem exceder o objetivo definido; a necessidade apresentada é indicativa. Operações não têm chave de idempotência: em falha de rede após submissão, consultar o relatório antes de repetir. Alterações a metas e permissões ainda não têm auditoria própria. Expirados são visíveis no inventário, mas não podem ser consumidos/repostos; falta fluxo de quebra/descarte. Não há edição/eliminações de movimentos: as correções de stock exigem fluxo futuro auditável.