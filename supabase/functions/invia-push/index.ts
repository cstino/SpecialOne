import '@supabase/functions-js/edge-runtime.d.ts'
import { withSupabase } from '@supabase/server'
import webpush from 'web-push'

// Stessa mappa a chiave singola gia' in uso da simula-giornata: il segreto
// che autentica il trigger (via pg_net, header apikey) e' lo stesso con cui
// il client amministrativo parla al database.
const CHIAVE_SEGRETA = Deno.env.get('CHIAVE_SEGRETA_PROGETTO') ?? ''

const VAPID_PUBLIC_KEY = Deno.env.get('VAPID_PUBLIC_KEY') ?? ''
const VAPID_PRIVATE_KEY = Deno.env.get('VAPID_PRIVATE_KEY') ?? ''
const VAPID_SUBJECT = Deno.env.get('VAPID_SUBJECT') ?? 'mailto:notifiche@specialone.app'

if (VAPID_PUBLIC_KEY && VAPID_PRIVATE_KEY) {
  webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY)
}

type Notification = {
  id: number
  user_id: string
  league_id: number | null
  tipo: string
  titolo: string
  corpo: string | null
  dati: Record<string, unknown>
}

type Subscription = {
  id: number
  endpoint: string
  p256dh: string
  auth_key: string
}

export default {
  // Solo il trigger su notifications chiama questa funzione, mai un
  // browser: nessun JWT utente da accettare.
  fetch: withSupabase({
    auth: ['secret'],
    env: { secretKeys: CHIAVE_SEGRETA ? { default: CHIAVE_SEGRETA } : {} },
  }, async (req, ctx) => {
    try {
      if (req.method !== 'POST') return Response.json({ error: 'Metodo non consentito.' }, { status: 405 })
      if (!VAPID_PUBLIC_KEY || !VAPID_PRIVATE_KEY) {
        // Chiavi non ancora configurate: non e' un errore del chiamante
        // (il trigger e' fire-and-forget), solo niente da inviare.
        return Response.json({ inviate: 0, motivo: 'Chiavi VAPID non configurate.' })
      }

      const body = await req.json().catch(() => ({})) as { notification_id?: number }
      const notificationId = Number(body.notification_id)
      if (!Number.isInteger(notificationId) || notificationId < 1) {
        return Response.json({ error: 'notification_id non valido.' }, { status: 400 })
      }

      const { data: notifica, error: notificaError } = await ctx.supabaseAdmin
        .from('notifications')
        .select('id, user_id, league_id, tipo, titolo, corpo, dati')
        .eq('id', notificationId)
        .single()
      if (notificaError || !notifica) return Response.json({ error: 'Notifica non trovata.' }, { status: 404 })
      const n = notifica as Notification

      const { data: subscriptions, error: subError } = await ctx.supabaseAdmin
        .from('push_subscriptions')
        .select('id, endpoint, p256dh, auth_key')
        .eq('user_id', n.user_id)
      if (subError) throw subError
      const abbonamenti = (subscriptions ?? []) as Subscription[]
      if (abbonamenti.length === 0) return Response.json({ inviate: 0, motivo: 'Nessuna sottoscrizione per questo utente.' })

      const payload = JSON.stringify({
        titolo: n.titolo,
        corpo: n.corpo,
        tipo: n.tipo,
        dati: { ...n.dati, notification_id: n.id, league_id: n.league_id },
      })

      let inviate = 0
      const daRimuovere: number[] = []
      await Promise.all(abbonamenti.map(async (sub) => {
        try {
          await webpush.sendNotification(
            { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth_key } },
            payload,
          )
          inviate += 1
        } catch (errore) {
          // 404/410: il browser ha revocato o dimenticato la sottoscrizione
          // (disinstallata, dati cancellati). Non e' un errore da ritentare,
          // solo una riga stantia da pulire.
          const status = (errore as { statusCode?: number }).statusCode
          if (status === 404 || status === 410) daRimuovere.push(sub.id)
          else console.error(`Push non inviata (sottoscrizione ${sub.id}):`, errore)
        }
      }))

      if (daRimuovere.length) {
        await ctx.supabaseAdmin.from('push_subscriptions').delete().in('id', daRimuovere)
      }

      return Response.json({ inviate, rimosse: daRimuovere.length, totali: abbonamenti.length })
    } catch (error) {
      console.error(error)
      return Response.json({ error: error instanceof Error ? error.message : 'Errore durante l\'invio della push.' }, { status: 500 })
    }
  }),
}
