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
type UnderlineTab<T extends string> = { value: T; label: string; badge?: ReactNode; disabled?: boolean }

type UnderlineTabsProps<T extends string> = {
  tabs: readonly UnderlineTab<T>[]
  value: T
  onChange: (value: T) => void
  layoutId?: string
  className?: string
}

export function UnderlineTabs<T extends string>({ tabs, value, onChange, layoutId = 'underline-tab-indicator', className = '' }: UnderlineTabsProps<T>) {
  return (
    <div className={`flex justify-center gap-7 overflow-x-auto border-b border-white/10 ${className}`} role="tablist">
      {tabs.map((tab) => {
        const active = tab.value === value
        return (
          <button
            key={tab.value}
            type="button"
            role="tab"
            aria-selected={active}
            disabled={tab.disabled}
            onClick={() => onChange(tab.value)}
            className={`relative flex shrink-0 items-center whitespace-nowrap pb-3 text-[.8rem] font-bold tracking-tight transition-colors disabled:cursor-not-allowed disabled:opacity-35 ${active ? 'text-white' : 'text-white/45 hover:text-white/70'}`}
          >
            {tab.label}
            {tab.badge != null && (
              <span className={`ml-1.5 flex items-center rounded-full px-1.5 py-0.5 text-[.65rem] font-extrabold tabular-nums leading-none ${active ? 'bg-white/15 text-white' : 'bg-white/[0.06] text-white/40'}`}>
                {tab.badge}
              </span>
            )}
            {active && (
              <motion.span
                layoutId={layoutId}
                className="absolute inset-x-0 -bottom-px h-[2px] rounded-full bg-white"
                transition={{ type: 'spring', stiffness: 500, damping: 40 }}
              />
            )}
          </button>
        )
      })}
    </div>
  )
}
