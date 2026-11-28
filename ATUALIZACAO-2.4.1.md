# BLACK JACK KARAOKÊ — Atualização 2.4.1

## Sorteio no telão
- Os vencedores são revelados um por vez, com intervalo de 8 segundos.
- Cada vencedor permanece visível; os próximos cartões são acrescentados sem apagar os anteriores.
- Ao finalizar, todos os vencedores continuam na tela.
- A lista se adapta à quantidade de vencedores e permite rolagem quando necessário.

## Agradecimento e próximas datas
- Exibe até três próximas datas simultaneamente.
- Os cartões entram um por vez, em sequência: primeiro, segundo após 3 segundos e terceiro após mais 3 segundos.
- Depois que o último cartão entra, os três permanecem visíveis por 10 segundos.
- Em seguida, saem com transição suave e o ciclo recomeça.

## Identificação da mesa no QR Code
- A página do cliente mostra “MESA X” logo abaixo de “Sua vez de brilhar!”.
- O número é obtido do token do QR Code validado pelo servidor, não de um valor digitado pelo cliente.
- A identificação também aparece quando o evento está fechado e a página mostra os próximos eventos.

## Banco de dados
Não há alteração SQL nesta atualização.

## Publicação
Substitua os arquivos mantendo as pastas:
- `public/telao.html`
- `public/index.html`
- `package.json`

Faça Commit e Push pelo GitHub Desktop e aguarde a publicação da Netlify.
