import { useEffect, useState } from 'react'

export function useOraCorrente() {
  const [ora, setOra] = useState(Date.now())
  useEffect(() => {
    const timer = window.setInterval(() => setOra(Date.now()), 1000)
    return () => window.clearInterval(timer)
  }, [])
  return ora
}

export function formatCountdown(millisecondi: number) {
  const secondi = Math.max(0, Math.floor(millisecondi / 1000))
  const ore = Math.floor(secondi / 3600)
  const minuti = Math.floor((secondi % 3600) / 60)
  const restanti = secondi % 60
  return `${String(ore).padStart(2, '0')}:${String(minuti).padStart(2, '0')}:${String(restanti).padStart(2, '0')}`
}
