import { useEffect, useId, useRef, useState } from 'react'
import { rimuoviSfondoStemma } from '../lib/crest'
import { STEMMI_SQUADRA } from '../lib/teamCrests'
import type { CrestChoice } from '../types'
import { Crest } from './Crest'

type CrestPickerProps = {
  value: CrestChoice
  onChange: (value: CrestChoice) => void
  disabled?: boolean
  disabledValues?: string[]
}

export function CrestPicker({ value, onChange, disabled, disabledValues = [] }: CrestPickerProps) {
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
        <label className="crest-upload" htmlFor={inputId}>
          {value.type === 'upload' || value.type === 'existing' ? (
            <img src={value.previewUrl} alt="Anteprima stemma caricato" />
          ) : (
            <span aria-hidden="true">＋</span>
          )}
          <span className="sr-only">Carica uno stemma personalizzato</span>
        </label>
        {STEMMI_SQUADRA.map((stemma) => {
          const presetValue = `preset:${stemma.id}`
          const selected = value.type === 'preset' && value.value === presetValue
          const used = disabledValues.includes(presetValue)
          return (
            <button
              className={`crest-option ${used ? 'is-unavailable' : ''}`}
              type="button"
              key={stemma.id}
              aria-pressed={selected}
              aria-label={used ? `Stemma ${stemma.nome} gia' usato` : `Scegli stemma ${stemma.nome}`}
              disabled={disabled || used}
              onClick={() => onChange({ type: 'preset', value: presetValue })}
            >
              <Crest value={presetValue} />
            </button>
          )
        })}
        <input
          className="sr-only"
          id={inputId}
          type="file"
          accept="image/png,image/jpeg"
          onChange={(event) => scegliFile(event.target.files?.[0])}
        />
      </div>
      {value.type === 'upload' && <button className="crest-background-tool" type="button" disabled={disabled || processing} onClick={removeBackground}>{processing ? 'Rimozione…' : '✦ Rimuovi sfondo'}</button>}
      <p className="field-help">Scegli uno stemma oppure caricane uno PNG/JPEG, massimo 2 MB. L’immagine personale viene ritagliata automaticamente in formato quadrato.</p>
      {error && <p className="crest-tool-error" role="alert">{error}</p>}
    </fieldset>
  )
}
