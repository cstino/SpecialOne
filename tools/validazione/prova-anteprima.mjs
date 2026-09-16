// Esegue DAVVERO il JS dell'anteprima con un DOM finto, invece di limitarsi a
// controllarne la sintassi: e' cosi' che si scopre un REPARTO non definito.
import { readFileSync } from 'fs';
const s = readFileSync(process.argv[2], 'utf8');
const js = s.slice(s.indexOf('<script>') + 8, s.lastIndexOf('</script>'));
const nodo = () => ({ style:{}, dataset:{}, classList:{ toggle(){}, add(){}, remove(){} },
  setAttribute(){}, appendChild(){}, remove(){}, querySelectorAll:()=>[], getBoundingClientRect:()=>({left:0,top:0,width:400,height:548}),
  set textContent(v){}, get textContent(){return ''}, set innerHTML(v){}, set onclick(v){}, set hidden(v){} });
const doc = { querySelector:()=>nodo(), querySelectorAll:()=>[], getElementById:()=>nodo(), createElement:()=>nodo(), body:nodo() };
const f = new Function('document','window', js + '\nreturn { SPOST, REPARTO, compLabel, ancoreLegali, MODULI, posti, nomeSchieramento };');
const m = f(doc, { addEventListener(){}, removeEventListener(){} });

let ko = 0;
for (const [k, v] of Object.entries(m.SPOST)) for (const x of v)
  if (m.REPARTO[x] !== m.REPARTO[k]) { console.log('  LINEA CAMBIATA: ' + k + ' -> ' + x); ko++ }
console.log(ko ? '  ' + ko + ' spostamenti illegali' : '  nessuno spostamento cambia linea');
console.log('  ST puo diventare:', m.SPOST.ST.join(', '));
for (const sl of ['CB','CM','ST'])
  console.log('  compito difensivo, ' + sl + ':', m.compLabel(sl,'difesa')[0], '(fiato x' + m.compLabel(sl,'difesa')[2] + ')');
console.log('  postazioni legali per un ST del 4-4-2:', m.ancoreLegali(9).map(a=>a.id).join(', '));

console.log('  nome derivato:');
for (const [nome, sl] of Object.entries(m.MODULI))
  console.log('    ' + nome.padEnd(18) + ' -> ' + m.nomeSchieramento(sl));
console.log('    ' + '4-4-2 coi due CDM'.padEnd(18) + ' -> '
  + m.nomeSchieramento(['GK','LB','CB','CB','RB','LM','CDM','CDM','RM','ST','ST']));
