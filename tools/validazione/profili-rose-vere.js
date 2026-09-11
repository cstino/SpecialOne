// ============================================================
//  I PROFILI TATTICI ESISTONO DAVVERO DENTRO LE ROSE VERE?
//  Sola lettura sul database di produzione. Eseguire con:
//    node tools/validazione/profili-rose-vere.js
//
//  PERCHE' ESISTE
//  leve-tattiche.sql ha misurato i profili sul CATALOGO (5.416 giocatori).
//  Ma nessuno gioca col catalogo: si gioca con 25 giocatori usciti dal draft.
//  Se dentro un singolo undici i profili fossero schiacciati, la leva
//  "scegliere gli interpreti giusti" non esisterebbe, e il sistema tattico
//  perderebbe meta' del suo senso. Questo script lo verifica sul campo.
//
//  ATTENZIONE ALLA SCELTA DELLA LEGA (11 settembre 2026)
//  LegaBot e' alla stagione 4 e quasi tutte le squadre sono controllate dal
//  PC, che non ha rinnovato i contratti: le rose si sono impoverite e NON
//  sono un campione valido. Si vede nei numeri — nel centrocampo dei bot
//  l'ampiezza del profilo scende da 34.7 a 24.7 e il costo in overall da 4.0
//  a 0.7 punti: su rose degradate il profilo e' quasi gratis e il dilemma
//  tattico sparisce. Usare sempre leghe umane di stagione 1.
//
//  LE TRE COSE CHE MISURA, per reparto:
//    ampiezza     p10-p90 del profilo fra i candidati di quella squadra.
//                 Sotto 20 non c'e' scelta: sono tutti uguali.
//    correlazione profilo contro overall. Lontano da 0 significa che
//                 "prendi chi ha il profilo" e "prendi chi e' piu' forte"
//                 sono la stessa frase, e la tattica non decide niente.
//    costo        quanto overall si perde schierando i piu' profilati invece
//                 dei piu' forti. E' il prezzo del piano, e non va aggiunto
//                 al modello: il motore lo applica gia' da solo, perche' una
//                 difesa veloce ma debole ha un DEF piu' basso in forzeLinee.
// ============================================================

import { sel } from './_db-produzione.js';
import { REPARTO } from '/Users/cristianobraccili/SpecialOne/engine/config.js';

const A = k => o => Number(o?.[k] ?? NaN);
const media = a => a.reduce((x,y)=>x+y,0)/a.length;
const pct = (a,q) => { const s=[...a].sort((x,y)=>x-y); return s[Math.min(s.length-1, Math.floor(q*s.length))]; };
const corr = (x,y) => { const mx=media(x),my=media(y);
  const sxy=x.reduce((s,v,i)=>s+(v-mx)*(y[i]-my),0), sx=Math.sqrt(x.reduce((s,v)=>s+(v-mx)**2,0)), sy=Math.sqrt(y.reduce((s,v)=>s+(v-my)**2,0));
  return sx&&sy ? sxy/(sx*sy) : 0; };

// i due profili, esattamente come definiti in leve-tattiche.sql
const tecnico = a => (A('short_passing')(a)+A('skill_long_passing')(a)+A('mentality_vision')(a)+A('skill_ball_control')(a))/4
                   - (A('power_strength')(a)+A('standing_tackle')(a)+A('mentality_interceptions')(a)+A('mentality_aggression')(a))/4;
const rapido  = a => A('pace')(a) - A('physic')(a);

async function carica(lid) {
  const squadre = await sel('teams', `select=id,nome,controllata_da_pc&league_id=eq.${lid}&limit=40`);
  const ids = squadre.map(s=>s.id);
  const pi = await sel('player_instances',
    `select=team_id,player_id,overall_corrente,posizioni_override,attributi_override&team_id=in.(${ids.join(',')})&limit=2000`);
  const pids = [...new Set(pi.map(p=>p.player_id))];
  const cat = new Map();
  for (let i=0;i<pids.length;i+=400) {
    for (const p of await sel('players', `select=id,posizioni,attributi&id=in.(${pids.slice(i,i+400).join(',')})&limit=500`)) cat.set(p.id, p);
  }
  return squadre.map(s => ({ ...s, rosa: pi.filter(p=>p.team_id===s.id).map(p => {
    const base = cat.get(p.player_id); if (!base) return null;
    const att = { ...(base.attributi||{}), ...(p.attributi_override||{}) };
    const pos = p.posizioni_override || base.posizioni;
    if (att.movement_sprint_speed == null) return null;
    return { ovr: p.overall_corrente, rep: REPARTO[(Array.isArray(pos)?pos:[pos])[0]],
             tecnico: tecnico(att), rapido: rapido(att) };
  }).filter(Boolean) }));
}

for (const [lid, nome] of [[63,'Serie F (st.1, umane)'], [37,'Real Fampionato (st.1, umane)'], [62,'LegaBot (st.4, quasi tutte bot)']]) {
  const sq = (await carica(lid)).filter(s=>s.rosa.length>=15);
  console.log(`\n${'='.repeat(78)}\n${nome} — ${sq.length} rose\n${'='.repeat(78)}`);
  for (const [prof, rep, quanti] of [['rapido','DEF',4], ['tecnico','MID',3], ['rapido','ATT',3]]) {
    // per ogni squadra: ampiezza del profilo fra i candidati di quel reparto,
    // e quanto overall costa schierare i piu' profilati invece dei piu' forti
    const amp = [], costo = [], tuttiT = [], tuttiO = [];
    for (const s of sq) {
      const c = s.rosa.filter(g=>g.rep===rep);
      if (c.length < quanti+1) continue;
      amp.push(pct(c.map(g=>g[prof]),0.9) - pct(c.map(g=>g[prof]),0.1));
      const forti = [...c].sort((a,b)=>b.ovr-a.ovr).slice(0,quanti);
      const prof_ = [...c].sort((a,b)=>b[prof]-a[prof]).slice(0,quanti);
      costo.push(media(forti.map(g=>g.ovr)) - media(prof_.map(g=>g.ovr)));
      for (const g of c) { tuttiT.push(g[prof]); tuttiO.push(g.ovr); }
    }
    if (!amp.length) continue;
    console.log(`  profilo "${prof}" nel reparto ${rep}  (${quanti} titolari, ${tuttiT.length} candidati)`);
    console.log(`     ampiezza p10-p90 dentro la rosa : ${media(amp).toFixed(1).padStart(5)}   (serve >= 20 perche' ci sia scelta)`);
    console.log(`     correlazione profilo/overall    : ${corr(tuttiT,tuttiO).toFixed(2).padStart(5)}   (serve ~0 perche' sia una decisione)`);
    console.log(`     costo in overall del profilo    : ${media(costo).toFixed(1).padStart(5)} punti`);
  }
}
