import { AppHeader } from './AppHeader';
import { BackendStatusPanel } from './BackendStatusPanel';
import { HeroIllustration } from './HeroIllustration';

const highlights = [
  'Tokenización de productos físicos con blockchain',
  'Confianza operacional y trazabilidad en tiempo real',
  'Interfaz clara para compliance y exportación',
];

const tokenBenefits = [
  'Activo respaldado con inventario físico',
  'Auditoría de cadena de custodia en cada paso',
  'Acceso al mercado con un activo digital seguro',
];

const howItWorks = [
  {
    title: '1. Registro del lote',
    description: 'El productor registra cada lote y su estado físico antes de tokenizarlo.',
  },
  {
    title: '2. Cumplimiento on-chain',
    description: 'El backend verifica roles, KYC y cadena de contratos en Plume.',
  },
  {
    title: '3. Visibilidad comercial',
    description: 'Los compradores ven el estado en tiempo real y el historial de trazabilidad.',
  },
];

export function LandingPage() {
  return (
    <main className="page-shell" id="inicio">
      <AppHeader />

      <section className="hero-section">
        <div className="hero-content">
          <p className="eyebrow">Tokenización de activos reales con trazabilidad</p>
          <h1>Tokeniza miel, café o cacao con una experiencia de producto premium.</h1>
          <p className="hero-text">
            Este frontend ya integra la API existente y convierte la propuesta en una primera impresión sólida: identidad, estado del backend y evidencia de cumplimiento en una sola pantalla.
          </p>
          <div className="hero-badges">
            <span>Miel boliviana</span>
            <span>Compliance</span>
            <span>Plume Network</span>
          </div>
          <div className="hero-actions">
            <a className="primary-link" href="#status">
              Ver estado en vivo
            </a>
            <a className="secondary-link" href="#como-funciona">
              Ver flujo rápido
            </a>
          </div>
          <div className="hero-metrics">
            <div>
              <strong>4</strong>
              <span>Contratos operativos</span>
            </div>
            <div>
              <strong>24/7</strong>
              <span>Monitorización visible</span>
            </div>
            <div>
              <strong>100%</strong>
              <span>Traza de custodia</span>
            </div>
          </div>
          <ul className="highlight-list">
            {highlights.map((item) => (
              <li key={item}>{item}</li>
            ))}
          </ul>
        </div>
        <HeroIllustration />
      </section>

      <section className="feature-grid-section" id="como-funciona">
        <div className="section-heading">
          <p className="eyebrow">Cómo se ve el producto</p>
          <h2>Un flujo claro desde la cosecha hasta la exportación.</h2>
        </div>
        <div className="feature-grid">
          {howItWorks.map((item) => (
            <article className="feature-card" key={item.title}>
              <p className="eyebrow">{item.title.split('.')[0]}</p>
              <h2>{item.title}</h2>
              <p>{item.description}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="metrics-grid" aria-label="Valores clave">
        <article className="metric-card">
          <span className="metric-kicker">Infraestructura</span>
          <h3>Plume + Polygon</h3>
          <p>Diseñado para expandirse con múltiples redes y una experiencia operacional consistente.</p>
        </article>
        <article className="metric-card">
          <span className="metric-kicker">Compliance</span>
          <h3>KYC y trazabilidad</h3>
          <p>El flujo reúne validación, estado de lote y evidencia para la toma de decisión.</p>
        </article>
        <article className="metric-card">
          <span className="metric-kicker">Operación</span>
          <h3>Monitoreo en tiempo real</h3>
          <p>El backend expone integraciones claves para mostrar el estado del producto sin fricción.</p>
        </article>
      </section>

      <section className="token-section" id="token">
        <div>
          <p className="eyebrow">Token</p>
          <h2>Un activo digital que refleja valor físico y cumplimiento.</h2>
          <p>
            El token representa un lote de la cadena de valor y se liga al estado del backend: contratos, minting y redención.
          </p>
          <ul className="trust-list">
            {tokenBenefits.map((item) => (
              <li key={item}>{item}</li>
            ))}
          </ul>
        </div>
        <div className="token-visual-card">
          <span>Token</span>
          <strong>MRG-001</strong>
          <p>Moneda digital fiduciada en trazabilidad y reservas físicas.</p>
        </div>
      </section>

      <section className="trust-section" id="status">
        <div>
          <p className="eyebrow">Integración</p>
          <h2>Backend existente enlazado con el frontend.</h2>
        </div>
        <BackendStatusPanel />
      </section>

      <section className="contact-section" id="contacto">
        <div>
          <p className="eyebrow">Contacto</p>
          <h2>Listo para presentar el producto al mercado.</h2>
          <p>
            Si querés avanzar con el siguiente paso, podemos crear el flujo de purchase, las páginas de detalles de lote y las integraciones on-chain de mint/redemption.
          </p>
        </div>
        <a className="primary-link" href="mailto:hello@tokeniza.example">
          Enviar consulta
        </a>
      </section>
    </main>
  );
}
