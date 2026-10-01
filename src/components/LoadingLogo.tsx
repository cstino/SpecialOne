type Props = { compatto?: boolean }

export function LoadingLogo({ compatto = false }: Props) {
  return <span className={`loading-logo${compatto ? ' loading-logo--compatto' : ''}`} role="status" aria-label="Caricamento in corso">
    <i className="loading-logo__anello" aria-hidden="true" />
    <img src="/loghi/specialone_logo.svg" alt="" />
  </span>
}
