import { createClient } from '@supabase/supabase-js';
import crypto from 'node:crypto';

const db = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false }
});
const headers = {
  'content-type':'application/json; charset=utf-8',
  'cache-control':'no-store',
  'access-control-allow-origin':'*',
  'access-control-allow-headers':'content-type,authorization',
  'access-control-allow-methods':'POST,OPTIONS'
};
const reply=(status,body)=>new Response(JSON.stringify(body),{status,headers});
const norm=s=>String(s||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').trim().replace(/\s+/g,' ').toLocaleLowerCase('pt-BR');
const safe=s=>String(s||'').replace(/[\u0000-\u001f\u007f]/g,'').trim();
async function activeEvent(){
 const {data,error}=await db.from('events').select('*').in('status',['OPEN','REGISTRATION_CLOSED']).order('created_at',{ascending:false}).limit(1).maybeSingle();
 if(error) throw error; return data;
}
async function log(event_id,actor,action,details={}){await db.from('audit_logs').insert({event_id,actor,action,details});}
async function publicStatus(token){
 const {data:table,error:te}=await db.from('dining_tables').select('id,number,active').eq('token',token).maybeSingle();
 if(te||!table||!table.active) return {ok:false,error:'Mesa inválida ou desativada.'};
 const ev=await activeEvent(); if(!ev)return {ok:true,table:table.number,event:null,open:false,available:0,capacity:0};
 const {data:rows,error}=await db.from('presentations').select('id,table_number,p1,p2,p3,song,status,created_at,started_at,sung_at,manual_rank').eq('event_id',ev.id).order('created_at');
 if(error)throw error;
 const pending=rows.filter(x=>['PENDING','PLAYING'].includes(x.status));
 const sung=rows.filter(x=>x.status==='SUNG').sort((a,b)=>new Date(b.sung_at)-new Date(a.sung_at));
 const current=pending.find(x=>x.status==='PLAYING')||null;
 const queue=pending.filter(x=>x.status!=='PLAYING').sort((a,b)=>{
  if(a.manual_rank!=null&&b.manual_rank!=null)return a.manual_rank-b.manual_rank;
  if(a.manual_rank!=null)return -1;if(b.manual_rank!=null)return 1;
  return new Date(a.created_at)-new Date(b.created_at);
 });
 const used=rows.filter(x=>['PENDING','PLAYING','SUNG'].includes(x.status)).length;
 return {ok:true,table:table.number,event:ev.name,status:ev.status,open:ev.status==='OPEN',capacity:ev.capacity,available:Math.max(0,ev.capacity-used),last:sung[0]||null,current,next:queue[0]||null};
}
async function register(payload){
 const token=safe(payload.token).toLowerCase(), tab=safe(payload.tab).toUpperCase();
 const p1=safe(payload.p1), p2=safe(payload.p2), p3=safe(payload.p3), song=safe(payload.song);
 const requestId=safe(payload.requestId);
 if(!/^[a-z0-9]{32}$/.test(token))throw new Error('QR Code inválido.');
 if(!/^[A-Z0-9]{1,10}$/.test(tab))throw new Error('Informe uma comanda válida (até 10 caracteres).');
 if(!p1||!song||song.length>150)throw new Error('Informe participante principal e música.');
 if(new Set([p1,p2,p3].filter(Boolean).map(norm)).size!==[p1,p2,p3].filter(Boolean).length)throw new Error('Não repita participantes na mesma apresentação.');
 if(!requestId)throw new Error('Identificador da solicitação ausente.');
 const {data:table}=await db.from('dining_tables').select('*').eq('token',token).eq('active',true).maybeSingle();
 if(!table)throw new Error('Mesa inválida ou desativada.');
 const ev=await activeEvent();if(!ev||ev.status!=='OPEN')throw new Error('Inscrições fechadas.');
 const {data:release}=await db.from('tab_releases').select('enabled').eq('event_id',ev.id).eq('tab_number',tab).maybeSingle();
 if(!release?.enabled)throw new Error('Sua comanda não está liberada. Consulte os responsáveis.');
 const {data:old}=await db.from('event_tabs').select('*').eq('event_id',ev.id).eq('tab_number',tab).maybeSingle();
 if(old && norm(old.participant_name)!==norm(p1))throw new Error('Esta comanda já está cadastrada com outro nome. Procure um responsável.');
 if(!old){const {error}=await db.from('event_tabs').insert({event_id:ev.id,tab_number:tab,participant_name:p1,normalized_name:norm(p1)});if(error)throw error;}
 const {data:dup}=await db.from('presentations').select('id').eq('event_id',ev.id).eq('request_id',requestId).maybeSingle();
 if(dup)return {ok:true,id:dup.id,duplicate:true};
 const names=[p1,p2,p3].filter(Boolean);
 // Serialização transacional real deve ser aplicada pela RPC SQL no pacote final de implantação.
 const {data:busy}=await db.from('participants').select('normalized_name').eq('event_id',ev.id).eq('table_id',table.id).in('normalized_name',names.map(norm));
 if(busy?.length)throw new Error('Um dos participantes já possui apresentação pendente.');
 const {count}=await db.from('presentations').select('id',{count:'exact',head:true}).eq('event_id',ev.id).in('status',['PENDING','PLAYING','SUNG']);
 if((count||0)>=ev.capacity)throw new Error('Capacidade da noite esgotada.');
 const id='A-'+crypto.randomBytes(6).toString('hex').toUpperCase();
 const {error:pe}=await db.from('presentations').insert({id,event_id:ev.id,table_id:table.id,table_number:table.number,tab_number:tab,p1,p2:p2||null,p3:p3||null,song,request_id:requestId});
 if(pe)throw pe;
 await db.from('participants').insert(names.map(n=>({event_id:ev.id,presentation_id:id,table_id:table.id,name:n,normalized_name:norm(n)})));
 await log(ev.id,'cliente','RESERVA',{presentation_id:id,table:table.number,song});
 return {ok:true,id};
}
export default async (req)=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return reply(405,{ok:false,error:'Método não permitido.'});
 try{
  if(!process.env.SUPABASE_URL||!process.env.SUPABASE_SERVICE_ROLE_KEY)throw new Error('Banco ainda não configurado no ambiente Netlify.');
  const body=await req.json(), action=body.action;
  if(action==='public.status')return reply(200,await publicStatus(safe(body.token)));
  if(action==='public.register')return reply(200,await register(body));
  if(action==='health'){const {error}=await db.from('events').select('id').limit(1);if(error)throw error;return reply(200,{ok:true,service:'blackjack-v2'});}
  return reply(404,{ok:false,error:'Ação ainda não habilitada nesta etapa.'});
 }catch(e){return reply(400,{ok:false,error:e.message||'Erro interno.'});}
};
