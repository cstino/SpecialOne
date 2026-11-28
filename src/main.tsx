import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import App from './App'
import { attivaAggiornamentoAutomatico } from './lib/aggiornamentoAutomatico'
import './styles.css'

if ('serviceWorker' in navigator && import.meta.env.PROD) {
  window.addEventListener('load', () => navigator.serviceWorker.register('/sw.js'))
}

if (import.meta.env.PROD) attivaAggiornamentoAutomatico()

// Diagnosi schermo (iPhone Duo, 23/11/2026): mostra misure e margini di sicurezza.
// Si apre con ?schermo nell'indirizzo oppure, dall'app installata (che non ha la barra
// degli indirizzi), toccando 5 volte di fila la scritta «S1 · BETA» in fondo al menu
// o il nome della lega nella barra in alto (il menu in verticale puo' essere irraggiungibile).
function mostraMisuraSchermo() {
  if (document.querySelector('.misura-schermo')) return
  const sonda = document.createElement('div')
  sonda.className = 'misura-schermo__sonda'
  document.body.appendChild(sonda)
  const riquadro = document.createElement('div')
  riquadro.className = 'misura-schermo'
  const aggiorna = () => {
    const st = getComputedStyle(sonda)
    const vv = window.visualViewport
    const menu = document.querySelector('.game-sidebar')?.getBoundingClientRect()
    riquadro.textContent = [
      `finestra: ${innerWidth} x ${innerHeight}`,
      `area visibile: ${vv ? `${Math.round(vv.width)} x ${Math.round(vv.height)} (scala ${vv.scale})` : '-'}`,
      `pagina: ${document.documentElement.clientWidth} x ${document.documentElement.clientHeight}`,
      `schermo: ${screen.width} x ${screen.height} @${devicePixelRatio}x`,
      `orientamento: ${screen.orientation?.type ?? '-'}`,
      `margine alto: ${st.paddingTop}`,
      `margine destro: ${st.paddingRight}`,
      `margine basso: ${st.paddingBottom}`,
      `margine sinistro: ${st.paddingLeft}`,
      `menu laterale: ${menu && menu.width ? `${Math.round(menu.width)} x ${Math.round(menu.height)} da y ${Math.round(menu.top)}` : 'nascosto'}`,
      `app installata: ${matchMedia('(display-mode: standalone)').matches ? 'sì' : 'no'}`,
      navigator.userAgent,
      '(tocca per chiudere)',
    ].join('\n')
  }
  riquadro.onclick = () => { riquadro.remove(); sonda.remove(); removeEventListener('resize', aggiorna) }
  aggiorna()
  document.body.appendChild(riquadro)
  addEventListener('resize', aggiorna)
}
if (new URLSearchParams(location.search).has('schermo')) window.addEventListener('load', mostraMisuraSchermo)
{
  let tocchi = 0
  let ultimo = 0
  document.addEventListener('click', (evento) => {
    const bersaglio = evento.target as Element | null
    if (!bersaglio?.closest?.('.game-version, .game-drawer > footer small, .game-mobilebar__league')) return
    const adesso = Date.now()
    tocchi = adesso - ultimo < 800 ? tocchi + 1 : 1
    ultimo = adesso
    if (tocchi >= 5) { tocchi = 0; mostraMisuraSchermo() }
  })
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
