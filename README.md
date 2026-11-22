# KARAOKÊ BLACK JACK — Netlify + Supabase

Aplicação para operação do karaokê com formulário por QR Code, painel administrativo, fila, comandas por evento, perfis por senha, sorteio ponderado e telão.

## Endereços
- Cliente: `/`
- Administração: `/admin.html`
- Telão: `/telao.html`
- API: `/api/`

## Infraestrutura existente
- Repositório: `https://github.com/palsvillerpbrasil/blackjack-karaoke-v2`
- Netlify: `https://blackjack-karaoke-v2.netlify.app/`
- Supabase: `https://supabase.com/dashboard/project/soycshrmzgtbodwxflds`
- Project URL: `https://soycshrmzgtbodwxflds.supabase.co`

## IMPORTANTE — antes de publicar
1. O projeto existente foi inspecionado e a base anterior tinha formulário público simplificado, `admin.html` provisório e API sem operações administrativas.
2. Este pacote substitui essa base pela implementação dos fluxos descritos neste README; a ativação depende da migração SQL, das variáveis da Netlify e da importação de dados.
3. A migração SQL incremental precisa ser executada no Supabase antes de usar a nova API.
4. O arquivo de logo original enviado foi localizado e incluído sem alterações em `public/assets/logo-original.png`. As três páginas utilizam esse mesmo arquivo e exibem KARAOKÊ acima de BLACK JACK.
5. A integração GitHub não autorizou gravação direta no repositório durante esta sessão (HTTP 403). Portanto, o ZIP precisa ser enviado ao repositório pelo proprietário ou por uma integração com permissão de escrita. Nenhuma publicação foi feita por este pacote.

## 1. Variáveis da Netlify
No projeto Netlify, em Site configuration / Environment variables, configure os escopos de Functions para:

- `SUPABASE_URL` = `https://soycshrmzgtbodwxflds.supabase.co`
- `SUPABASE_SERVICE_ROLE_KEY` = service_role key do projeto Supabase. Nunca coloque esta chave em HTML, JavaScript público ou GitHub.
- `SUPABASE_ANON_KEY` = chave anon/public do projeto Supabase, necessária para a transmissão de tela aos telões. Nunca use a service_role no navegador.
- `ADMIN_SESSION_SECRET` = segredo aleatório longo (pelo menos 32 caracteres; recomendado 64+).
- `ADMIN_SETUP_KEY` = outra chave aleatória, diferente do segredo de sessão.
- `PUBLIC_APP_URL` = `https://blackjack-karaoke-v2.netlify.app`

As variáveis do Supabase devem estar cadastradas no escopo Functions. Confirme os valores antes de publicar. Não cole a service role em conversas ou arquivos públicos.

Para gerar segredos localmente no Windows PowerShell:

```powershell
node -e "console.log(require('node:crypto').randomBytes(48).toString('base64url'))"
```

Gere dois valores diferentes e use um em cada variável. Guarde `ADMIN_SETUP_KEY` até concluir o primeiro acesso. Depois de criar o primeiro administrador, você pode remover `ADMIN_SETUP_KEY` das variáveis da Netlify.

## 2. Aplicar a migração no Supabase
O `schema.sql` anterior já foi executado. Agora abra Supabase → SQL Editor → New query e execute, nesta ordem, o conteúdo integral dos arquivos:

1. `supabase/migrations/20261121_complete_system.sql`
2. `supabase/migrations/20261121_queue_tabs_history.sql`
3. `supabase/migrations/20261121_collaborator_history_tracking.sql`
4. `supabase/migrations/20261121_calendar_presenter_welcome.sql`
5. `supabase/migrations/20261121_calendar_public_list_time.sql`
6. `supabase/migrations/20261122_screen_queue_history.sql`

As migrações são incrementais e não apagam as tabelas nem os registros existentes. Não execute comandos DROP ou TRUNCATE. Para um projeto Supabase totalmente novo, use `supabase/complete-install.sql`, que inclui o esquema e as migrações acima.

## 3. Publicar no Netlify
1. Extraia o ZIP.
2. Envie o conteúdo da pasta do projeto para a raiz do repositório existente `palsvillerpbrasil/blackjack-karaoke-v2`, substituindo os arquivos antigos correspondentes.
3. Preserve a estrutura de diretórios, especialmente `public/`, `netlify/` e `supabase/`.
4. Faça commit na branch principal `main`.
5. Aguarde a publicação automática no Netlify.
6. Abra `https://blackjack-karaoke-v2.netlify.app/api/` apenas por uma chamada POST `{"action":"health"}`. A função responde JSON; abrir em GET no navegador retorna 405, o que é esperado.

## 4. Primeiro acesso administrativo
1. Abra `https://blackjack-karaoke-v2.netlify.app/admin.html`.
2. No primeiro acesso, informe `ADMIN_SETUP_KEY` e crie uma senha com pelo menos 10 caracteres.
3. Esse primeiro perfil será Administrador 1 (acesso total).
4. Entre no painel → Administradores.
5. Crie o segundo perfil Administrador (acesso total) e o perfil Colaborador (somente comandas), cada um com senha diferente.
6. O login é exclusivamente por senha; não existe campo de usuário.
7. Os três perfis (dois administradores e um colaborador) podem manter sessões simultâneas em computadores diferentes. Cada perfil deve usar sua própria senha.
8. Após o primeiro administrador ser criado, remova `ADMIN_SETUP_KEY` da Netlify para desativar o bootstrap.

