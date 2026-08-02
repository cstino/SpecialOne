export const STEMMI_SQUADRA = [
  { id: '1', nome: 'Stemma 1', src: '/stemmi-squadra/thumbs/1.png' },
  { id: 'alci', nome: 'Alci', src: '/stemmi-squadra/thumbs/alci.png' },
  { id: 'aliens', nome: 'Aliens', src: '/stemmi-squadra/thumbs/aliens.png' },
  { id: 'aquile', nome: 'Aquile', src: '/stemmi-squadra/thumbs/aquile.png' },
  { id: 'aviator', nome: 'Aviator', src: '/stemmi-squadra/thumbs/aviator.png' },
  { id: 'bigbrain', nome: 'Big Brain', src: '/stemmi-squadra/thumbs/bigbrain.png' },
  { id: 'calvi', nome: 'Calvi', src: '/stemmi-squadra/thumbs/calvi.png' },
  { id: 'canna', nome: 'Canna', src: '/stemmi-squadra/thumbs/canna.png' },
  { id: 'cola', nome: 'Cola', src: '/stemmi-squadra/thumbs/cola.png' },
  { id: 'coord', nome: 'Coord', src: '/stemmi-squadra/thumbs/coord.png' },
  { id: 'cotoletta', nome: 'Cotoletta', src: '/stemmi-squadra/thumbs/cotoletta.png' },
  { id: 'eagle', nome: 'Eagle', src: '/stemmi-squadra/thumbs/eagle.png' },
  { id: 'flat', nome: 'Flat', src: '/stemmi-squadra/thumbs/flat.png' },
  { id: 'generale', nome: 'Generale', src: '/stemmi-squadra/thumbs/generale.png' },
  { id: 'leoni', nome: 'Leoni', src: '/stemmi-squadra/thumbs/leoni.png' },
  { id: 'lions', nome: 'Lions', src: '/stemmi-squadra/thumbs/lions.png' },
  { id: 'lupo', nome: 'Lupo', src: '/stemmi-squadra/thumbs/lupo.png' },
  { id: 'massoni', nome: 'Massoni', src: '/stemmi-squadra/thumbs/massoni.png' },
  { id: 'mcdonald', nome: 'McDonald', src: '/stemmi-squadra/thumbs/mcdonald.png' },
  { id: 'musk', nome: 'Musk', src: '/stemmi-squadra/thumbs/musk.png' },
  { id: 'musso', nome: 'Musso', src: '/stemmi-squadra/thumbs/musso.png' },
  { id: 'onepiece', nome: 'One Piece', src: '/stemmi-squadra/thumbs/onepiece.png' },
  { id: 'parenzo', nome: 'Parenzo', src: '/stemmi-squadra/thumbs/parenzo.png' },
  { id: 'piramidi', nome: 'Piramidi', src: '/stemmi-squadra/thumbs/piramidi.png' },
  { id: 'rocca', nome: 'Rocca', src: '/stemmi-squadra/thumbs/rocca.png' },
  { id: 'rosa', nome: 'Rosa', src: '/stemmi-squadra/thumbs/rosa.png' },
  { id: 'skull', nome: 'Skull', src: '/stemmi-squadra/thumbs/skull.png' },
  { id: 'slot', nome: 'Slot', src: '/stemmi-squadra/thumbs/slot.png' },
  { id: 'torres', nome: 'Torres', src: '/stemmi-squadra/thumbs/torres.png' },
  { id: 'totti', nome: 'Totti', src: '/stemmi-squadra/thumbs/totti.png' },
  { id: 'trump', nome: 'Trump', src: '/stemmi-squadra/thumbs/trump.png' },
  { id: 'twins', nome: 'Twins', src: '/stemmi-squadra/thumbs/twins.png' },
  { id: 'wolves', nome: 'Wolves', src: '/stemmi-squadra/thumbs/wolves.png' },
  { id: 'yugioh', nome: 'Yu-Gi-Oh', src: '/stemmi-squadra/thumbs/yugioh.png' },
] as const

export const STEMMA_SQUADRA_DEFAULT = `preset:${STEMMI_SQUADRA[0].id}`

const STEMMI_PER_ID = new Map<string, (typeof STEMMI_SQUADRA)[number]>(
  STEMMI_SQUADRA.map((stemma) => [stemma.id, stemma]),
)

export function stemmaPresetDaValore(value: string | null) {
  if (!value?.startsWith('preset:')) return null
  return STEMMI_PER_ID.get(value.slice(7)) ?? STEMMI_SQUADRA[0]
}
