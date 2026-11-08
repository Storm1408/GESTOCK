# Publicar uma versão Gestock

As versões Windows procuram releases estáveis em Storm1408/GESTOCK ao arrancar, a cada quatro horas e no botão Verificar atualizações. A descarga e o reinício são confirmados pelo utilizador; não há instalação silenciosa.

O workflow .github/workflows/release.yml compila e testa a tag, prepara um rascunho, envia o instalador, o blockmap, latest.yml, o código-fonte e as migrações e só então publica como latest. Uma falha de upload deixa a release em rascunho. O instalador atual não tem assinatura digital.

Configurar nas Variables ou Secrets do repositório: GESTOCK_SUPABASE_URL e GESTOCK_SUPABASE_PUBLISHABLE_KEY. São a configuração do cliente público; nunca usar service_role, secret key ou palavra-passe. O código público app-config.js é um modelo vazio; a configuração é inserida apenas na compilação.

Para novas versões: atualizar package.json e package-lock.json, testar, atualizar as notas, sincronizar o código e criar a tag vX.Y.Z sobre esse commit. A tag tem de corresponder à versão exata do package.json. O workflow também admite execução manual com uma tag existente. Aplicar primeiro eventuais migrações do servidor que a nova versão exija.

O instalador tem sempre o nome Gestock.exe (e Gestock.exe.blockmap). A versão fica na tag, em latest.yml e no canto inferior direito da aplicação, sem integrar o nome do programa.
