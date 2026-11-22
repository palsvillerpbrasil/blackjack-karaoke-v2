# Manifesto de migração — conferência inicial

Planilha fonte: Karaokê (ID `13ZFnktB81V0aAONi5EhNY6KH2fGpFIqXBQfEmGS5C5I`)

Abas identificadas: PAINEL, CONFIGURAÇÕES, MESAS, APRESENTAÇÕES, PARTICIPANTES, EVENTOS, HISTÓRICO.

Contagens observadas na auditoria:
- Mesas: 17 registros
- Apresentações: 24 registros
- Participantes: 15 registros
- Eventos: 4 registros
- Histórico: 128 registros

Atenção: essas contagens são um retrato da leitura realizada e devem ser recalculadas imediatamente antes da migração definitiva. Os arquivos `legacy-current-netlify/` são cópias de referência do site enviado e não são a versão v2.


## Atualização funcional — 21/11/2026

Nova migração incremental: `supabase/migrations/20261121_queue_tabs_history.sql`.

- Preserva o rodízio automático e permite prioridades manuais pontuais na fila.
- Permite correção administrativa de nome/comanda com atualização transacional do histórico da pessoa.
- Mantém o histórico de apresentações cantadas usando o horário `sung_at`.
- Não apaga eventos, mesas, tokens, comandas, apresentações ou registros históricos existentes.


## Atualização funcional — Calendário, apresentador e boas-vindas

Nova migração incremental: `supabase/migrations/20261121_calendar_presenter_welcome.sql`.

- Adiciona calendário mensal com título da noite e nome do apresentador.
- Disponibiliza a programação em `public/calendario.html`, com visualização mensal e lista de próximos eventos.
- Adiciona a mensagem animada de boas-vindas ao telão quando o evento é aberto.
- A mensagem usa o título e o apresentador programados para a data atual e permanece até o início da primeira apresentação.
- Ao iniciar a primeira música, o telão retorna automaticamente ao painel normal.
- Migração incremental; não remove dados existentes.


## Atualização funcional — Lista pública de próximos karaokês

Nova migração incremental: `supabase/migrations/20261121_calendar_public_list_time.sql`.

- A página pública de programação passa a exibir somente uma lista das datas futuras com karaokê, sem calendário mensal.
- A tela inicial do QR Code mostra os próximos karaokês quando não há evento aberto ou quando a noite foi encerrada; ao abrir o evento, retorna ao formulário de identificação.
- Cada programação passa a ter horário de início configurável, com padrão de 19h para datas já cadastradas e novas datas.
- A lista apresenta dia da semana, data, horário, título e apresentador.
- A migração apenas adiciona a coluna `start_time`; não apaga nem altera datas, títulos ou apresentadores existentes.


## Atualização funcional — 22/11/2026

Nova migração incremental: `supabase/migrations/20261122_screen_queue_history.sql`.

- Adiciona controle de transmissão ativa por evento, sem expor a chave `service_role` no navegador.
- Permite inserir uma apresentação manual, aumenta a capacidade em uma unidade e mantém a apresentação oculta do telão até o início.
- Permite devolver uma apresentação cantada à fila, com posição inicial solicitada depois das três primeiras músicas.
- Atualiza a ação de início para revelar no telão apresentações manuais quando começarem.
- A fila passa a contar músicas por comanda, sem zerar o histórico quando a mesa muda.
- A primeira música da comanda recebe prioridade somente a partir da quarta posição; as músicas seguintes seguem o rodízio.
- Não apaga apresentações, comandas, eventos, mesas, tokens ou histórico existente.
