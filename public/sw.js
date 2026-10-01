self.addEventListener('install', () => self.skipWaiting())
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()))

// Mostra la push: il payload arriva da supabase/functions/invia-push,
// stessa forma di una riga di public.notifications (titolo/corpo/tipo/dati).
self.addEventListener('push', (event) => {
  if (!event.data) return
  let payload
  try { payload = event.data.json() } catch { return }
  const dati = payload.dati || {}
  event.waitUntil(
    self.registration.showNotification(payload.titolo || 'SpecialOne', {
      body: payload.corpo || '',
      icon: '/specialone-icon-192.png',
      badge: '/specialone-icon-192.png',
      tag: dati.notification_id ? `notifica-${dati.notification_id}` : undefined,
      data: dati,
    }),
  )
})

// Un tocco sulla notifica porta all'app gia' aperta (e le passa dove
// andare, come fa la campanella in-app) oppure ne apre una nuova, con i dati
// della notifica nell'indirizzo: App.tsx li legge all'avvio e va nello stesso
// posto (per una partita non ancora vista, l'intro).
self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  const dati = event.notification.data || {}
  event.waitUntil((async () => {
    const clientList = await self.clients.matchAll({ type: 'window', includeUncontrolled: true })
    for (const client of clientList) {
      if ('focus' in client) {
        client.postMessage({ tipo: 'notifica-push-click', dati })
        return client.focus()
      }
    }
    return self.clients.openWindow(`/?notifica=${encodeURIComponent(JSON.stringify(dati))}`)
  })())
})
