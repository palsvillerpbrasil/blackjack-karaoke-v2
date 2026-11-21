import ExcelJS from 'exceljs';
import { createClient } from '@supabase/supabase-js';
import crypto from 'node:crypto';
import path from 'node:path';

const file = process.argv[2] || path.resolve('Karaokê.xlsx');
const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) throw new Error('Defina SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY no ambiente local antes de executar a importação.');
const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
const { data: importFlag, error: importFlagError } = await db.from('settings').select('value').eq('key', 'legacy_import_completed').maybeSingle();
if (importFlagError) throw importFlagError;
if (importFlag?.value === true && !process.argv.includes('--force')) throw new Error('A migração legada já foi concluída neste banco. Para executar novamente, use --force somente após backup e revisão.');
const workbook = new ExcelJS.Workbook();
await workbook.xlsx.readFile(file);

function rows(sheetName) {
  const sheet = workbook.getWorksheet(sheetName);
  if (!sheet) throw new Error(`A aba ${sheetName} não existe no arquivo exportado.`);
  let headers = [];
  const out = [];
  sheet.eachRow({ includeEmpty: false }, (row, rowNumber) => {
    const values = row.values.slice(1);
    if (rowNumber === 1) headers = values.map(v => String(v ?? '').trim());
    else {
      const item = {};
      headers.forEach((h, i) => { if (h) item[h] = values[i] ?? null; });
      if (Object.values(item).some(v => v !== null && v !== '')) out.push(item);
    }
  });
  return out;
}
function value(v) { return v === null || v === undefined ? '' : String(v).trim(); }
function command(v) {
  if (v === null || v === undefined || v === '') return null;
  if (typeof v === 'number' && Number.isInteger(v)) return String(v);
  return String(v).trim().toUpperCase();
}
function dateIso(v) {
  if (!v) return null;
  if (v instanceof Date && !Number.isNaN(v.getTime())) return v.toISOString();
  const s = String(v).trim();
  const m = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?$/);
  if (m) return new Date(Number(m[3]), Number(m[2]) - 1, Number(m[1]), Number(m[4] || 0), Number(m[5] || 0), Number(m[6] || 0)).toISOString();
  const d = new Date(s); return Number.isNaN(d.getTime()) ? null : d.toISOString();
}
function normalized(v) { return value(v).normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/\s+/g, ' ').toLocaleLowerCase('pt-BR'); }
function deterministicUuid(source) {
  const b = crypto.createHash('sha256').update(`blackjack-legacy:${source}`).digest().subarray(0, 16);
  b[6] = (b[6] & 0x0f) | 0x50; b[8] = (b[8] & 0x3f) | 0x80;
  const h = b.toString('hex'); return `${h.slice(0,8)}-${h.slice(8,12)}-${h.slice(12,16)}-${h.slice(16,20)}-${h.slice(20)}`;
}
async function write(table, data, conflict) {
  for (let i = 0; i < data.length; i += 100) {
    const chunk = data.slice(i, i + 100);
    if (!chunk.length) continue;
    const { error } = await db.from(table).upsert(chunk, { onConflict: conflict });
    if (error) throw new Error(`${table}: ${error.message}`);
  }
}

const configRows = rows('CONFIGURAÇÕES');
const config = Object.fromEntries(configRows.map(x => [value(x.chave), x.valor]));
const activeLegacyId = value(config.evento_ativo);
const configuredCapacity = Number(config.capacidade || 45);

// 1) Eventos: IDs legados textuais são preservados em legacy_id e mapeados para UUID.
const oldEvents = rows('EVENTOS');
const { data: alreadyEvents, error: existingEventsError } = await db.from('events').select('id,legacy_id');
if (existingEventsError) throw existingEventsError;
const eventIdMap = new Map((alreadyEvents || []).filter(x => x.legacy_id).map(x => [x.legacy_id, x.id]));
const eventRows = oldEvents.map(e => {
  const legacyId = value(e.id);
  const id = eventIdMap.get(legacyId) || deterministicUuid(legacyId);
  let status = value(e.status).toUpperCase();
  status = status === 'ENCERRADO' ? 'FINISHED' : status === 'ABERTO' ? 'OPEN' : status === 'FECHADO' ? 'CLOSED' : ['OPEN','CLOSED','REGISTRATION_CLOSED','FINISHED'].includes(status) ? status : 'CLOSED';
  const capacity = legacyId === activeLegacyId ? configuredCapacity : Number(e.capacidade_inicial || 45);
  const created = dateIso(e.criado_em) || new Date().toISOString();
  return { id, legacy_id: legacyId, name: value(e.nome) || 'Noite de Karaokê', status, capacity, created_at: created, opened_at: dateIso(e.aberto_em), closed_at: dateIso(e.encerrado_em) };
});
await write('events', eventRows, 'id');
for (const e of eventRows) eventIdMap.set(e.legacy_id, e.id);

