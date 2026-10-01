import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import App from './App'
import { attivaAggiornamentoAutomatico } from './lib/aggiornamentoAutomatico'
import './styles.css'

if ('serviceWorker' in navigator && import.meta.env.PROD) {
  window.addEventListener('load', () => navigator.serviceWorker.register('/sw.js'))
}

if (import.meta.env.PROD) attivaAggiornamentoAutomatico()

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
