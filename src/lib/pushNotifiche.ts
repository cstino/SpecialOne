import { supabase } from './supabase'

const VAPID_PUBLIC_KEY = import.meta.env.VITE_VAPID_PUBLIC_KEY as string | undefined

export function pushSupportata() {
  return typeof window !== 'undefined' && 'serviceWorker' in navigator && 'PushManager' in window && !!VAPID_PUBLIC_KEY
}

export function permessoPush(): NotificationPermission | 'non-supportato' {
  if (!pushSupportata()) return 'non-supportato'
  return Notification.permission
}

// L'API Push vuole la chiave VAPID come Uint8Array, non come stringa: stesso
// helper standard che si trova in ogni guida Web Push (RFC 4648 base64url).
function base64UrlAUint8Array(base64Url: string) {
  const padding = '='.repeat((4 - (base64Url.length % 4)) % 4)
  const base64 = (base64Url + padding).replace(/-/g, '+').replace(/_/g, '/')
  const raw = atob(base64)
  return Uint8Array.from([...raw].map((carattere) => carattere.charCodeAt(0)))
}

export async function sottoscrizioneAttuale() {
  if (!pushSupportata()) return null
  const registrazione = await navigator.serviceWorker.ready
  return registrazione.pushManager.getSubscription()
}

// Chiede il permesso (se serve), crea la sottoscrizione push del browser e la
// salva su Supabase: da quel momento il trigger su notifications trova una
// riga a cui mandare le push per questo utente.
export async function attivaPush(): Promise<{ ok: boolean; errore?: string }> {
  if (!pushSupportata()) return { ok: false, errore: 'Le notifiche push non sono supportate su questo browser.' }
  try {
    const permesso = await Notification.requestPermission()
    if (permesso !== 'granted') return { ok: false, errore: 'Permesso negato.' }

    const registrazione = await navigator.serviceWorker.ready
    const esistente = await registrazione.pushManager.getSubscription()
    const sottoscrizione = esistente ?? await registrazione.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: base64UrlAUint8Array(VAPID_PUBLIC_KEY!),
    })

    const json = sottoscrizione.toJSON()
    if (!json.endpoint || !json.keys?.p256dh || !json.keys?.auth) {
      return { ok: false, errore: 'Sottoscrizione incompleta restituita dal browser.' }
    }

    const { error } = await supabase.from('push_subscriptions').upsert({
      endpoint: json.endpoint,
      p256dh: json.keys.p256dh,
      auth_key: json.keys.auth,
      user_agent: navigator.userAgent,
      user_id: (await supabase.auth.getUser()).data.user?.id,
    }, { onConflict: 'endpoint' })
    if (error) return { ok: false, errore: error.message }

    return { ok: true }
  } catch (caught) {
    return { ok: false, errore: caught instanceof Error ? caught.message : 'Attivazione non riuscita.' }
  }
}

// Disattiva sia lato browser (pushManager.unsubscribe) sia lato server (la
// riga smette di ricevere): fare solo uno dei due lascerebbe l'altro
// disallineato, o niente push in arrivo o push a un browser che le ha rifiutate.
export async function disattivaPush(): Promise<{ ok: boolean; errore?: string }> {
  if (!pushSupportata()) return { ok: true }
  try {
    const registrazione = await navigator.serviceWorker.ready
    const sottoscrizione = await registrazione.pushManager.getSubscription()
    if (!sottoscrizione) return { ok: true }
    const endpoint = sottoscrizione.endpoint
    await sottoscrizione.unsubscribe()
    const { error } = await supabase.from('push_subscriptions').delete().eq('endpoint', endpoint)
    if (error) return { ok: false, errore: error.message }
    return { ok: true }
  } catch (caught) {
    return { ok: false, errore: caught instanceof Error ? caught.message : 'Disattivazione non riuscita.' }
  }
}
