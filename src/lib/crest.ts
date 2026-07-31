const MAX_UPLOAD_BYTES = 2 * 1024 * 1024
const OUTPUT_SIZE = 512

export async function preparaStemma(file: File): Promise<Blob> {
  if (!['image/png', 'image/jpeg'].includes(file.type)) {
    throw new Error('Usa un file PNG o JPEG.')
  }
  if (file.size > MAX_UPLOAD_BYTES) {
    throw new Error('Il file supera il limite di 2 MB.')
  }

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
