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

async function salvaSottoscrizione(sottoscrizione: PushSubscription) {
  const json = sottoscrizione.toJSON()
  if (!json.endpoint || !json.keys?.p256dh || !json.keys?.auth) {
    return { ok: false, errore: 'Sottoscrizione incompleta restituita dal browser.' }
  }

  const { data: autenticazione, error: autenticazioneError } = await supabase.auth.getUser()
  if (autenticazioneError || !autenticazione.user) {
    return { ok: false, errore: 'Sessione non disponibile. Accedi di nuovo e riprova.' }
  }

  const { error } = await supabase.from('push_subscriptions').upsert({
    endpoint: json.endpoint,
    p256dh: json.keys.p256dh,
    auth_key: json.keys.auth,
    user_agent: navigator.userAgent,
    user_id: autenticazione.user.id,
  }, { onConflict: 'endpoint' })

  return error ? { ok: false, errore: error.message } : { ok: true }
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

    return await salvaSottoscrizione(sottoscrizione)
  } catch (caught) {
    return { ok: false, errore: caught instanceof Error ? caught.message : 'Attivazione non riuscita.' }
  }
}

// Il permesso e la sottoscrizione nel browser non bastano: la Edge Function
// puo' aver eliminato dal database un endpoint revocato (404/410), oppure i
// dati locali possono essere sopravvissuti a un cambio account. In entrambi
// i casi la vecchia UI diceva "attive" pur non avendo un destinatario lato
// server. Verifichiamo entrambi i lati e, se sono disallineati, ricreiamo la
// sottoscrizione invece di risalvare un endpoint che il push service ha gia'
// dichiarato scaduto.
export async function sincronizzaPush(): Promise<{ ok: boolean; errore?: string }> {
  if (!pushSupportata()) return { ok: false, errore: 'Le notifiche push non sono supportate su questo browser.' }
  if (Notification.permission !== 'granted') return { ok: false, errore: 'Permesso non concesso.' }

  try {
    const locale = await sottoscrizioneAttuale()
    if (!locale) return await attivaPush()

    const { data: remota, error } = await supabase
      .from('push_subscriptions')
      .select('id')
      .eq('endpoint', locale.endpoint)
      .maybeSingle()
    if (error) return { ok: false, errore: error.message }

    if (!remota) {
      const rimossa = await locale.unsubscribe()
      if (!rimossa) return { ok: false, errore: 'La vecchia sottoscrizione non puo\' essere rinnovata.' }
      return await attivaPush()
    }

    // Aggiorna anche chiavi, user agent e proprietario se il browser li ha
    // rigenerati senza cambiare endpoint.
    return await salvaSottoscrizione(locale)
  } catch (caught) {
    return { ok: false, errore: caught instanceof Error ? caught.message : 'Sincronizzazione non riuscita.' }
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
