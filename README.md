# BLACK JACK KARAOKÊ v2 — base de migração

## Estado desta entrega
Este pacote inicia a migração Netlify + Supabase. Inclui esquema PostgreSQL, função server-side inicial, formulário público simplificado e páginas de painel/telão em modo seguro. **Não é ainda uma substituição completa do sistema de produção**: painel ADM, autenticação por perfis, fila justa/posição manual transacional, sorteio animado, importador de dados e testes de concorrência precisam ser concluídos antes da virada.

## Regras já refletidas no modelo
- `event_tabs` e `tab_releases` têm chave vinculada ao `event_id`: a comanda é independente por noite.
- O número da comanda não é retornado por `public.status` e não aparece no telão.
- Sorteio guarda nome, música e mesa em `raffle_winners`; não há campo de comanda na projeção pública.
- As tabelas não têm políticas RLS públicas; a chave `service_role` fica somente nas variáveis de ambiente das Functions.
- As páginas públicas usam apenas `/api/`.

## Pré-requisitos
- Conta Netlify e projeto atual preservado.
- Projeto Supabase Free.
- Node.js 20+.

## Instalação em ambiente de teste
1. Crie um projeto no Supabase.
2. Abra SQL Editor e execute `supabase/schema.sql`.
3. No Supabase, copie Project URL e `service_role` key. Nunca coloque a service role no navegador ou em repositório público.
4. No projeto Netlify de teste, configure `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` em Site configuration → Environment variables.
5. Faça deploy deste diretório como projeto separado ou branch de preview. Não substitua ainda o site de produção.
6. Verifique `/.netlify/functions/api` via POST com `{"action":"health"}` (ou `/api/`).
7. Cadastre mesas/eventos de teste diretamente no SQL Editor somente no ambiente de teste.
8. Faça testes funcionais antes de qualquer importação real.

## Importação dos dados existentes
A planilha original continua sendo a fonte autoritativa durante a preparação. Não execute importação em produção ainda. A migração precisa:
- Exportar abas CONFIGURAÇÕES, MESAS, APRESENTAÇÕES, PARTICIPANTES, EVENTOS e HISTÓRICO.
- Preservar IDs, tokens de 32 caracteres, timestamps e status.
- Mapear status antigos (`NAO_CANTADA`, `PENDENTE`, `CANTADA`, `CANCELADA`) para os novos estados.
- Tratar comandas antigas como dados do evento original, sem criar vínculo permanente com a pessoa.
- Comparar contagens e hashes antes de liberar o tráfego.

## Regras que faltam antes da produção
1. RPC transacional de reserva: lock de evento/comanda, idempotência por requestId, limite de capacidade e bloqueio de participantes pendentes.
2. Fila automática com rodízio justo por mesa e prioridade manual persistente.
3. Login por senha com hash Argon2id/bcrypt, sessões curtas e papéis OWNER/ADMIN/COLLABORATOR.
4. APIs administrativas com checagem de permissão em toda chamada.
5. Cadastro/edição/liberação de comandas por evento.
6. Sorteio sem reposição, ponderação por mesa e broadcast de resultados para telão.
7. Telão com canal realtime ou polling incremental e sem dados de comanda.
8. Testes automatizados de concorrência, migração, cancelamento, encerramento e reabertura.
9. Backup automatizado externo e procedimento de restauração. Supabase Free não deve ser tratado como backup.
10. Revisão de segurança e testes de carga.

## Importante
A função `register` desta base é uma implementação inicial de integração, não deve receber tráfego de produção até a reserva ser movida para uma única função SQL transacional. O site antigo e a planilha não foram modificados.
