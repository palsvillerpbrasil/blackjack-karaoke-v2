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
- `ADMIN_SESSION_SECRET` = segredo aleatório longo (pelo menos 32 caracteres; recomendado 64+).
- `ADMIN_SETUP_KEY` = outra chave aleatória, diferente do segredo de sessão.
- `PUBLIC_APP_URL` = `https://blackjack-karaoke-v2.netlify.app`

As duas variáveis Supabase já haviam sido cadastradas anteriormente, mas confirme os valores e o escopo Functions. Não cole a service role em conversas ou arquivos públicos.

Para gerar segredos localmente no Windows PowerShell:

```powershell
node -e "console.log(require('node:crypto').randomBytes(48).toString('base64url'))"
```

Gere dois valores diferentes e use um em cada variável. Guarde `ADMIN_SETUP_KEY` até concluir o primeiro acesso. Depois de criar o primeiro administrador, você pode remover `ADMIN_SETUP_KEY` das variáveis da Netlify.

## 2. Aplicar a migração no Supabase
O `schema.sql` anterior já foi executado. Agora abra Supabase → SQL Editor → New query e execute o conteúdo integral de:

`supabase/migrations/20261121_complete_system.sql`

A migração é incremental e não apaga as tabelas nem os registros existentes. Ela acrescenta colunas, índices, estado de fila e funções transacionais. Não execute comandos DROP ou TRUNCATE.

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
7. Após o primeiro administrador ser criado, remova `ADMIN_SETUP_KEY` da Netlify para desativar o bootstrap.

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
10. No painel, gerencie fila, edição, início, conclusão e cancelamento.
11. Inicie o sorteio informando quantos vencedores deseja. O telão mostra a animação e revela nome, música e mesa, sem exibir comanda.
12. Encerre a noite. Para outra noite, crie um novo evento; as comandas e os cadastros pertencem ao evento anterior e não são reutilizados.

## Regras implementadas
- O bloqueio de segunda inscrição é por comanda e por evento.
- Comandas são vinculadas ao evento e não à pessoa para sempre.
- O número da comanda aparece apenas nas telas administrativas e no campo digitado pelo próprio cliente; não é retornado no estado público nem no telão.
- O painel tem dois perfis de acesso total e um colaborador limitado às comandas.
- A fila automática roda por mesa, seguindo a mesa posterior à última que cantou; dentro de cada mesa, prioriza menor histórico médio de músicas dos integrantes e depois horário de reserva.
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
