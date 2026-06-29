export function HeroIllustration() {
  return (
    <div className="hero-visual">
      <div className="hero-card-visual">
        <div className="hero-card-top">
          <span />
          <span />
        </div>
        <div className="hero-card-body">
          <div className="hero-card-chip" />
          <div className="hero-card-blocks">
            <span />
            <span />
            <span />
          </div>
          <div className="hero-card-dashboard">
            <div>
              <small>Activo</small>
              <strong>MRG-001</strong>
            </div>
            <div>
              <small>Estado</small>
              <strong>Verificado</strong>
            </div>
          </div>
        </div>
        <div className="hero-card-details">
          <span />
          <span />
        </div>
      </div>
      <div className="hero-floating-icon">
        <svg viewBox="0 0 48 48" fill="none" aria-hidden="true">
          <rect x="8" y="8" width="32" height="32" rx="12" fill="#D4AF37" />
          <path d="M24 14L18 24H30L24 14Z" fill="#0F5132" />
          <path d="M24 34C25.6569 34 27 32.6569 27 31C27 29.3431 25.6569 28 24 28C22.3431 28 21 29.3431 21 31C21 32.6569 22.3431 34 24 34Z" fill="#0F5132" />
        </svg>
      </div>
    </div>
  );
}
