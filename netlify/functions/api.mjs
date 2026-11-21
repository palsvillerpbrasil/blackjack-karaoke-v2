import { createClient } from '@supabase/supabase-js';
import QRCode from 'qrcode';
import crypto from 'node:crypto';
import { promisify } from 'node:util';

const scrypt = promisify(crypto.scrypt);
let supabase;
const HEADERS = {
  'content-type': 'application/json; charset=utf-8',
  'cache-control': 'no-store',
  'access-control-allow-origin': '*',
  'access-control-allow-headers': 'content-type,authorization',
  'access-control-allow-methods': 'POST,OPTIONS'
};
const json = (status, body) => new Response(JSON.stringify(body), { status, headers: HEADERS });
const text = (v) => String(v ?? '').replace(/[\u0000-\u001f\u007f]/g, '').trim();
const norm = (v) => text(v).normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/\s+/g, ' ').toLocaleLowerCase('pt-BR');
const id = () => crypto.randomUUID();
const token32 = () => crypto.randomBytes(16).toString('hex');
const randomIndex = (n) => crypto.randomInt(0, n);

function db() {
  if (supabase) return supabase;
  const url = text(process.env.SUPABASE_URL);
  const key = text(process.env.SUPABASE_SERVICE_ROLE_KEY);
  if (!url || !key) throw new Error('Configure SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY nas variáveis da Netlify.');
  let parsed;
  try { parsed = new URL(url); } catch { throw new Error('SUPABASE_URL inválida. Use o Project URL completo do Supabase.'); }
  if (!['https:', 'http:'].includes(parsed.protocol)) throw new Error('SUPABASE_URL precisa começar com https:// ou http://.');
  supabase = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  return supabase;
}

