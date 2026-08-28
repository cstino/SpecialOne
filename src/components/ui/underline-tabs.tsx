import type { ReactNode } from 'react'
import { motion } from 'motion/react'

// Barra di tab con indicatore sottolineato animato (riferimento: pagina
// squadra dell'app UEFA Champions League). Costruita a mano invece che
// importata da 21st.dev: il componente "Underline Tabs" trovato lì
// dipendeva da un file di utility non arrivato nel pacchetto scaricato
// (registryDependencies conteneva solo i primitivi shadcn generici, non
// l'implementazione v-tabs-2-utils/tabs che gestisce l'indicatore). Questa
// versione usa motion (già una dipendenza del progetto, vedi Draft.tsx)
// con layoutId per l'animazione condivisa: stesso effetto, senza
// introdurre un pacchetto con un pezzo mancante.
type UnderlineTab<T extends string> = { value: T; label: string; badge?: ReactNode; disabled?: boolean; activeColor?: string }

type UnderlineTabsProps<T extends string> = {
  tabs: readonly UnderlineTab<T>[]
  value: T
  onChange: (value: T) => void
  layoutId?: string
  className?: string
}

export function UnderlineTabs<T extends string>({ tabs, value, onChange, layoutId = 'underline-tab-indicator', className = '' }: UnderlineTabsProps<T>) {
  return (
    // overflow-x/y non possono essere uno "auto" e l'altro "visible" insieme
    // (regola della spec CSS Overflow: se uno dei due non e' "visible",
    // l'altro diventa "auto" anche se scritto "visible"): tentare
    // overflow-y-visible accanto a overflow-x-auto non aveva alcun effetto.
    // overflow-y-hidden invece e' esplicito e prevedibile, e touch-action:
    // pan-x dice al touch di iOS/Android di scorrere solo in orizzontale —
    // senza, Safari lascia trascinare la riga anche in verticale (il difetto
    // segnalato) perche' un overflow-y "auto" implicito resta comunque
    // scrollabile col dito anche senza nulla da scorrere.
    <div
      className={`flex justify-center gap-7 overflow-x-auto overflow-y-hidden border-b border-white/10 ${className}`}
      style={{ touchAction: 'pan-x' }}
      role="tablist"
    >
      {tabs.map((tab) => {
        const active = tab.value === value
        const colore = active ? tab.activeColor : undefined
        return (
          <button
            key={tab.value}
            type="button"
            role="tab"
            aria-selected={active}
            disabled={tab.disabled}
            onClick={() => onChange(tab.value)}
            style={colore ? { color: colore } : undefined}
            className={`relative flex shrink-0 items-center whitespace-nowrap pb-3 text-[.8rem] font-bold tracking-tight transition-colors disabled:cursor-not-allowed disabled:opacity-35 ${active ? (colore ? '' : 'text-white') : 'text-white/45 hover:text-white/70'}`}
          >
            {tab.label}
            {tab.badge != null && (
              <span
                style={colore ? { backgroundColor: `${colore}26`, color: colore } : undefined}
                className={`ml-1.5 flex items-center rounded-full px-1.5 py-0.5 text-[.65rem] font-extrabold tabular-nums leading-none ${active ? (colore ? '' : 'bg-white/15 text-white') : 'bg-white/[0.06] text-white/40'}`}
              >
                {tab.badge}
              </span>
            )}
            {active && (
              <motion.span
                layoutId={layoutId}
                style={{ backgroundColor: colore ?? '#fff' }}
                className="absolute inset-x-0 -bottom-px h-[2px] rounded-full"
                transition={{ type: 'spring', stiffness: 500, damping: 40 }}
              />
            )}
          </button>
        )
      })}
    </div>
  )
}
