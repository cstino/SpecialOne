type Props = { compatto?: boolean }

export function LoadingLogo({ compatto = false }: Props) {
  return <span className={`loading-logo${compatto ? ' loading-logo--compatto' : ''}`} role="status" aria-label="Caricamento in corso">
    <img src="/loghi/specialone_logo.svg" alt="" />
  </span>
}