function sessionSecret() {
  const value = text(process.env.ADMIN_SESSION_SECRET);
  if (value.length < 32) throw new Error('Configure ADMIN_SESSION_SECRET com pelo menos 32 caracteres na Netlify.');
  return value;
}
function safeEqual(a, b) {
  const aa = Buffer.from(String(a)); const bb = Buffer.from(String(b));
  return aa.length === bb.length && crypto.timingSafeEqual(aa, bb);
}
function sign(value) { return crypto.createHmac('sha256', sessionSecret()).update(value).digest('base64url'); }
function makeSession(admin) {
  const payload = Buffer.from(JSON.stringify({ sub: admin.id, exp: Date.now() + 8 * 60 * 60 * 1000 })).toString('base64url');
  return `${payload}.${sign(payload)}`;
}
async function requireAdmin(req) {
  const bearer = (req.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
  const [payload, signature] = bearer.split('.');
  if (!payload || !signature || !safeEqual(signature, sign(payload))) throw new Error('Sessão inválida. Entre novamente.');
  let data;
  try { data = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')); } catch { throw new Error('Sessão inválida. Entre novamente.'); }
  if (!data.sub || !data.exp || data.exp < Date.now()) throw new Error('Sessão expirada. Entre novamente.');
  const { data: admin, error } = await db().from('admins').select('id,display_name,role,active').eq('id', data.sub).maybeSingle();
  if (error || !admin || !admin.active) throw new Error('Administrador inativo ou não encontrado.');
  return admin;
}
function assertFull(admin) {
  if (!['OWNER', 'ADMIN'].includes(admin.role)) throw new Error('Seu perfil não tem permissão para esta operação.');
}
async function hashPassword(password) {
  const salt = crypto.randomBytes(16).toString('hex');
  const key = await scrypt(password, salt, 64);
  return `scrypt$${salt}$${Buffer.from(key).toString('hex')}`;
}
async function verifyPassword(password, stored) {
  const [kind, salt, hex] = String(stored || '').split('$');
  if (kind !== 'scrypt' || !salt || !hex) return false;
  const key = await scrypt(password, salt, 64);
  return safeEqual(Buffer.from(key).toString('hex'), hex);
}
async function audit(actor, action, details = {}, eventId = null) {
  await db().from('audit_logs').insert({ actor: actor || 'system', action, details, event_id: eventId });
}
async function latestEvent() {
  const { data, error } = await db().from('events').select('*').order('created_at', { ascending: false }).limit(1).maybeSingle();
  if (error) throw error;
  return data;
}
function saoPauloDateString() {
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(new Date());
  const values = Object.fromEntries(parts.map(part => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}
async function calendarEventForDate(date = saoPauloDateString()) {
  const { data, error } = await db().from('karaoke_calendar')
    .select('id,event_date,title,presenter_name,has_karaoke')
    .eq('event_date', date).eq('has_karaoke', true).maybeSingle();
  if (error) throw error;
  return data || null;
}
async function nextCalendarEvent(afterToday = false) {
  const today = saoPauloDateString();
  let query = db().from('karaoke_calendar').select('id,event_date,title,presenter_name,has_karaoke')
    .eq('has_karaoke', true).order('event_date', { ascending: true }).limit(1);
  query = afterToday ? query.gt('event_date', today) : query.gte('event_date', today);
  const { data, error } = await query.maybeSingle();
  if (error) throw error;
  return data || null;
}
async function eventForPublic() {
  const event = await latestEvent();
  return event && event.status !== 'FINISHED' ? event : null;
}
async function validateTableToken(token) {
  const value = text(token).toLowerCase();
  if (!/^[a-f0-9]{32}$/.test(value)) throw new Error('QR Code inválido. Escaneie novamente o código da sua mesa.');
  const { data, error } = await db().from('dining_tables').select('id,number,active').eq('token', value).maybeSingle();
  if (error) throw error;
  if (!data || !data.active) throw new Error('Mesa inválida ou desativada.');
  return data;
}

async function queueForEvent(event) {
  if (!event) return { current: null, last: null, queue: [], manualMode: false };
  const client = db();
  const [{ data: rows, error: re }, { data: participants, error: pe }, { data: sungRows, error: se }, { data: state, error: qe }, { data: stats, error: ste }] = await Promise.all([
    client.from('presentations').select('id,event_id,table_id,table_number,tab_number,p1,p2,p3,song,status,created_at,started_at,sung_at,manual_rank,manual_position,round_number').eq('event_id', event.id).in('status', ['PENDING', 'PLAYING', 'SUNG']).order('created_at'),
    client.from('participants').select('presentation_id,table_id,normalized_name,name').eq('event_id', event.id),
    client.from('presentations').select('id,sung_at,table_number').eq('event_id', event.id).eq('status', 'SUNG'),
    client.from('queue_state').select('last_sung_table_number,manual_mode').eq('event_id', event.id).maybeSingle(),
    client.from('participant_stats').select('table_id,normalized_name,songs_sung').eq('event_id', event.id)
  ]);
  if (re) throw re; if (pe) throw pe; if (se) throw se; if (qe) throw qe; if (ste) throw ste;
  const participantMap = new Map();
  for (const p of participants || []) {
    if (!participantMap.has(p.presentation_id)) participantMap.set(p.presentation_id, []);
    participantMap.get(p.presentation_id).push(p);
  }
  const sungIds = new Set((sungRows || []).map(x => x.id));
  const history = new Map();
  for (const p of participants || []) if (sungIds.has(p.presentation_id)) {
    const key = `${p.table_id}|${p.normalized_name}`; history.set(key, (history.get(key) || 0) + 1);
  }
  for (const stat of stats || []) history.set(`${stat.table_id}|${stat.normalized_name}`, Number(stat.songs_sung || 0));
  const current = (rows || []).find(x => x.status === 'PLAYING') || null;
  const pending = (rows || []).filter(x => x.status === 'PENDING');
  // Ajustes manuais são exceções pontuais: o rodízio automático continua
  // ordenando todas as outras apresentações e preenchendo os espaços livres.
  const manual = pending.filter(x => x.manual_position !== null && x.manual_position !== undefined || x.manual_rank !== null && x.manual_rank !== undefined)
    .sort((a, b) => Number(a.manual_position ?? (Number(a.manual_rank) / 1000)) - Number(b.manual_position ?? (Number(b.manual_rank) / 1000)) || Number(a.manual_rank || 0) - Number(b.manual_rank || 0));
  const manualIds = new Set(manual.map(x => x.id));
  const auto = pending.filter(x => !manualIds.has(x.id));
  const tableGroups = new Map();
  for (const p of auto) {
    if (!tableGroups.has(p.table_number)) tableGroups.set(p.table_number, []);
    const members = participantMap.get(p.id) || [];
    const counts = members.map(m => history.get(`${m.table_id}|${m.normalized_name}`) || 0);
    p._historyAverage = counts.length ? counts.reduce((a, b) => a + b, 0) / counts.length : 0;
    p._neverSung = counts.length ? counts.every(x => x === 0) : true;
    tableGroups.get(p.table_number).push(p);
  }
  for (const list of tableGroups.values()) list.sort((a, b) => a._historyAverage - b._historyAverage || new Date(a.created_at) - new Date(b.created_at));
  const tableNumbers = [...tableGroups.keys()].sort((a, b) => a - b);
  const cursor = state?.last_sung_table_number ?? null;
  const rotation = cursor === null ? tableNumbers : [...tableNumbers.filter(n => n > cursor), ...tableNumbers.filter(n => n <= cursor)];
  const automaticOrder = [];
  let round = 1;
  while (automaticOrder.length < auto.length) {
    let added = false;
    for (const tableNumber of rotation) {
      const next = tableGroups.get(tableNumber)?.shift();
      if (next) { next._round = round; automaticOrder.push(next); added = true; }
    }
    if (!added) break;
    round++;
  }
  const mergedOrder = automaticOrder.slice();
  for (const p of manual) {
    const desired = Number(p.manual_position ?? (Number(p.manual_rank) / 1000) ?? 1);
    const index = Math.max(0, Math.min(mergedOrder.length, (Number.isFinite(desired) ? desired : 1) - 1));
    mergedOrder.splice(index, 0, p);
  }
  const ordered = mergedOrder.map((p, index) => ({
    ...p,
    position: index + 1,
    round: manualIds.has(p.id) ? 'Manual' : (p._round || 1),
    history_count: (participantMap.get(p.id) || []).reduce((sum, m) => sum + (history.get(`${m.table_id}|${m.normalized_name}`) || 0), 0),
    participants: (participantMap.get(p.id) || []).map(m => m.name)
  }));
  const last = (rows || []).filter(x => x.status === 'SUNG').sort((a, b) => new Date(b.sung_at || b.created_at) - new Date(a.sung_at || a.created_at))[0] || null;
  const clean = p => p ? ({ id: p.id, table_number: p.table_number, tab_number: p.tab_number, p1: p.p1, p2: p.p2, p3: p.p3, song: p.song, status: p.status, created_at: p.created_at, started_at: p.started_at, sung_at: p.sung_at }) : null;
  return { current: clean(current), last: clean(last), queue: ordered, manualMode: Boolean(state?.manual_mode), manualCount: manual.length, automaticActive: true, cursor };
}
function publicPresentation(p) {
  if (!p) return null;
  return { id: p.id, table_number: p.table_number, p1: p.p1, p2: p.p2, p3: p.p3, song: p.song, status: p.status, created_at: p.created_at, started_at: p.started_at, sung_at: p.sung_at };
}
async function publicStatus(token) {
  const table = await validateTableToken(token);
  const event = await eventForPublic();
  if (!event) return { ok: true, table: table.number, event: null, open: false, available: 0, capacity: 0, last: null, current: null, next: null };
  const q = await queueForEvent(event);
  const { count, error } = await db().from('presentations').select('id', { count: 'exact', head: true }).eq('event_id', event.id).in('status', ['PENDING', 'PLAYING', 'SUNG']);
  if (error) throw error;
  return { ok: true, table: table.number, event: event.name, status: event.status, open: event.status === 'OPEN', capacity: event.capacity, available: Math.max(0, event.capacity - (count || 0)), last: publicPresentation(q.last), current: publicPresentation(q.current), next: publicPresentation(q.queue[0]) };
}
async function lookupTab(token, tabValue) {
  const table = await validateTableToken(token);
  const tab = text(tabValue).toUpperCase();
  if (!/^[A-Z0-9]{1,10}$/.test(tab)) throw new Error('Informe uma comanda válida (até 10 caracteres).');
  const event = await eventForPublic();
  if (!event || event.status !== 'OPEN') throw new Error('As inscrições estão fechadas.');
  const { data: release, error: re } = await db().from('tab_releases').select('enabled').eq('event_id', event.id).eq('tab_number', tab).maybeSingle();
  if (re) throw re;
  if (!release?.enabled) throw new Error('Sua comanda não está liberada. Consulte os responsáveis.');
  const { data: existing, error } = await db().from('event_tabs').select('participant_name').eq('event_id', event.id).eq('tab_number', tab).maybeSingle();
  if (error) throw error;
  const { data: pending, error: pe } = await db().from('presentations').select('id,status').eq('event_id', event.id).eq('tab_number', tab).in('status', ['PENDING', 'PLAYING']).limit(1).maybeSingle();
  if (pe) throw pe;
  return { ok: true, table: table.number, registered: Boolean(existing), name: existing?.participant_name || '', pending: Boolean(pending), can_submit: !pending };
}
async function identifyTab(body) {
  const tab = text(body.tab).toUpperCase();
  const existing = await lookupTab(body.token, tab);
  // A comanda já cadastrada sempre usa o nome salvo no servidor; o cliente
  // não consegue sobrescrevê-lo nem mesmo alterando a requisição manualmente.
  const canonicalName = existing.registered ? existing.name : text(body.name);
  const { data, error } = await db().rpc('bj_identify_tab', { p_token: text(body.token).toLowerCase(), p_tab: tab, p_name: canonicalName });
  if (error) throw error;
  return { ...data, name: existing.registered ? existing.name : data.name };
}
async function registerPresentation(body) {
  const tab = text(body.tab).toUpperCase();
  const identity = await lookupTab(body.token, tab);
  if (!identity.registered) throw new Error('Identifique esta comanda antes de enviar uma música.');
  if (identity.pending) throw new Error('Esta comanda já possui uma apresentação aguardando ou tocando.');
  const { data, error } = await db().rpc('bj_register_presentation', {
    p_token: text(body.token).toLowerCase(), p_tab: tab, p_p1: identity.name,
    p_p2: text(body.p2), p_p3: text(body.p3), p_song: text(body.song), p_request_id: text(body.requestId)
  });
  if (error) throw error;
  return data;
}

async function screenStatus() {
  const event = await eventForPublic();
  if (!event) return { ok: true, event: null, capacity: 0, available: 0, current: null, last: null, next: null, queue: [], raffle: null };
  const q = await queueForEvent(event);
  // Remaining presentation slots follow the same rule as the customer page:
  // pending, currently playing and already sung presentations consume a slot.
  const { count: usedCount, error: countError } = await db()
    .from('presentations')
    .select('id', { count: 'exact', head: true })
    .eq('event_id', event.id)
    .in('status', ['PENDING', 'PLAYING', 'SUNG']);
  if (countError) throw countError;
  const capacity = Number(event.capacity || 0);
  const available = Math.max(0, capacity - (usedCount || 0));
  const { data: raffle, error: re } = await db().from('raffles').select('id,status,requested_winners,created_at,reveal_at,results_ready').eq('event_id', event.id).order('created_at', { ascending: false }).limit(1).maybeSingle();
  if (re) throw re;
  let rafflePayload = null;
  if (raffle && (raffle.status === 'RUNNING' || Date.now() - new Date(raffle.created_at).getTime() < 60000)) {
    if (raffle.status === 'RUNNING' && raffle.results_ready && raffle.reveal_at && new Date(raffle.reveal_at).getTime() <= Date.now()) {
      await db().from('raffles').update({ status: 'FINISHED', finished_at: new Date().toISOString() }).eq('id', raffle.id);
      raffle.status = 'FINISHED';
    }
    const { data: sung, error: se } = await db().from('presentations').select('id,song,table_number').eq('event_id', event.id).eq('status', 'SUNG');
    if (se) throw se;
    const sungIds = (sung || []).map(x => x.id);
    const { data: people, error: pe } = sungIds.length ? await db().from('participants').select('presentation_id,name,normalized_name').in('presentation_id', sungIds) : { data: [], error: null };
    if (pe) throw pe;
    const byId = new Map((sung || []).map(x => [x.id, x]));
    const spinCandidates = (people || []).map(p => ({ name: p.name, song: byId.get(p.presentation_id)?.song, table_number: byId.get(p.presentation_id)?.table_number })).filter(x => x.name);
    let winners = [];
    if (raffle.status === 'FINISHED' && raffle.results_ready) {
      const { data: winnerRows, error: we } = await db().from('raffle_winners').select('participant_name,song,table_number,position').eq('raffle_id', raffle.id).order('position');
      if (we) throw we;
      winners = winnerRows || [];
    }
    rafflePayload = { id: raffle.id, status: raffle.status, requested_winners: raffle.requested_winners, reveal_at: raffle.reveal_at, revealed: raffle.status === 'FINISHED' && raffle.results_ready, spinCandidates, winners };
  }
  return { ok: true, event: { name: event.name, status: event.status }, capacity, available, current: publicPresentation(q.current), last: publicPresentation(q.last), next: publicPresentation(q.queue[0]), raffle: rafflePayload };
}

async function dashboard() {
  const event = await latestEvent();
  const { count: tableCount, error: te } = await db().from('dining_tables').select('id', { count: 'exact', head: true });
  if (te) throw te;
  if (!event) return { event: null, tables: tableCount || 0, counts: { reserved: 0, sung: 0, cancelled: 0, waiting: 0, available: 0, capacity: 45 }, releasedTabs: 0, usedTabs: 0 };
  const { data: rows, error } = await db().from('presentations').select('id,status,tab_number').eq('event_id', event.id);
  if (error) throw error;
  const list = rows || [];
  const reserved = list.filter(x => ['PENDING', 'PLAYING'].includes(x.status)).length;
  const sung = list.filter(x => x.status === 'SUNG').length;
  const cancelled = list.filter(x => x.status === 'CANCELLED').length;
  const { count: releasedTabs, error: re } = await db().from('tab_releases').select('tab_number', { count: 'exact', head: true }).eq('event_id', event.id).eq('enabled', true);
  if (re) throw re;
  const { count: usedTabs, error: ue } = await db().from('event_tabs').select('tab_number', { count: 'exact', head: true }).eq('event_id', event.id);
  if (ue) throw ue;
  const pendingIds = list.filter(x => ['PENDING','PLAYING'].includes(x.status)).map(x => x.id);
  const { count: waitingPeople, error: we } = pendingIds.length ? await db().from('participants').select('id', { count: 'exact', head: true }).eq('event_id', event.id).in('presentation_id', pendingIds) : { count: 0, error: null };
  if (we) throw we;
  return { event, tables: tableCount || 0, counts: { reserved, sung, cancelled, waiting: waitingPeople || 0, available: Math.max(0, event.capacity - reserved - sung), capacity: event.capacity }, releasedTabs: releasedTabs || 0, usedTabs: usedTabs || 0 };
}

async function adminQueue(event) {
  if (!event) return { current: null, last: null, queue: [], manualMode: false, manualCount: 0, automaticActive: true };
  return queueForEvent(event);
}
async function listTabs(event) {
  if (!event) return [];
  const [{ data: releases, error: re }, { data: tabs, error: te }, { data: presentations, error: pe }] = await Promise.all([
    db().from('tab_releases').select('tab_number,enabled').eq('event_id', event.id).order('tab_number'),
    db().from('event_tabs').select('tab_number,participant_name,created_at').eq('event_id', event.id).order('tab_number'),
    db().from('presentations').select('tab_number,status').eq('event_id', event.id).in('status', ['PENDING', 'PLAYING', 'SUNG'])
  ]);
  if (re) throw re; if (te) throw te; if (pe) throw pe;
  const tabMap = new Map((tabs || []).map(x => [x.tab_number, x]));
  const pending = new Set((presentations || []).filter(x => ['PENDING', 'PLAYING'].includes(x.status)).map(x => x.tab_number));
  const sung = new Set((presentations || []).filter(x => x.status === 'SUNG').map(x => x.tab_number));
  return (releases || []).map(x => ({ ...x, participant_name: tabMap.get(x.tab_number)?.participant_name || '', registered: tabMap.has(x.tab_number), pending: pending.has(x.tab_number), sung: sung.has(x.tab_number) }));
}

async function raffleDraw(event, count, actor) {
  if (!event) throw new Error('Não existe evento ativo.');
  const n = Number(count);
  if (!Number.isInteger(n) || n < 1 || n > 100) throw new Error('Informe uma quantidade entre 1 e 100.');
  const nowIso = new Date().toISOString();
  await db().from('raffles').update({ status: 'FINISHED', finished_at: nowIso }).eq('event_id', event.id).eq('status', 'RUNNING').eq('results_ready', true).lte('reveal_at', nowIso);
  const { data: triggerSetting, error: triggerError } = await db().from('settings').select('value').eq('key', 'raffle_trigger_count').maybeSingle();
  if (triggerError) throw triggerError;
  const triggerCount = Number(triggerSetting?.value || 0);
  const { count: sungCount, error: sungCountError } = await db().from('presentations').select('id', { count: 'exact', head: true }).eq('event_id', event.id).eq('status', 'SUNG');
  if (sungCountError) throw sungCountError;
  if (triggerCount > 0 && (sungCount || 0) < triggerCount) throw new Error(`O sorteio estará disponível após ${triggerCount} músicas cantadas. Até agora: ${sungCount || 0}.`);
  const { data: activeRaffle, error: ar } = await db().from('raffles').select('id').eq('event_id', event.id).eq('status', 'RUNNING').limit(1).maybeSingle();
  if (ar) throw ar;
  if (activeRaffle) throw new Error('Já existe um sorteio em andamento. Aguarde a revelação.');
  const { data: sung, error: se } = await db().from('presentations').select('id,song,table_number').eq('event_id', event.id).eq('status', 'SUNG');
  if (se) throw se;
  if (!sung?.length) throw new Error('Ainda não existem apresentações cantadas para o sorteio.');
  const sungMap = new Map(sung.map(x => [x.id, x]));
  const { data: people, error: pe } = await db().from('participants').select('presentation_id,name,normalized_name').eq('event_id', event.id).in('presentation_id', sung.map(x => x.id));
  if (pe) throw pe;
  const { data: previous, error: we } = await db().from('raffle_winners').select('participant_norm').eq('event_id', event.id);
  if (we) throw we;
  const already = new Set((previous || []).map(x => x.participant_norm));
  const grouped = new Map();
  for (const p of people || []) {
    if (already.has(p.normalized_name)) continue;
    const presentation = sungMap.get(p.presentation_id);
    if (!presentation) continue;
    if (!grouped.has(p.normalized_name)) grouped.set(p.normalized_name, { name: p.name, norm: p.normalized_name, performances: [] });
    grouped.get(p.normalized_name).performances.push({ presentation_id: p.presentation_id, song: presentation.song, table_number: presentation.table_number });
  }
  const candidates = [...grouped.values()].map(person => {
    const performance = person.performances[randomIndex(person.performances.length)];
    return { participant_name: person.name, participant_norm: person.norm, ...performance };
  });
  if (candidates.length < n) throw new Error(`Existem somente ${candidates.length} pessoas elegíveis. Reduza a quantidade de vencedores.`);
  const raffle = await db().from('raffles').insert({ event_id: event.id, status: 'RUNNING', requested_winners: n }).select('id').single();
  if (raffle.error) throw raffle.error;
  const remaining = [...candidates];
  const selected = [];
  const tableWins = new Map();
  while (selected.length < n) {
    const byTable = new Map();
    for (const person of remaining) {
      if (!byTable.has(person.table_number)) byTable.set(person.table_number, []);
      byTable.get(person.table_number).push(person);
    }
    const tables = [...byTable.keys()];
    const weights = tables.map(t => 1 / (1 + (tableWins.get(t) || 0)));
    const total = weights.reduce((a, b) => a + b, 0);
    let draw = crypto.randomInt(0, 1_000_000_000) / 1_000_000_000 * total;
    let chosenTable = tables[0];
    for (let i = 0; i < tables.length; i++) { draw -= weights[i]; if (draw <= 0) { chosenTable = tables[i]; break; } }
    const group = byTable.get(chosenTable);
    const chosen = group[randomIndex(group.length)];
    selected.push({ ...chosen, position: selected.length + 1 });
    tableWins.set(chosenTable, (tableWins.get(chosenTable) || 0) + 1);
    remaining.splice(remaining.findIndex(x => x.participant_norm === chosen.participant_norm), 1);
  }
  const { data: saved, error: saveError } = await db().rpc('bj_save_raffle_winners', { p_raffle_id: raffle.data.id, p_event_id: event.id, p_winners: selected, p_actor: actor.display_name });
  if (saveError) {
    await db().from('raffles').update({ status: 'CANCELLED' }).eq('id', raffle.data.id);
    throw saveError;
  }
  return { ok: true, raffle_id: raffle.data.id, requested_winners: n, reveal_at: saved.reveal_at, winners: selected.map(x => ({ participant_name: x.participant_name, song: x.song, table_number: x.table_number, position: x.position })) };
}

async function handleAdmin(action, body, req) {
  if (action === 'admin.bootstrapStatus') {
    const { count, error } = await db().from('admins').select('id', { count: 'exact', head: true });
    if (error) throw error;
    return { ok: true, needsBootstrap: (count || 0) === 0 };
  }
  if (action === 'admin.bootstrap') {
    if (!process.env.ADMIN_SETUP_KEY) throw new Error('Configure ADMIN_SETUP_KEY nas variáveis da Netlify antes do primeiro acesso.');
    if (!safeEqual(text(body.setupKey), text(process.env.ADMIN_SETUP_KEY))) throw new Error('Chave inicial incorreta.');
    const { count, error } = await db().from('admins').select('id', { count: 'exact', head: true });
    if (error) throw error;
    if ((count || 0) > 0) throw new Error('A configuração inicial já foi realizada. Entre com sua senha.');
    const password = String(body.password || '');
    if (password.length < 10) throw new Error('A senha deve ter pelo menos 10 caracteres.');
    const password_hash = await hashPassword(password);
    const { data, error: insertError } = await db().from('admins').insert({ display_name: 'Administrador 1', role: 'OWNER', password_hash, active: true }).select('id,display_name,role').single();
    if (insertError) throw insertError;
    await audit(data.display_name, 'ADMIN_BOOTSTRAP');
    return { ok: true, token: makeSession(data), admin: data };
  }
  if (action === 'admin.login') {
    const password = String(body.password || '');
    if (!password) throw new Error('Informe sua senha.');
    const ip = req.headers.get('x-nf-client-connection-ip') || (req.headers.get('x-forwarded-for') || 'unknown').split(',')[0].trim();
    const ipHash = crypto.createHmac('sha256', sessionSecret()).update(ip || 'unknown').digest('hex');
    const { data: gate, error: gateError } = await db().rpc('bj_login_guard', { p_ip_hash: ipHash, p_success: null });
    if (gateError) throw gateError;
    if (!gate?.allowed) throw new Error('Muitas tentativas de acesso. Aguarde 15 minutos antes de tentar novamente.');
    const { data: admins, error } = await db().from('admins').select('id,display_name,role,password_hash').eq('active', true);
    if (error) throw error;
    const matches = [];
    for (const admin of admins || []) if (await verifyPassword(password, admin.password_hash)) matches.push(admin);
    if (matches.length !== 1) {
      await db().rpc('bj_login_guard', { p_ip_hash: ipHash, p_success: false });
      throw new Error(matches.length > 1 ? 'Senha compartilhada entre perfis. O administrador precisa definir senhas diferentes.' : 'Senha incorreta.');
    }
    await db().rpc('bj_login_guard', { p_ip_hash: ipHash, p_success: true });
    const admin = matches[0];
    return { ok: true, token: makeSession(admin), admin: { id: admin.id, display_name: admin.display_name, role: admin.role } };
  }

  const admin = await requireAdmin(req);
  if (action === 'admin.me') return { ok: true, admin };
  const collaboratorAllowed = new Set([
    'admin.tables.list', 'admin.tables.qr',
    'admin.tabs.list', 'admin.tabs.releaseRange', 'admin.tabs.set', 'admin.tabs.update',
    'admin.events.list', 'admin.history', 'admin.history.mark'
  ]);
  if (admin.role === 'COLLABORATOR' && !collaboratorAllowed.has(action)) {
    throw new Error('Seu perfil permite somente acessar Mesas, Comandas e Histórico.');
  }
  if (action === 'admin.dashboard') { assertFull(admin); return { ok: true, ...(await dashboard()) }; }
  if (action === 'admin.tabs.list') {
    const event = await eventForPublic();
    return { ok: true, event, tabs: await listTabs(event) };
  }
  if (action === 'admin.tabs.releaseRange' || action === 'admin.tabs.set') {
    const event = await eventForPublic();
    if (!event) throw new Error('Crie uma nova noite antes de liberar comandas.');
    const values = action === 'admin.tabs.set' ? [text(body.tab).toUpperCase()] : (() => {
      const fromText = text(body.from); const toText = text(body.to);
      if (!fromText || !toText) throw new Error('Informe o início e o fim do intervalo.');
      const from = Number(fromText); const to = Number(toText);
      if (!Number.isInteger(from) || !Number.isInteger(to) || from < 0 || to < from || to - from > 500) throw new Error('Intervalo de comandas inválido (máximo de 501 números por operação).');
      return Array.from({ length: to - from + 1 }, (_, i) => String(from + i));
    })();
    if (values.some(v => !/^[A-Z0-9]{1,10}$/.test(v))) throw new Error('Comanda inválida. Use letras e números, até 10 caracteres.');
    const enabled = body.enabled !== false;
    const rows = values.map(tab_number => ({ event_id: event.id, tab_number, enabled }));
    const { error } = await db().from('tab_releases').upsert(rows, { onConflict: 'event_id,tab_number' });
    if (error) throw error;
    await audit(admin.display_name, enabled ? 'TABS_RELEASED' : 'TABS_BLOCKED', { values }, event.id);
    return { ok: true, tabs: await listTabs(event) };
  }
  if (action === 'admin.tabs.update') {
    const event = await eventForPublic();
    if (!event) throw new Error('Não existe evento ativo para editar comandas.');
    const oldTab = text(body.oldTab).toUpperCase();
    const newTab = text(body.tab).toUpperCase();
    const name = text(body.name);
    if (!/^[A-Z0-9]{1,10}$/.test(oldTab) || !/^[A-Z0-9]{1,10}$/.test(newTab)) throw new Error('Comanda inválida. Use letras e números, até 10 caracteres.');
    if (name.length < 2 || name.length > 70) throw new Error('O nome deve ter entre 2 e 70 caracteres.');
    const { data, error } = await db().rpc('bj_admin_update_tab', {
      p_event_id: event.id, p_old_tab: oldTab, p_new_tab: newTab, p_name: name, p_actor: admin.display_name
    });
    if (error) throw error;
    return { ok: true, result: data, tabs: await listTabs(event) };
  }
  if (action === 'admin.tables.list') {
    const { data, error } = await db().from('dining_tables').select('id,number,token,active,created_at').order('number');
    if (error) throw error; return { ok: true, tables: data || [] };
  }
  if (action === 'admin.tables.create') {
    const number = Number(body.number);
    if (!Number.isInteger(number) || number < 1 || number > 999) throw new Error('Número da mesa inválido (1 a 999).');
    const { data, error } = await db().from('dining_tables').insert({ id: id(), number, token: token32(), active: true }).select('id,number,token,active,created_at').single();
    if (error) throw error; await audit(admin.display_name, 'TABLE_CREATED', { number }); return { ok: true, table: data };
  }
  if (action === 'admin.tables.update') {
    const number = Number(body.number);
    if (!Number.isInteger(number) || number < 1 || number > 999) throw new Error('Número da mesa inválido.');
    const { data, error } = await db().from('dining_tables').update({ number, active: Boolean(body.active) }).eq('id', text(body.id)).select('id,number,token,active,created_at').single();
    if (error) throw error; await audit(admin.display_name, 'TABLE_UPDATED', { number, active: Boolean(body.active) }); return { ok: true, table: data };
  }
  if (action === 'admin.tables.regenerate') {
    const { data, error } = await db().from('dining_tables').update({ token: token32() }).eq('id', text(body.id)).select('id,number,token,active,created_at').single();
    if (error) throw error; await audit(admin.display_name, 'TABLE_TOKEN_REGENERATED', { number: data.number }); return { ok: true, table: data };
  }
  if (action === 'admin.tables.qr') {
    const { data: table, error } = await db().from('dining_tables').select('id,number,token,active').eq('id', text(body.id)).single();
    if (error) throw error; if (!table.active) throw new Error('Ative a mesa antes de gerar o QR Code.');
    const base = text(body.baseUrl || process.env.PUBLIC_APP_URL || 'https://blackjack-karaoke-v2.netlify.app').replace(/\/$/, '');
    const url = `${base}/?m=${table.token}`;
    return { ok: true, url, dataUrl: await QRCode.toDataURL(url, { width: 600, margin: 2, errorCorrectionLevel: 'H', color: { dark: '#080808', light: '#FFFFFF' } }), table };
  }

  if (action.startsWith('admin.events.')) {
    const latest = await latestEvent();
    if (action === 'admin.events.list') {
      const { data, error } = await db().from('events').select('*').order('created_at', { ascending: false }).limit(100);
      if (error) throw error; return { ok: true, events: data || [] };
    }
    if (action === 'admin.events.create') {
      if (latest && latest.status !== 'FINISHED') throw new Error('Encerre o evento atual antes de iniciar uma nova noite.');
      const scheduled = await calendarEventForDate();
      const name = text(body.name) || scheduled?.title || `Karaokê ${new Date().toLocaleDateString('pt-BR')}`;
      const capacity = Number(body.capacity ?? 45);
      if (!Number.isInteger(capacity) || capacity < 1 || capacity > 10000) throw new Error('Capacidade inválida.');
      const { data, error } = await db().from('events').insert({ name, status: 'CLOSED', capacity }).select('*').single();
      if (error) throw error;
      await db().from('queue_state').upsert({ event_id: data.id, manual_mode: false }, { onConflict: 'event_id' });
      await audit(admin.display_name, 'EVENT_CREATED', { name, capacity }, data.id); return { ok: true, event: data, dashboard: await dashboard() };
    }
    if (!latest) throw new Error('Nenhum evento cadastrado. Crie uma nova noite.');
    if (action === 'admin.events.open' || action === 'admin.events.reopen') {
      const { data, error } = await db().from('events').update({ status: 'OPEN', opened_at: new Date().toISOString() }).eq('id', latest.id).select('*').single();
      if (error) throw error; await audit(admin.display_name, 'EVENT_OPENED', {}, latest.id); return { ok: true, event: data, dashboard: await dashboard() };
    }
    if (action === 'admin.events.close') {
      const { data, error } = await db().from('events').update({ status: 'REGISTRATION_CLOSED', closed_at: new Date().toISOString() }).eq('id', latest.id).select('*').single();
      if (error) throw error; await audit(admin.display_name, 'REGISTRATION_CLOSED', {}, latest.id); return { ok: true, event: data, dashboard: await dashboard() };
    }
    if (action === 'admin.events.finish') {
      const { data, error } = await db().from('events').update({ status: 'FINISHED', closed_at: new Date().toISOString() }).eq('id', latest.id).select('*').single();
      if (error) throw error; await audit(admin.display_name, 'EVENT_FINISHED', {}, latest.id); return { ok: true, event: data, dashboard: await dashboard() };
    }
    if (action === 'admin.events.capacity') {
      const capacity = Number(body.capacity);
      if (!Number.isInteger(capacity) || capacity < 0 || capacity > 10000) throw new Error('Capacidade inválida.');
      const { data, error } = await db().from('events').update({ capacity }).eq('id', latest.id).select('*').single();
      if (error) throw error; await audit(admin.display_name, 'CAPACITY_UPDATED', { capacity }, latest.id); return { ok: true, event: data, dashboard: await dashboard() };
    }
  }

  if (action === 'admin.queue.list') {
    const event = await eventForPublic(); return { ok: true, event, ...(await adminQueue(event)) };
  }
  if (action === 'admin.queue.reorder') {
    const event = await eventForPublic(); if (!event) throw new Error('Não existe evento ativo.');
    const q = await adminQueue(event);
    let presentationId = text(body.id);
    let position = Number(body.position);
    // Compatibilidade com versões anteriores do painel: converte uma
    // reordenação por arraste em um único ajuste manual, sem fixar a fila inteira.
    if (!presentationId && Array.isArray(body.ids)) {
      const current = q.queue.map(x => x.id);
      const desired = body.ids.map(text);
      if (desired.length !== current.length || new Set(desired).size !== current.length || desired.some(x => !current.includes(x))) throw new Error('A fila mudou. Atualize o painel e tente novamente.');
      outer: for (const candidate of current) {
        const rest = current.filter(x => x !== candidate);
        for (let target = 0; target < current.length; target++) {
          const attempt = rest.slice(); attempt.splice(target, 0, candidate);
          if (attempt.every((x, i) => x === desired[i])) { presentationId = candidate; position = target + 1; break outer; }
        }
      }
    }
    if (!presentationId || !Number.isInteger(position) || position < 1) throw new Error('Não foi possível identificar a apresentação movida.');
    const { data, error } = await db().rpc('bj_queue_pin_position', { p_event_id: event.id, p_presentation_id: presentationId, p_position: position, p_actor: admin.display_name });
    if (error) throw error; return { ok: true, ...(await adminQueue(event)), result: data };
  }
  if (action === 'admin.queue.auto') {
    const event = await eventForPublic(); if (!event) throw new Error('Não existe evento ativo.');
    // Reativa o rodízio para as inscrições sem prioridade manual; não apaga os ajustes já feitos.
    const { error } = await db().rpc('bj_queue_auto', { p_event_id: event.id, p_actor: admin.display_name });
    if (error) throw error; return { ok: true, ...(await adminQueue(event)) };
  }
  if (action === 'admin.queue.unpin') {
    const event = await eventForPublic(); if (!event) throw new Error('Não existe evento ativo.');
    const { data, error } = await db().rpc('bj_queue_unpin_position', { p_event_id: event.id, p_presentation_id: text(body.id), p_actor: admin.display_name });
    if (error) throw error; return { ok: true, ...(await adminQueue(event)), result: data };
  }
  if (action === 'admin.queue.startNext') {
    const event = await eventForPublic(); if (!event) throw new Error('Não existe evento ativo.');
    const q = await adminQueue(event); if (q.current) throw new Error('Já existe uma apresentação tocando agora.');
    const next = q.queue[0]; if (!next) throw new Error('Não há apresentações aguardando.');
    const { error } = await db().rpc('bj_presentation_action', { p_action: 'START', p_presentation_id: next.id, p_actor: admin.display_name });
    if (error) throw error; return { ok: true, ...(await adminQueue(event)), dashboard: await dashboard() };
  }
  if (action === 'admin.queue.move') {
    const event = await eventForPublic(); if (!event) throw new Error('Não existe evento ativo.');
    const q = await adminQueue(event);
    if (!q.queue.some(x => x.id === text(body.id))) throw new Error('Apresentação não encontrada na fila.');
    const requestedPosition = Number(body.position);
    if (!Number.isInteger(requestedPosition) || requestedPosition < 1) throw new Error('Informe uma posição válida.');
    const { error } = await db().rpc('bj_queue_pin_position', { p_event_id: event.id, p_presentation_id: text(body.id), p_position: requestedPosition, p_actor: admin.display_name });
    if (error) throw error; return { ok: true, ...(await adminQueue(event)) };
  }
  if (action === 'admin.presentation.action') {
    const op = String(body.operation || '').toUpperCase();
    if (!['START', 'SUNG', 'CANCEL'].includes(op)) throw new Error('Operação inválida.');
    if (op === 'CANCEL' && body.confirmed !== true) throw new Error('Confirme o cancelamento.');
    const { data, error } = await db().rpc('bj_presentation_action', { p_action: op, p_presentation_id: text(body.id), p_actor: admin.display_name });
    if (error) throw error; const event = await eventForPublic(); return { ok: true, result: data, ...(await adminQueue(event)), dashboard: await dashboard() };
  }
  if (action === 'admin.presentation.edit') {
    const presentationId = text(body.id); const p1 = text(body.p1); const p2 = text(body.p2); const p3 = text(body.p3); const song = text(body.song);
    if (p1.length < 2 || p1.length > 70 || song.length < 2 || song.length > 150) throw new Error('Confira o nome do participante e da música.');
    const names = [p1, p2, p3].filter(Boolean); if (new Set(names.map(norm)).size !== names.length) throw new Error('Não repita participantes.');
    const { data: old, error: oe } = await db().from('presentations').select('id,event_id').eq('id', presentationId).single();
    if (oe) throw oe;
    const { data: edited, error: editError } = await db().rpc('bj_edit_presentation', { p_presentation_id: presentationId, p_p1: p1, p_p2: p2 || null, p_p3: p3 || null, p_song: song, p_actor: admin.display_name });
    if (editError) throw editError;
    const event = await eventForPublic(); return { ok: true, edited, ...(await adminQueue(event)) };
  }

  if (action === 'admin.raffle.start') {
    const event = await eventForPublic(); const result = await raffleDraw(event, body.count, admin); return result;
  }
  if (action === 'admin.raffle.cancel') {
    const event = await eventForPublic(); if (!event) throw new Error('Não existe evento ativo.');
    const { data, error } = await db().from('raffles').update({ status: 'CANCELLED' }).eq('event_id', event.id).eq('status', 'RUNNING').select('id').single();
    if (error) throw error; await audit(admin.display_name, 'RAFFLE_CANCELLED', { raffle_id: data.id }, event.id); return { ok: true };
  }
  if (action === 'admin.raffle.history') {
    const event = await eventForPublic(); if (!event) return { ok: true, raffles: [] };
    const { data, error } = await db().from('raffles').select('id,status,requested_winners,created_at,reveal_at,results_ready').eq('event_id', event.id).order('created_at', { ascending: false }).limit(20);
    if (error) throw error;
    const ids = (data || []).map(x => x.id); const { data: winners, error: we } = ids.length ? await db().from('raffle_winners').select('raffle_id,participant_name,song,table_number,position').in('raffle_id', ids).order('position') : { data: [], error: null };
    if (we) throw we;
    return { ok: true, raffles: (data || []).map(r => ({ ...r, winners: (winners || []).filter(w => w.raffle_id === r.id) })) };
  }

  if (action === 'admin.history') {
    const eventId = text(body.eventId);
    let query = db().from('presentations').select('id,event_id,table_id,table_number,tab_number,p1,p2,p3,song,sung_at').eq('status', 'SUNG').order('sung_at', { ascending: false, nullsFirst: false }).limit(1000);
    if (eventId) query = query.eq('event_id', eventId);
    const { data: presentations, error } = await query; if (error) throw error;
    const ids = (presentations || []).map(p => p.id);
    const { data: people, error: peopleError } = ids.length
      ? await db().from('participants').select('id,event_id,presentation_id,name,external_registered_at,external_registered_by,created_at').in('presentation_id', ids).order('created_at', { ascending: true })
      : { data: [], error: null };
    if (peopleError) throw peopleError;
    const byPresentation = new Map();
    for (const person of people || []) {
      if (!byPresentation.has(person.presentation_id)) byPresentation.set(person.presentation_id, []);
      byPresentation.get(person.presentation_id).push(person);
    }
    const rows = [];
    for (const presentation of presentations || []) {
      const members = byPresentation.get(presentation.id) || [];
      if (members.length) {
        for (const person of members) rows.push({
          id: person.id, presentation_id: presentation.id, event_id: presentation.event_id,
          table_number: presentation.table_number, tab_number: presentation.tab_number,
          name: person.name, song: presentation.song, sung_at: presentation.sung_at,
          external_registered_at: person.external_registered_at,
          external_registered_by: person.external_registered_by, markable: true
        });
      } else {
        // Compatibilidade com históricos antigos que ainda não tenham linhas em participants.
        for (const name of [presentation.p1, presentation.p2, presentation.p3].filter(Boolean)) rows.push({
          id: null, presentation_id: presentation.id, event_id: presentation.event_id,
          table_number: presentation.table_number, tab_number: presentation.tab_number,
          name, song: presentation.song, sung_at: presentation.sung_at,
          external_registered_at: null, external_registered_by: null, markable: false
        });
      }
    }
    return { ok: true, presentations: rows };
  }
  if (action === 'admin.history.mark') {
    const participantId = text(body.participantId);
    if (!participantId) throw new Error('Participante não informado.');
    const { data: person, error: personError } = await db().from('participants')
      .select('id,event_id,presentation_id,name').eq('id', participantId).single();
    if (personError) throw personError;
    const { data: presentation, error: presentationError } = await db().from('presentations')
      .select('id,event_id,status').eq('id', person.presentation_id).single();
    if (presentationError) throw presentationError;
    if (presentation.status !== 'SUNG' || presentation.event_id !== person.event_id) {
      throw new Error('Só é possível marcar participantes de apresentações já cantadas.');
    }
    const registered = body.registered === true;
    const changes = registered
      ? { external_registered_at: new Date().toISOString(), external_registered_by: admin.display_name }
      : { external_registered_at: null, external_registered_by: null };
    const { data, error } = await db().from('participants').update(changes).eq('id', participantId)
      .select('id,external_registered_at,external_registered_by').single();
    if (error) throw error;
    await audit(admin.display_name, registered ? 'HISTORY_EXTERNAL_REGISTERED' : 'HISTORY_EXTERNAL_UNREGISTERED',
      { participant_id: participantId, participant_name: person.name }, person.event_id);
    return { ok: true, participant: data };
  }
  if (action === 'admin.admins.list') {
    const { data, error } = await db().from('admins').select('id,display_name,role,active,created_at').order('created_at');
    if (error) throw error; return { ok: true, admins: data || [] };
  }
  if (action === 'admin.admins.create') {
    const role = String(body.role || '').toUpperCase(); const password = String(body.password || '');
    if (!['ADMIN', 'COLLABORATOR'].includes(role)) throw new Error('Perfil inválido.');
    if (password.length < 10) throw new Error('A senha deve ter pelo menos 10 caracteres.');
    const { data: existing, error } = await db().from('admins').select('id,role,password_hash').eq('active', true);
    if (error) throw error;
    if (role === 'ADMIN' && existing.filter(x => ['OWNER', 'ADMIN'].includes(x.role)).length >= 2) throw new Error('Os dois perfis com acesso total já foram criados.');
    if (role === 'COLLABORATOR' && existing.filter(x => x.role === 'COLLABORATOR').length >= 1) throw new Error('O perfil de colaborador já existe.');
    for (const x of existing) if (await verifyPassword(password, x.password_hash)) throw new Error('Escolha uma senha diferente das demais.');
    const display_name = role === 'ADMIN' ? 'Administrador 2' : 'Colaborador';
    const { data, error: ie } = await db().from('admins').insert({ display_name, role, password_hash: await hashPassword(password), active: true }).select('id,display_name,role,active').single();
    if (ie) throw ie; await audit(admin.display_name, 'ADMIN_CREATED', { display_name, role }); return { ok: true, admin: data };
  }
  if (action === 'admin.admins.rename') {
    const targetId = text(body.id);
    const displayName = text(body.displayName);
    if (!targetId) throw new Error('Selecione o perfil que deseja renomear.');
    if (displayName.length < 2 || displayName.length > 60) throw new Error('O nome deve ter entre 2 e 60 caracteres.');
    const { data, error } = await db().from('admins').update({ display_name: displayName })
      .eq('id', targetId).select('id,display_name,role,active,created_at').single();
    if (error) throw error;
    await audit(admin.display_name, 'ADMIN_NAME_CHANGED', { admin_id: targetId, display_name: displayName });
    return { ok: true, admin: data };
  }
  if (action === 'admin.admins.password') {
    const password = String(body.password || ''); if (password.length < 10) throw new Error('A senha deve ter pelo menos 10 caracteres.');
    const { error } = await db().from('admins').update({ password_hash: await hashPassword(password) }).eq('id', text(body.id));
    if (error) throw error; await audit(admin.display_name, 'ADMIN_PASSWORD_CHANGED', { admin_id: text(body.id) }); return { ok: true };
  }
  if (action === 'admin.admins.active') {
    if (text(body.id) === admin.id) throw new Error('Não é possível desativar sua própria sessão.');
    const { error } = await db().from('admins').update({ active: Boolean(body.active) }).eq('id', text(body.id));
    if (error) throw error; await audit(admin.display_name, 'ADMIN_STATUS_CHANGED', { admin_id: text(body.id), active: Boolean(body.active) }); return { ok: true };
  }
  if (action === 'admin.settings.get') {
    const { data, error } = await db().from('settings').select('key,value'); if (error) throw error;
    return { ok: true, settings: Object.fromEntries((data || []).map(x => [x.key, x.value])) };
  }
  if (action === 'admin.settings.save') {
    const key = text(body.key); if (!['public_base_url', 'event_name_default', 'raffle_trigger_count'].includes(key)) throw new Error('Configuração não permitida.');
    let value = body.value;
    if (key === 'public_base_url') {
      let parsed; try { parsed = new URL(String(value)); } catch { throw new Error('URL pública inválida.'); }
      if (!['https:', 'http:'].includes(parsed.protocol)) throw new Error('A URL pública precisa usar HTTP ou HTTPS.');
      value = parsed.origin.replace(/\/$/, '');
    }
    if (key === 'raffle_trigger_count') { value = Number(value); if (!Number.isInteger(value) || value < 0 || value > 10000) throw new Error('A quantidade mínima de músicas deve ser um número entre 0 e 10000.'); }
    const { error } = await db().from('settings').upsert({ key, value }, { onConflict: 'key' }); if (error) throw error;
    await audit(admin.display_name, 'SETTING_UPDATED', { key }); return { ok: true };
  }
  throw new Error('Ação administrativa desconhecida.');
}

export default async function handler(req) {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: HEADERS });
  if (req.method !== 'POST') return json(405, { ok: false, error: 'Método não permitido.' });
  try {
    const body = await req.json(); const action = text(body.action);
    if (!action) return json(400, { ok: false, error: 'Ação não informada.' });
    if (action === 'health') {
      const { error } = await db().from('events').select('id').limit(1);
      if (error) throw error; return json(200, { ok: true, service: 'blackjack-karaoke-v2' });
    }
    if (action === 'public.status') return json(200, await publicStatus(body.token));
    if (action === 'public.screenStatus') return json(200, await screenStatus());
    if (action === 'public.lookupTab') return json(200, await lookupTab(body.token, body.tab));
    if (action === 'public.identifyTab') return json(200, await identifyTab(body));
    if (action === 'public.register') return json(200, await registerPresentation(body));
    if (action.startsWith('admin.')) return json(200, await handleAdmin(action, body, req));
    return json(404, { ok: false, error: 'Ação não encontrada.' });
  } catch (error) {
    const message = error?.message || 'Erro interno na operação.';
    const status = /sessão|senha|permissão|perfil/i.test(message) ? 401 : 400;
    return json(status, { ok: false, error: message });
  }
}
