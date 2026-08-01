const MAX_UPLOAD_BYTES = 2 * 1024 * 1024
const OUTPUT_SIZE = 512

export function generaUuidV4() {
  const webCrypto = globalThis.crypto
  if (typeof webCrypto?.randomUUID === 'function') return webCrypto.randomUUID()
  if (typeof webCrypto?.getRandomValues !== 'function') throw new Error('Il browser non supporta il caricamento sicuro delle immagini.')
  const bytes = webCrypto.getRandomValues(new Uint8Array(16))
  bytes[6] = (bytes[6] & 0x0f) | 0x40
  bytes[8] = (bytes[8] & 0x3f) | 0x80
  const hex = [...bytes].map((value) => value.toString(16).padStart(2, '0')).join('')
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
}

export function formatoStemma(blob: Blob) {
  if (blob.type === 'image/webp') return { extension: 'webp', contentType: 'image/webp' as const }
  if (blob.type === 'image/png') return { extension: 'png', contentType: 'image/png' as const }
  throw new Error(`Formato immagine non supportato: ${blob.type || 'sconosciuto'}.`)
}

function validaFile(file: File) {
  if (!['image/png', 'image/jpeg'].includes(file.type)) throw new Error('Usa un file PNG o JPEG.')
  if (file.size > MAX_UPLOAD_BYTES) throw new Error('Il file supera il limite di 2 MB.')
}

export async function rimuoviSfondoStemma(file: File): Promise<File> {
  validaFile(file)
  const bitmap = await createImageBitmap(file)
  const maxSide = 1024
  const scale = Math.min(1, maxSide / Math.max(bitmap.width, bitmap.height))
  const width = Math.max(1, Math.round(bitmap.width * scale))
  const height = Math.max(1, Math.round(bitmap.height * scale))
  const canvas = document.createElement('canvas')
  canvas.width = width
  canvas.height = height
  const context = canvas.getContext('2d', { willReadFrequently: true })
  if (!context) throw new Error('Il browser non riesce a elaborare l’immagine.')
  context.drawImage(bitmap, 0, 0, width, height)
  bitmap.close()

  const image = context.getImageData(0, 0, width, height)
  const corners = [[0, 0], [width - 1, 0], [0, height - 1], [width - 1, height - 1]].map(([x, y]) => {
    const offset = (y * width + x) * 4
    return [image.data[offset], image.data[offset + 1], image.data[offset + 2]]
  })
  for (let offset = 0; offset < image.data.length; offset += 4) {
    const red = image.data[offset]
    const green = image.data[offset + 1]
    const blue = image.data[offset + 2]
    const distance = Math.min(...corners.map(([r, g, b]) => Math.hypot(red - r, green - g, blue - b)))
    const transparency = Math.max(0, Math.min(1, (distance - 18) / 48))
    image.data[offset + 3] = Math.round(image.data[offset + 3] * transparency)
  }
  context.putImageData(image, 0, 0)
  const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/png'))
  if (!blob) throw new Error('Non è stato possibile rimuovere lo sfondo.')
  return new File([blob], `${file.name.replace(/\.[^.]+$/, '')}-senza-sfondo.png`, { type: 'image/png' })
}

export async function preparaStemma(file: File): Promise<Blob> {
  validaFile(file)

  const bitmap = await createImageBitmap(file)
  const lato = Math.min(bitmap.width, bitmap.height)
  const x = (bitmap.width - lato) / 2
  const y = (bitmap.height - lato) / 2
  const canvas = document.createElement('canvas')
  canvas.width = OUTPUT_SIZE
  canvas.height = OUTPUT_SIZE
  const context = canvas.getContext('2d')
  if (!context) throw new Error('Il browser non riesce a elaborare l’immagine.')
  context.drawImage(bitmap, x, y, lato, lato, 0, 0, OUTPUT_SIZE, OUTPUT_SIZE)
  bitmap.close()

  const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/webp', 0.86))
  if (!blob) throw new Error('Non è stato possibile preparare lo stemma.')
  if (blob.size > 512 * 1024) throw new Error('L’immagine compressa supera 512 KB. Scegline una più semplice.')
  return blob
}
