# Atualização BLACK JACK KARAOKÊ — 22/11/2026

## Melhorias incluídas
- Transmissão de tela para os telões a partir da própria fila, com botões separados para iniciar normalmente ou iniciar compartilhando.
- Faixa de letreiro no telão mantendo música atual e próxima música visíveis durante o compartilhamento.
- Rodízio com histórico contado pela comanda e prioridade da primeira música somente a partir da quarta posição.
- Alteração de mesa sem zerar o histórico da comanda.
- Atualização automática da aba Comandas a cada dois minutos.
- Histórico recolhível de músicas cantadas com opção de devolução à fila.
- Contagem cronológica das músicas por pessoa/comanda no histórico.
- Marcação de lançamento em lote para os registros anteriores da mesma pessoa, comanda e noite.
- Inserção manual de música com acréscimo automático de capacidade e ocultação no telão até o início.
- Formulário QR Code retorna à identificação inicial após cada envio para permitir o uso compartilhado do mesmo celular.
- Sessões administrativas independentes preservadas; o sistema não invalida outros logins quando um perfil entra.

## Antes de publicar
1. Aplicar `supabase/migrations/20261122_screen_queue_history.sql` depois das migrações anteriores descritas no README.
2. Configurar `SUPABASE_ANON_KEY` nas variáveis da Netlify para habilitar a transmissão.
3. Publicar os arquivos do projeto na branch principal.
4. Testar compartilhamento em Chrome/Edge e confirmar se a rede dos telões permite WebRTC. Se a conexão direta falhar, integrar um servidor TURN com credenciais temporárias.

A chave `SUPABASE_SERVICE_ROLE_KEY` permanece exclusivamente no backend da Netlify.
