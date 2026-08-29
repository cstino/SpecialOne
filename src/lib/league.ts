export const CAMPIONATI = [
  'Premier League',
  'La Liga',
  'Serie A',
  'Bundesliga',
  'Ligue 1',
  'Eredivisie',
  'Liga Portugal',
  'Süper Lig',
  'Saudi Pro League',
  'EFL Championship',
] as const

export const ROSA_MINIMA = 21
export const ROSA_MASSIMA = 30

// Solo il proprietario del progetto puo' creare nuove leghe (richiesta
// esplicita, 29 agosto 2026): gli altri restano liberi di entrare con un
// codice invito. Lo stesso controllo vive anche lato server, in
// public.crea_lega — questo e' solo per non mostrare un bottone che
// fallirebbe sempre.
const EMAIL_PROPRIETARIO = 'cr.96bc@gmail.com'
export function puoCreareLeghe(email: string | null | undefined) {
  return email === EMAIL_PROPRIETARIO
}

export function calcolaGiornateTotali(squadre: number, gironi: number) {
  return (squadre - 1 + (squadre % 2)) * gironi
}

export function calcolaPartitePerSquadra(squadre: number, gironi: number) {
  return (squadre - 1) * gironi
}

export function dataFineStagione(giornate: number, now = new Date()) {
  const parti = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Rome',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(now)
  const leggi = (type: Intl.DateTimeFormatPartTypes) =>
    Number(parti.find((parte) => parte.type === type)?.value)
  const giornoRoma = new Date(Date.UTC(leggi('year'), leggi('month') - 1, leggi('day'), 12))
  giornoRoma.setUTCDate(giornoRoma.getUTCDate() + giornate)
  return new Intl.DateTimeFormat('it-IT', {
    timeZone: 'Europe/Rome',
    day: 'numeric',
    month: 'long',
    year: 'numeric',
  }).format(giornoRoma)
}

export function normalizzaCodice(codice: string) {
  return codice.toUpperCase().replace(/[^ABCDEFGHJKLMNPQRSTUVWXYZ23456789]/g, '').slice(0, 6)
}
