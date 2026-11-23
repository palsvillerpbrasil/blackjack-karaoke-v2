# BLACK JACK KARAOKÊ — Atualização 2.3.0

## Alterações
- Removido o compartilhamento de tela do administrador e o receptor WebRTC do telão.
- O telão volta a operar somente com a fila, a tela de boas-vindas, o agradecimento, a agenda e o sorteio já existentes.
- A fila automática deixa de usar o número da mesa como cursor ou agrupamento.
- A ordem normal usa a chegada da apresentação; a primeira música de uma comanda sem histórico recebe prioridade especial somente depois das três primeiras posições.
- Músicas seguintes da mesma comanda não recebem novamente a prioridade de primeira música.
- Ajustes manuais pontuais continuam preservados.
- O histórico passa a exibir cartões clicáveis das comandas que já cantaram, com o nome cadastrado e o total de músicas da noite selecionada.

## Banco de dados
Não há migração SQL nova. A tabela antiga `screen_sessions` é mantida sem uso para não apagar dados nem alterar a estrutura do banco.

## Publicação
Substitua os arquivos do projeto pelos arquivos deste pacote e publique pelo GitHub Desktop/Netlify.
