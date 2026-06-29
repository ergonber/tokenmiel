import Link from 'next/link';

export function AppHeader() {
  return (
    <header className="site-header">
      <Link href="#inicio" className="brand-link">
        <span className="brand-mark">T</span>
        <span className="brand-name">TokenMiel</span>
      </Link>
      <nav className="site-nav">
        <a href="#inicio">Inicio</a>
        <a href="#como-funciona">Cómo funciona</a>
        <a href="#token">Token</a>
        <a href="#contacto">Contacto</a>
        <a className="nav-pill" href="#status">
          Estado live
        </a>
      </nav>
    </header>
  );
}
