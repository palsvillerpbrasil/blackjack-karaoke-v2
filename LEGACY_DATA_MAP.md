# Mapa de migração — planilha Karaokê

Fonte: planilha Google Sheets `Karaokê`, exportada como XLSX para inspeção.

| Aba | Cabeçalhos principais | Destino |
|---|---|---|
| MESAS | id, numero, token, ativa, criada_em | `dining_tables` — IDs e tokens preservados |
| EVENTOS | id, nome, status, capacidade_inicial, criado_em, aberto_em, encerrado_em | `events` — IDs antigos em `legacy_id`, UUID novo determinístico |
| APRESENTAÇÕES | id, evento_id, mesa_id, mesa_numero, p1, p2, p3, musica, link, criado_em, status, ordem_manual, iniciada_em, cantada_em, request_id, comanda | `presentations` — status normalizado; link histórico preservado; comanda ausente fica NULL |
| PARTICIPANTES | evento_id, chave, nome, mesa_id, cantadas, ultima_em | `participant_stats` — preserva contagem agregada original |
| HISTÓRICO | data, usuario, acao, detalhes, evento_id | `audit_logs` — autor, ação, data e detalhes originais preservados |
| CONFIGURAÇÕES | chave, valor | `settings` — importa URL nova e capacidade da noite ativa; ignora PIN antigo |
| PAINEL | indicadores calculados | Não importado; será recalculado pelo painel web |

## Valores observados
- 17 mesas ativas, cada uma com token hexadecimal válido de 32 caracteres.
- 5 eventos: quatro encerrados e um aberto (`Melhores do Ano`).
- Capacidade atual da noite aberta: 20.
- 25 apresentações: 17 cantadas e 8 não cantadas.
- Duas apresentações antigas sem número de comanda.
- 16 linhas de estatísticas de participantes.
- 137 linhas de histórico.

## Regras de migração
- `CANTADA` → `SUNG`.
- `NAO_CANTADA` → `PENDING`.
- `ENCERRADO` → `FINISHED`.
- `ABERTO` → `OPEN`.
- IDs de eventos antigos são armazenados em `events.legacy_id`; as FKs usam UUID.
- `pin_admin` é deliberadamente descartado: a planilha contém PIN em texto puro e ele não é adequado como credencial administrativa.
- Não existe na planilha um registro confiável dos intervalos de comandas liberados. Eles devem ser configurados pelo painel para o evento atual.
