# BLACK JACK KARAOKÊ — Tela de agradecimento nos telões

## O que esta atualização faz
- Adiciona ao Dashboard administrativo o botão **Exibir agradecimento nos telões**.
- Ao ativar, todos os telões abertos em `/telao.html` mostram a mensagem: **“Obrigado por fazer parte de mais um karaokê.”**
- A tela apresenta até três próximas datas programadas no calendário, incluindo título, horário e apresentador.
- A programação é consultada pelo backend e os telões atualizam a tela em seu ciclo normal de 2 segundos.
- O mesmo botão passa a oferecer **Encerrar agradecimento e voltar ao telão**.
- Somente perfis OWNER e ADMIN podem ativar ou encerrar essa tela.

## Instalação
1. Substitua estes arquivos no projeto existente, mantendo os mesmos caminhos:
   - `netlify/functions/api.mjs`
   - `public/admin.html`
   - `public/telao.html`
2. Não substitua nem apague `.git`, `.env`, tokens de mesas ou outros arquivos de configuração.
3. Faça Commit e Push pela branch principal.
4. Aguarde o deploy da Netlify ficar como **Published**.
5. Atualize os telões com `Ctrl + F5` (ou recarregue a página nas TVs).
6. No Dashboard do administrador, use o novo botão para exibir a mensagem. Clique novamente para voltar à programação normal.

## Supabase
Não é necessária nova migração SQL. A funcionalidade utiliza a tabela `settings` já existente para guardar o estado global da tela.

## Comportamento
- São exibidas no máximo três datas futuras, a partir do dia seguinte, em ordem cronológica.
- Cada cartão mostra dia da semana, data, mês, título, horário e apresentador (quando cadastrado).
- Se não houver datas futuras, aparece uma mensagem informando que novas datas serão anunciadas.
- A tela de agradecimento tem prioridade visual sobre a programação, boas-vindas, sorteio e compartilhamento enquanto estiver ativa. Ao encerrá-la, a tela normal volta a aparecer.