## 5. Operação da noite
1. Entre em Administração → Dashboard.
2. Inicie uma nova noite (ela nasce fechada).
3. Abra o evento.
4. Entre em Comandas e libere o intervalo usado naquela noite (ex.: 20 até 29).
5. Entre em Mesas, cadastre as mesas e gere/imprima um QR Code por mesa.
6. Fixe cada QR Code na mesa correspondente.
7. Abra `/telao.html` no computador conectado ao televisor.
8. Os clientes escaneiam o QR Code, informam comanda e nome no primeiro acesso e depois têm o nome recuperado automaticamente naquela noite.
9. Uma comanda só pode manter uma apresentação pendente. Ela é liberada quando a música é cantada ou cancelada.
10. No painel, gerencie fila, edição, início, conclusão e cancelamento. A fila preserva as três primeiras posições do rodízio; a partir da quarta, uma primeira música de comanda sem histórico passa à frente das músicas repetidas. Depois que cantar uma vez, a comanda segue o rodízio normal.
11. Na fila, use `Iniciar com telões` para escolher a tela/janela a compartilhar. O telão mantém uma faixa superior com a música atual e a próxima. Encerre a transmissão pelo botão do painel; se o navegador encerrar o compartilhamento, o telão retorna ao modo normal.
12. Use `Inserir música manual` para cadastrar uma apresentação extra. O sistema aumenta a capacidade da noite em uma unidade e mantém a música oculta do telão até ser iniciada.
13. A seção recolhível `Músicas já cantadas` permite devolver uma apresentação à fila, posicionada por padrão depois das três primeiras posições quando houver itens suficientes.
14. A página Comandas atualiza automaticamente a cada dois minutos. Após enviar uma música, o formulário do QR Code volta à identificação inicial para permitir o uso do mesmo celular por outra pessoa.
15. O histórico numera as músicas por pessoa/comanda em ordem cronológica. Marcar uma apresentação como lançada aplica a marcação aos registros anteriores daquela pessoa na mesma comanda e noite.
16. Inicie o sorteio informando quantos vencedores deseja. O telão mostra a animação e revela nome, música e mesa, sem exibir comanda.
17. Encerre a noite. Para outra noite, crie um novo evento; as comandas e os cadastros pertencem ao evento anterior e não são reutilizados.

## Regras implementadas
- O bloqueio de segunda inscrição é por comanda e por evento.
- Comandas são vinculadas ao evento e não à pessoa para sempre.
- O número da comanda aparece apenas nas telas administrativas e no campo digitado pelo próprio cliente; não é retornado no estado público nem no telão.
- O painel tem dois perfis de acesso total e um colaborador limitado às comandas.
- A fila automática mantém o rodízio por mesa, mas calcula o histórico de músicas por comanda, independentemente da mesa atual. A primeira música de uma comanda sem histórico recebe prioridade somente a partir da quarta posição, sem deslocar as três primeiras; depois que cantar uma vez, as próximas inscrições seguem o rodízio normal.
- A ordem manual persistida fica à frente de novas inscrições até o administrador restaurar o rodízio automático.
- Sorteio usa pessoas que cantaram, sem repetição no evento e com peso menor para mesas já sorteadas naquela rodada.
- QR Codes são gerados no backend com a dependência `qrcode`, sem serviço externo de QR.

## Limites e itens que exigem configuração do proprietário
- O logo original está incluído em `public/assets/logo-original.png` sem redesenho ou alteração.
- A integração GitHub recusou gravações diretas nesta sessão (HTTP 403). O pacote está pronto para upload pelo proprietário no repositório existente.
- A migração dos dados reais ainda precisa ser executada pelo script `scripts/import-legacy.mjs`, após aplicar a migração SQL e exportar a planilha para XLSX. A planilha foi acessada e os totais estão registrados abaixo.
- Netlify/Supabase podem ter limites de execução e uso no plano gratuito; a disponibilidade depende dos limites atuais das contas.

## Segurança
A chave service_role só é usada pela Netlify Function. O frontend nunca recebe a chave. As tabelas têm RLS habilitado e as funções SECURITY DEFINER da migração são restritas ao papel `service_role`. Senhas administrativas usam scrypt com salt aleatório; sessões são assinadas por HMAC e expiram em 8 horas.

## Migração da planilha original — estrutura conferida
A planilha `Karaokê` foi exportada e suas abas foram inspecionadas. O conteúdo encontrado foi:

| Aba | Registros de dados (sem cabeçalho) |
|---|---:|
| MESAS | 17 |
| APRESENTAÇÕES | 25 |
| PARTICIPANTES | 16 |
| EVENTOS | 5 |
| HISTÓRICO | 137 |

