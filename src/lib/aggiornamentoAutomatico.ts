// Un'app installata sulla home puo' restare aperta in memoria per giorni
// senza ricaricarsi mai: chi non la chiude resta su una versione vecchia, e
// quando il server cambia formato qualcosa si rompe (successo col training il
// 1 ottobre 2026). Quando l'app torna in primo piano si confronta il bundle
// caricato con quello che index.html indica adesso: se e' cambiato, si
// ricarica. Lo stato di gioco e' tutto su Supabase, non si perde niente.
const BUNDLE = /\/assets\/index-[\w-]+\.js/

function bundleCaricato() {
  const script = document.querySelector<HTMLScriptElement>('script[type="module"][src*="/assets/index-"]')
  return script?.src.match(BUNDLE)?.[0] ?? null
}

export function attivaAggiornamentoAutomatico() {
  const attuale = bundleCaricato()
  if (!attuale) return
  let inVerifica = false

  async function verifica() {
    if (inVerifica || document.visibilityState !== 'visible' || !navigator.onLine) return
    inVerifica = true
    try {
      const risposta = await fetch(`/?v=${Date.now()}`, { cache: 'no-store' })
      if (!risposta.ok) return
      const online = (await risposta.text()).match(BUNDLE)?.[0]
      if (online && online !== attuale) window.location.reload()
    } catch {
      // Rete assente o instabile: si riprova al prossimo ritorno in primo piano.
    } finally {
      inVerifica = false
    }
  }

  document.addEventListener('visibilitychange', () => { void verifica() })
  window.addEventListener('focus', () => { void verifica() })
}
