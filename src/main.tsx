import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import App from './App'
import { attivaAggiornamentoAutomatico } from './lib/aggiornamentoAutomatico'
import './styles.css'

if ('serviceWorker' in navigator && import.meta.env.PROD) {
  window.addEventListener('load', () => navigator.serviceWorker.register('/sw.js'))
}

if (import.meta.env.PROD) attivaAggiornamentoAutomatico()

// Diagnosi schermo (iPhone Duo, 23/11/2026): con ?schermo nell'indirizzo mostra misure e margini di sicurezza.
if (new URLSearchParams(location.search).has('schermo')) {
  window.addEventListener('load', () => {
    const sonda = document.createElement('div')
    sonda.className = 'misura-schermo__sonda'
    document.body.appendChild(sonda)
    const riquadro = document.createElement('div')
    riquadro.className = 'misura-schermo'
    riquadro.onclick = () => riquadro.remove()
    const aggiorna = () => {
      const st = getComputedStyle(sonda)
      riquadro.textContent = [
        `finestra: ${innerWidth} x ${innerHeight}`,
        `schermo: ${screen.width} x ${screen.height} @${devicePixelRatio}x`,
        `margine alto: ${st.paddingTop}`,
        `margine destro: ${st.paddingRight}`,
        `margine basso: ${st.paddingBottom}`,
        `margine sinistro: ${st.paddingLeft}`,
        `app installata: ${matchMedia('(display-mode: standalone)').matches ? 'sì' : 'no'}`,
        '(tocca per chiudere)',
      ].join('\n')
    }
    aggiorna()
    document.body.appendChild(riquadro)
    addEventListener('resize', aggiorna)
  })
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
