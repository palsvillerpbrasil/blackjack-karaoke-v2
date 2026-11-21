// Validação local mínima do pacote. Não escreve no banco.
import fs from 'node:fs';
const required=['supabase/schema.sql','netlify/functions/api.mjs','public/index.html','public/admin.html','public/telao.html','public/calendario.html','supabase/migrations/20261121_calendar_presenter_welcome.sql'];
let ok=true;for(const f of required){const yes=fs.existsSync(f);console.log(`${yes?'OK':'FALTA'} ${f}`);ok&&=yes}
if(!ok)process.exit(1);
console.log('Estrutura básica presente. A migração de dados ainda depende da exportação conferida.');
