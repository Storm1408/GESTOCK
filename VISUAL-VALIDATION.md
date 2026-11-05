# Gestock 1.0.3 — validação visual

Identidade aplicada: logótipo e fundo aprovados, cores verde/amarelo/grafite, ícone Windows, login, navegação e formulários de stocks. Referências de FiveM retiradas do cabeçalho/login. O catálogo herdado e os identificadores técnicos foram preservados.

Verificações: sintaxe e todos os testes npm passaram. Capturas Electron de login, stocks, matriz de permissões e janela reduzida foram inspecionadas com dados fictícios locais. Janela de stocks sem overflow horizontal a 1200 e 700 px; seis formulários presentes; checkboxes com 18 px. Sem autenticação de teste em contas reais, sem alterações de dados remotos.

Capturas locais em reports/identity-*.png (não versionadas). Ficheiros de estudo e referência rejeitada não são incluídos no instalador; apenas o logótipo limpo, fundo aprovado e ícones são empacotados. O ficheiro app-config.js com a configuração da instalação permanece local; o modelo público do repositório mantém-se vazio.

Instalador sem assinatura digital. Permanecem as limitações funcionais registadas nas versões anteriores, incluindo revisão de produção, papéis herdados e mobile.
