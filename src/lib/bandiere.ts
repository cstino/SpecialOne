// Bandiera (emoji) della nazionalita' come la scrive il catalogo giocatori (players.nazionalita, in inglese FC 26).
// Le nazioni del Regno Unito usano le bandiere a sequenza di tag (Inghilterra, Scozia, Galles).

const ISO: Record<string, string> = {
  Albania: 'AL', Algeria: 'DZ', Angola: 'AO', Argentina: 'AR', Armenia: 'AM', Australia: 'AU', Austria: 'AT',
  Azerbaijan: 'AZ', Bangladesh: 'BD', Belgium: 'BE', Benin: 'BJ', 'Bosnia and Herzegovina': 'BA', Brazil: 'BR',
  Bulgaria: 'BG', 'Burkina Faso': 'BF', Burundi: 'BI', 'Cabo Verde': 'CV', Cameroon: 'CM', Canada: 'CA',
  'Central African Republic': 'CF', Chad: 'TD', Chile: 'CL', Colombia: 'CO', Comoros: 'KM', Congo: 'CG',
  'Congo DR': 'CD', 'Costa Rica': 'CR', "Côte d'Ivoire": 'CI', Croatia: 'HR', Curacao: 'CW', Cyprus: 'CY',
  Czechia: 'CZ', Denmark: 'DK', 'Dominican Republic': 'DO', Ecuador: 'EC', Egypt: 'EG', 'Equatorial Guinea': 'GQ',
  Estonia: 'EE', Finland: 'FI', France: 'FR', Gabon: 'GA', Gambia: 'GM', Georgia: 'GE', Germany: 'DE', Ghana: 'GH',
  Greece: 'GR', Guinea: 'GN', 'Guinea-Bissau': 'GW', Haiti: 'HT', Honduras: 'HN', Hungary: 'HU', Iceland: 'IS',
  Indonesia: 'ID', Iran: 'IR', Iraq: 'IQ', Israel: 'IL', Italy: 'IT', Jamaica: 'JM', Japan: 'JP', Jordan: 'JO',
  Kenya: 'KE', 'Korea Republic': 'KR', Kosovo: 'XK', Liberia: 'LR', Libya: 'LY', Lithuania: 'LT', Luxembourg: 'LU',
  Malaysia: 'MY', Mali: 'ML', Malta: 'MT', Mauritania: 'MR', Mexico: 'MX', Moldova: 'MD', Montenegro: 'ME',
  Morocco: 'MA', Mozambique: 'MZ', Namibia: 'NA', Netherlands: 'NL', 'New Zealand': 'NZ', Niger: 'NE', Nigeria: 'NG',
  'North Macedonia': 'MK', 'Northern Ireland': 'GB', Norway: 'NO', Panama: 'PA', Paraguay: 'PY', Peru: 'PE',
  Poland: 'PL', Portugal: 'PT', 'Puerto Rico': 'PR', 'Republic of Ireland': 'IE', Romania: 'RO', Russia: 'RU',
  'Saudi Arabia': 'SA', Senegal: 'SN', Serbia: 'RS', 'Sierra Leone': 'SL', Slovakia: 'SK', Slovenia: 'SI',
  'South Africa': 'ZA', Spain: 'ES', Suriname: 'SR', Sweden: 'SE', Switzerland: 'CH', Syria: 'SY', Tanzania: 'TZ',
  Togo: 'TG', Tunisia: 'TN', Türkiye: 'TR', Ukraine: 'UA', 'United States': 'US', Uruguay: 'UY', Uzbekistan: 'UZ',
  Venezuela: 'VE', Yemen: 'YE', Zambia: 'ZM', Zimbabwe: 'ZW',
}

// Bandiere a sequenza di tag: nero sventolante + lettere della suddivisione + terminatore.
const TAG: Record<string, string> = { England: 'gbeng', Scotland: 'gbsct', Wales: 'gbwls' }

export function bandiera(nazionalita: string | null | undefined): string {
  if (!nazionalita) return ''
  const tag = TAG[nazionalita]
  if (tag) return '\u{1F3F4}' + [...tag].map((c) => String.fromCodePoint(0xE0000 + c.charCodeAt(0))).join('') + '\u{E007F}'
  const iso = ISO[nazionalita]
  return iso ? [...iso].map((c) => String.fromCodePoint(0x1F1E6 + c.charCodeAt(0) - 65)).join('') : ''
}