Nas apresentações antigas, 17 estavam como `CANTADA` e 8 como `NAO_CANTADA`. Duas apresentações antigas não tinham comanda; a migração permite `tab_number` nulo para preservar esses registros sem inventar números. A noite ativa encontrada foi **Melhores do Ano**, com capacidade atual **20**. As 17 mesas estavam ativas e tinham tokens de 32 caracteres válidos.

### Como importar sem publicar dados pessoais no GitHub
1. No Google Sheets, abra a planilha `Karaokê` e use Arquivo → Fazer download → Microsoft Excel (.xlsx).
2. Salve o arquivo localmente como `Karaokê.xlsx`, na pasta raiz extraída deste projeto. **Não envie esse arquivo ao GitHub**, pois contém nomes, histórico e um PIN legado.
3. Abra PowerShell nessa pasta e execute:

```powershell
npm install
$env:SUPABASE_URL="https://soycshrmzgtbodwxflds.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY="COLE_A_CHAVE_SERVICE_ROLE_LOCALMENTE"
node scripts/import-legacy.mjs ".\Karaokê.xlsx"
```

4. Confira o resumo de importação exibido no terminal.
5. O script mantém IDs e tokens das mesas, cria mapeamento UUID para os IDs textuais antigos de evento e importa apresentações, estatísticas e histórico. A importação é idempotente pelos identificadores legados.
6. O script **não migra** `CONFIGURAÇÕES.pin_admin` (o valor encontrado era um PIN numérico em texto puro), não importa a URL antiga e não libera intervalos de comandas automaticamente. Configure as comandas no painel e crie senhas administrativas novas.

A planilha original permanece intacta. O script não apaga abas nem altera a origem.

## Segurança de login
O login aceita somente a senha. O backend verifica o hash scrypt de cada perfil ativo, assina sessão HMAC com expiração de 8 horas e limita tentativas por IP: a partir de 8 falhas em uma janela de 15 minutos, o acesso fica bloqueado por 15 minutos. O hash do IP é armazenado, não o endereço bruto.

**QR Codes antigos:** os tokens das 17 mesas são preservados na importação, mas os QR Codes impressos anteriormente apontam para o domínio antigo `karaokeblackjack.netlify.app`. Como o novo sistema está em `blackjack-karaoke-v2.netlify.app`, gere e imprima novamente os QR Codes pelo painel para apontar ao novo endereço. O token de cada mesa permanece igual, salvo se você escolher regenerá-lo.


## Ajustes de fila, identificação e histórico (21/11/2026)

Para atualizar uma instalação existente, execute no SQL Editor do Supabase o arquivo `supabase/migrations/20261121_queue_tabs_history.sql` antes de publicar a nova versão do site.

- A comanda identifica a pessoa uma única vez por evento, independentemente da mesa/QR Code utilizado. O nome já cadastrado é carregado como somente leitura no acesso do cliente.
- O último número de comanda usado naquele QR Code é lembrado no navegador. Ao atualizar a página, a inscrição é consultada novamente e a tela libera uma nova música assim que a apresentação anterior estiver cantada ou cancelada.
- Somente perfis OWNER/ADMIN podem corrigir o nome ou trocar a comanda; a troca atualiza também as apresentações e estatísticas vinculadas. A nova comanda precisa estar liberada.
- A fila permanece automática por mesa. Uma alteração manual fixa somente a apresentação movida; as demais continuam no rodízio automático. O comando de automático não apaga prioridades manuais, e cada prioridade pode ser removida individualmente pelo botão `Automático`.
- O histórico lista apenas apresentações cantadas e usa `sung_at`, o horário em que a música foi marcada como cantada.
- O logo `public/assets/logo-original.png` mantém o desenho circular original, com transparência fora do círculo para remover o fundo quadrado.


## Calendário público e mensagem de boas-vindas do telão

Para habilitar a programação mensal, o nome do apresentador e a mensagem de boas-vindas antes da primeira música, execute no SQL Editor do Supabase a migração `supabase/migrations/20261121_calendar_presenter_welcome.sql`. A migração é incremental e não apaga dados existentes.

No painel administrativo, abra **Configurações > Calendário de Karaokê**. Selecione uma data, marque se haverá karaokê, informe o título e, opcionalmente, o nome do apresentador. Os clientes podem consultar a programação em `/calendario.html`.

Ao abrir o evento no painel, o telão mostra uma mensagem de boas-vindas usando o título e o apresentador programados para a data atual. A mensagem permanece até o início da primeira apresentação; depois disso, o telão volta ao quadro normal de músicas.


## Transmissão de tela para os telões
A transmissão usa `getDisplayMedia` no navegador do administrador e WebRTC com sinalização pelo Supabase Realtime. O administrador precisa autorizar o compartilhamento no Chrome/Edge e selecionar a tela ou janela. O áudio não é compartilhado. A chave pública `SUPABASE_ANON_KEY` é usada no navegador; `SUPABASE_SERVICE_ROLE_KEY` permanece somente no backend. O STUN público é a configuração desta versão. Se os telões estiverem em outra rede e a conexão direta falhar, será necessário integrar um servidor TURN com credenciais temporárias; não coloque credenciais TURN permanentes em variáveis públicas ou em repositórios.