// 2) Mesas: mantém os IDs e tokens originais de 32 caracteres.
const oldTables = rows('MESAS');
const tableRows = oldTables.map(t => {
  const token = value(t.token).toLowerCase();
  if (!/^[a-f0-9]{32}$/.test(token)) throw new Error(`Token inválido na mesa ${value(t.numero)}. Importação interrompida sem alterar os dados restantes.`);
  return { id: value(t.id), number: Number(t.numero), token, active: String(t.ativa).toLowerCase() === 'true', created_at: dateIso(t.criada_em) || new Date().toISOString() };
});
const { data: currentTables, error: currentTablesError } = await db.from('dining_tables').select('id,number,token');
if (currentTablesError) throw currentTablesError;
for (const t of tableRows) {
  const sameNumber = (currentTables || []).find(x => x.number === t.number && x.id !== t.id);
  if (sameNumber) throw new Error(`Já existe uma mesa ${t.number} no Supabase com outro ID. Resolva essa duplicidade antes de importar; nenhum registro de mesa foi sobrescrito.`);
}
await write('dining_tables', tableRows, 'id');

// 3) Apresentações: status legado é convertido, comanda ausente permanece NULL.
const oldPresentations = rows('APRESENTAÇÕES');
const presentationRows = oldPresentations.map(p => {
  const eventId = eventIdMap.get(value(p.evento_id));
  if (!eventId) throw new Error(`Evento legado não localizado para a apresentação ${value(p.id)}.`);
  const statusOld = value(p.status).toUpperCase();
  const status = statusOld === 'CANTADA' ? 'SUNG' : ['CANCELADA','CANCELADO','CANCELLED'].includes(statusOld) ? 'CANCELLED' : ['TOCANDO','PLAYING'].includes(statusOld) ? 'PLAYING' : 'PENDING';
  const manual = p.ordem_manual === null || p.ordem_manual === undefined || p.ordem_manual === '' ? null : Number(p.ordem_manual);
  return {
    id: value(p.id), event_id: eventId, table_id: value(p.mesa_id), table_number: Number(p.mesa_numero),
    tab_number: command(p.comanda), p1: value(p.p1) || 'Participante não informado', p2: value(p.p2) || null, p3: value(p.p3) || null,
    song: value(p.musica) || 'Música não informada', youtube_url: value(p.link) || null, status,
    request_id: value(p.request_id) || `legacy-${value(p.id)}`, manual_position: Number.isFinite(manual) ? manual : null,
    manual_rank: Number.isFinite(manual) ? Math.round(manual * 1000) : null,
    created_at: dateIso(p.criado_em) || new Date().toISOString(), started_at: dateIso(p.iniciada_em), sung_at: dateIso(p.cantada_em),
    cancelled_at: status === 'CANCELLED' ? dateIso(p.cantada_em) || dateIso(p.criado_em) : null
  };
});
await write('presentations', presentationRows, 'id');

// 4) Participantes por apresentação, preservando o histórico de cada integrante.
const participantRows = [];
for (const p of presentationRows) {
  for (const name of [p.p1, p.p2, p.p3].filter(Boolean)) {
    const normalized_name = normalized(name);
    if (!participantRows.some(x => x.presentation_id === p.id && x.normalized_name === normalized_name)) {
      participantRows.push({ event_id: p.event_id, presentation_id: p.id, table_id: p.table_id, name, normalized_name });
    }
  }
}
if (participantRows.length) await write('participants', participantRows, 'presentation_id,normalized_name');

// 5) Estatísticas históricas agregadas da aba PARTICIPANTES, sem perder os contadores originais.
const oldStats = rows('PARTICIPANTES');
const statRows = oldStats.map(p => {
  const eventId = eventIdMap.get(value(p.evento_id));
  if (!eventId) return null;
  return { event_id: eventId, table_id: value(p.mesa_id), normalized_name: normalized(p.nome), name: value(p.nome), songs_sung: Number(p.cantadas || 0), last_sung_at: dateIso(p.ultima_em) };
}).filter(Boolean);
await write('participant_stats', statRows, 'event_id,table_id,normalized_name');

// 6) Histórico administrativo: mantém data, autor, ação e texto original em JSON.
const oldHistory = rows('HISTÓRICO');
const logRows = oldHistory.map((h, i) => ({
  legacy_id: `legacy-history-${i + 1}`, event_id: eventIdMap.get(value(h.evento_id)) || null,
  actor: value(h.usuario) || 'legacy', action: value(h.acao) || 'LEGACY_ACTION',
  details: { legacy_details: value(h.detalhes) }, created_at: dateIso(h.data) || new Date().toISOString()
}));
await write('audit_logs', logRows, 'legacy_id');

// 7) Configurações seguras. O PIN legado 1234 é deliberadamente descartado.
await write('settings', [
  { key: 'public_base_url', value: 'https://blackjack-karaoke-v2.netlify.app' },
  { key: 'legacy_active_event_id', value: activeLegacyId },
  { key: 'legacy_import_completed', value: true }
], 'key');

console.log(JSON.stringify({
  imported: { events: eventRows.length, tables: tableRows.length, presentations: presentationRows.length, participants: participantRows.length, participant_stats: statRows.length, audit_logs: logRows.length },
  activeLegacyEvent: activeLegacyId,
  currentCapacity: configuredCapacity,
  ignored: ['CONFIGURAÇÕES.pin_admin — PIN legado em texto puro não é migrado; crie senhas novas e seguras no painel.'],
  note: 'tab_releases não é importada porque a planilha não contém uma lista confiável dos intervalos liberados; configure as comandas pelo painel no evento atual.'
}, null, 2));
