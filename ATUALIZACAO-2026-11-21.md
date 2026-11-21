# Atualização BLACK JACK KARAOKÊ — 21/11/2026

## O que mudou

1. **Identificação por comanda:** o nome fica salvo uma vez por evento e vale para qualquer mesa/QR Code. Ao voltar, o cliente informa a comanda e o nome é recuperado como somente leitura.
2. **Retorno após cantar:** o navegador lembra a última comanda usada naquele QR Code. A página consulta a situação novamente e libera o formulário de nova música assim que a apresentação anterior for cantada ou cancelada.
3. **Correção administrativa:** perfis OWNER/ADMIN podem corrigir o nome e/ou trocar a comanda na área Comandas. A correção é transacional e atualiza os dados históricos ligados àquela comanda. A nova comanda precisa estar liberada.
4. **Fila híbrida:** o rodízio automático continua ativo para as inscrições restantes. Arrastar ou mudar a posição fixa apenas a música escolhida. O comando de automático não apaga os ajustes manuais; cada ajuste pode ser devolvido ao automático individualmente.
5. **Histórico:** a tela mostra somente músicas cantadas, com participantes, mesa, comanda, música e horário `sung_at`.
6. **Logo:** o arquivo original foi mantido, removendo apenas o fundo quadrado externo e deixando transparência ao redor do círculo.

## Atualização de uma instalação existente

1. Faça um backup do Supabase antes de qualquer alteração.
2. No SQL Editor do Supabase, execute integralmente `supabase/migrations/20261121_queue_tabs_history.sql`.
3. Publique os arquivos deste projeto na mesma aplicação/site Netlify que já está em uso. Mantenha as variáveis de ambiente existentes (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `ADMIN_SESSION_SECRET`, `ADMIN_SETUP_KEY` e `PUBLIC_APP_URL`). Não substitua segredos por valores do `.env.example`.
4. Não é necessário recriar mesas ou QR tokens. Os dados atuais permanecem no banco.
5. Faça os testes abaixo antes de usar em uma noite com clientes.

## Testes recomendados

- Identifique a comanda em um QR Code e confira que o nome fica bloqueado.
- Abra outro QR Code/mesa, informe a mesma comanda e confira que o mesmo nome é recuperado.
- Envie uma música, marque-a como cantada no painel e confira que a página do cliente libera outra música ao atualizar (ou após a atualização automática).
- Entre como OWNER/ADMIN e edite nome/comanda. Confirme que o perfil COLLABORATOR não apresenta a ação de edição.
- Mova uma música na fila e confira que apenas ela recebe prioridade manual, enquanto as demais continuam no rodízio automático.
- Clique em “Manter rodízio automático” e confira que as prioridades manuais continuam preservadas. Use “Automático” em uma música para remover somente aquela prioridade.
- Confira se o histórico contém apenas apresentações cantadas e mostra o horário em que foram marcadas como cantadas.
- Confira o logo no site, painel, telão e impressão do QR Code.

**Importante:** a validação de build e sintaxe JavaScript foi feita neste pacote. A migração SQL e o funcionamento integrado com o Supabase/Netlify precisam ser executados e conferidos no ambiente da aplicação; nenhum banco remoto foi alterado durante a preparação deste ZIP.
