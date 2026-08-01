import { useEffect, useId, useRef, useState } from 'react'
import { rimuoviSfondoStemma } from '../lib/crest'
import type { CrestChoice } from '../types'
import { Crest } from './Crest'

const PRESET = ['scudo', 'diagonale', 'torre', 'stella', 'quartieri', 'corona'] as const

type CrestPickerProps = {
  value: CrestChoice
  onChange: (value: CrestChoice) => void
  disabled?: boolean
}

export function CrestPicker({ value, onChange, disabled }: CrestPickerProps) {
  const inputId = useId()
  const previousPreview = useRef<string | null>(null)
  const [processing, setProcessing] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => () => { if (previousPreview.current) URL.revokeObjectURL(previousPreview.current) }, [])

  function scegliFile(file?: File) {
    if (!file) return
    setError(null)
    if (previousPreview.current) URL.revokeObjectURL(previousPreview.current)
    const previewUrl = URL.createObjectURL(file)
    previousPreview.current = previewUrl
    onChange({ type: 'upload', file, previewUrl })
  }

  async function removeBackground() {
    if (value.type !== 'upload') return
    setProcessing(true)
    setError(null)
    try { scegliFile(await rimuoviSfondoStemma(value.file)) }
    catch (caught) { setError(caught instanceof Error ? caught.message : 'Rimozione dello sfondo non riuscita.') }
    setProcessing(false)
  }

  return (
    <fieldset className="crest-picker" disabled={disabled}>
      <legend>Stemma squadra</legend>
      <div className="crest-grid">
        {PRESET.map((preset) => {
          const presetValue = `preset:${preset}`
          const selected = value.type === 'preset' && value.value === presetValue
          return (
            <button
              className="crest-option"
              type="button"
              key={preset}
              aria-pressed={selected}
              aria-label={`Scegli stemma ${preset}`}
              onClick={() => onChange({ type: 'preset', value: presetValue })}
            >
              <Crest value={presetValue} />
            </button>
          )
        })}
        <label className="crest-upload" htmlFor={inputId}>
          {value.type === 'upload' || value.type === 'existing' ? (
            <img src={value.previewUrl} alt="Anteprima stemma caricato" />
          ) : (
            <span aria-hidden="true">＋</span>
          )}
          <span className="sr-only">Carica uno stemma personalizzato</span>
        </label>
        <input
          className="sr-only"
          id={inputId}
          type="file"
          accept="image/png,image/jpeg"
          onChange={(event) => scegliFile(event.target.files?.[0])}
        />
      </div>
      {value.type === 'upload' && <button className="crest-background-tool" type="button" disabled={disabled || processing} onClick={removeBackground}>{processing ? 'Rimozione…' : '✦ Rimuovi sfondo'}</button>}
      <p className="field-help">PNG/JPEG, massimo 2 MB. L’immagine viene ritagliata automaticamente in formato quadrato.</p>
      {error && <p className="crest-tool-error" role="alert">{error}</p>}
    </fieldset>
  )
}
