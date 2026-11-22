# BLACK JACK KARAOKÊ — Correção de erros e consulta por comanda

## Arquivos deste patch
- `netlify/functions/api.mjs`: inclui os helpers `adminQueue()` e `dashboard()` usados pelas rotas de fila e eventos; acrescenta a contagem de apresentações cantadas por comanda no evento selecionado.
- `public/admin.html`: corrige a experiência de tela cheia para ocultar a marca e o nome superior, mantendo os controles de sair/tela cheia; acrescenta consulta de total de músicas por número de comanda no Histórico.

## Instalação
1. Faça backup da pasta atual do projeto.
2. Copie os dois arquivos mantendo os caminhos e substitua os arquivos correspondentes no repositório local.
3. Não substitua `.git`, `.env`, `public/telao.html`, assets ou arquivos SQL.
4. Não execute SQL: esta correção usa as tabelas e colunas já existentes.
5. Faça commit e push pelo GitHub Desktop e aguarde o deploy da Netlify.

## Verificações
- `adminQueue` e `dashboard` estão declaradas no escopo do módulo da Function.
- O contador usa `event_id`, `tab_number` e `status = SUNG`, portanto conta apresentações concluídas na noite selecionada.
- A tela cheia é aplicada ao `#app`, não ao documento inteiro; a faixa de marca fica fora do modo fullscreen e os controles permanecem disponíveis.
