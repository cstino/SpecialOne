import { STEMMI_SQUADRA } from '../lib/teamCrests'
import type { CrestChoice } from '../types'
import { Crest } from './Crest'

type CrestPickerProps = {
  value: CrestChoice
  onChange: (value: CrestChoice) => void
  disabled?: boolean
  disabledValues?: string[]
}

// Gli stemmi si scelgono solo fra quelli predefiniti: il caricamento di
// immagini personali e' stato tolto il 5 ottobre 2026. Chi ne aveva gia' uno
// lo conserva (compare come prima voce, "Il tuo stemma") finche' non sceglie
// un predefinito.
export function CrestPicker({ value, onChange, disabled, disabledValues = [] }: CrestPickerProps) {
  return (
    <fieldset className="crest-picker" disabled={disabled}>
      <legend>Stemma squadra</legend>
      <div className="crest-grid">
        {value.type === 'existing' && (
          <button className="crest-option" type="button" aria-pressed aria-label="Il tuo stemma attuale" disabled>
            <img className="crest crest--small" src={value.previewUrl} alt="" />
          </button>
        )}
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
      </div>
      <p className="field-help">{value.type === 'existing' ? 'Hai uno stemma personalizzato: puoi tenerlo o passare a uno di questi, ma non si possono più caricare nuove immagini.' : 'Scegli lo stemma della tua squadra fra questi.'}</p>
    </fieldset>
  )
}
