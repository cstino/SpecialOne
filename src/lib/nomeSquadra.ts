// Regole del nome squadra (stesse del trigger SQL private.valida_nome_squadra,
// che e' quello che fa fede): da 2 a 22 caratteri, spazi compresi; solo
// lettere (anche accentate), numeri, spazi e apostrofo. Niente simboli ne' emoji.
export const NOME_SQUADRA_MAX = 22
export const SUGGERIMENTO_NOME_SQUADRA = 'Massimo 22 caratteri: solo lettere, numeri, spazi e apostrofo.'

const NON_AMMESSI = /[^A-Za-zÀ-ÖØ-öø-ÿĀ-ž0-9 '’]/g

// Mentre si scrive: toglie quello che non e' ammesso (anche incollato) e taglia a 22.
export function pulisciNomeSquadra(valore: string): string {
  return valore.normalize('NFC').replace(NON_AMMESSI, '').replace(/ {2,}/g, ' ').slice(0, NOME_SQUADRA_MAX)
}
