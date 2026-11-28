# BLACK JACK KARAOKÊ — Atualização 2.4.0

## Fila e rodízio
- O botão **Próxima apresentação** agora encerra a música que está tocando como cantada e inicia automaticamente a próxima da fila.
- O histórico de músicas cantadas continua vinculado à comanda, não à mesa.
- A partir da quarta posição, a fila usa rodízio por mesa: cada mesa fornece no máximo uma música por rodada.
- Dentro de cada mesa, a comanda com menos músicas cantadas tem preferência.
- Se uma comanda enviar duas músicas antes de cantar a primeira, somente o primeiro pedido recebe prioridade de estreante; os seguintes entram na ordem normal projetada da mesma comanda.
- Em empate, a rotação começa pela mesa seguinte à última que cantou; no início, começa pela menor numeração de mesa.
- Pedidos aguardando há 45 minutos ou mais recebem prioridade de espera, com meta operacional de até 50 minutos.
- Ajustes manuais da fila continuam preservados.

## Telão
- No agradecimento, as datas do calendário são exibidas uma por vez, com cinco segundos de permanência para cada data.
- No sorteio, os vencedores são revelados um por vez, com intervalo de seis segundos; o nome revelado fica em destaque enquanto a animação continua entre as revelações.
- A tela mantém o sorteio ativo pelo tempo necessário para revelar todos os vencedores, mesmo quando há mais de três nomes.

## Histórico
- Cada cartão de comanda ganhou um botão para dar baixa no lançamento de todas as músicas cantadas daquela comanda.
- O cartão mostra se o lançamento está pendente, parcial ou concluído.
- É possível desfazer a baixa.
- A implementação reutiliza as colunas `external_registered_at` e `external_registered_by` já existentes na tabela `participants`.

## Banco de dados
Não há migração SQL nova nesta atualização. A baixa por comanda utiliza o controle de lançamento já instalado na versão anterior.

## Publicação
Substitua os arquivos do pacote, faça Commit e Push pelo GitHub Desktop e aguarde a publicação da Netlify.
