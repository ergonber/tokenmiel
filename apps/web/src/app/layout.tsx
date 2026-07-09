import type { Metadata } from "next";
import "./globals.css";
import { Navigation } from "@/components/Navigation";

export const metadata: Metadata = {
  title: "TokenMiel - Tokenización de Miel Boliviana",
  description: "Plataforma de tokenización de miel monofloral boliviana para exportación premium. Trazabilidad, compliance y transparencia en blockchain.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="es">
      <body>
        <div className="min-h-screen">
          <Navigation />
          <main className="max-w-7xl mx-auto px-4 py-8">
            {children}
          </main>
          <footer className="border-t border-border bg-white/50 backdrop-blur-sm mt-16">
            <div className="max-w-7xl mx-auto px-4 py-8">
              <div className="flex flex-col md:flex-row justify-between items-center gap-4">
                <div className="flex items-center gap-3">
                  <div className="flex h-8 w-8 items-center justify-center rounded-full bg-primary text-white font-bold text-sm">
                    T
                  </div>
                  <span className="font-semibold">TokenMiel</span>
                </div>
                <p className="text-sm text-muted">
                  Plataforma de tokenización RWA - Cochabamba, Bolivia
                </p>
                <div className="flex gap-4 text-sm text-muted">
                  <a href="#" className="hover:text-primary transition-colors">Términos</a>
                  <a href="#" className="hover:text-primary transition-colors">Privacidad</a>
                  <a href="#" className="hover:text-primary transition-colors">Contacto</a>
                </div>
              </div>
            </div>
          </footer>
        </div>
      </body>
    </html>
  );
}
