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
