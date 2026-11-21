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
