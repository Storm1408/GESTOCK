# GESTOCK 1.0.1

Aplicação Windows de gestão de stocks do Posto Médico e Armazém de Saúde, adaptada do SpawnVault 2.4.1. Versão de testes, sem assinatura digital.

Inclui produtos/marcas, lotes/validades, metas de stock, entradas, consumos, reposições, relatórios CSV e permissões de stocks geridas pelo Developer. Catálogo e funcionalidades herdadas preservados.

A configuração específica do Supabase e o registo do servidor permanecem locais. O app-config.js deste repositório é um modelo vazio: preencher localmente apenas URL e chave pública antes de compilar; nunca incluir service_role ou outros segredos.

Desenvolvimento: Node.js 24, npm ci, npm run check, npm test, npm start. Build: npm run dist -- --publish never. Só uma release com instalador, blockmap e latest.yml disponibiliza atualizações; um commit não publica uma versão.

Limites: papéis de stocks e catálogo ainda separados, sem pacotes iOS/Android, sem revisão completa de produção ou atualização das dependências herdadas. Os scripts de setup são de instalação inicial e não devem ser repetidos num servidor já configurado. A documentação de validação incluída é histórica; a configuração e os testes específicos do servidor estão registados localmente.
