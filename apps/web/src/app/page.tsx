import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { MOCK_LOTES, formatUSDC, getKgDisponibles, getEstadoLabel, getEstadoColor } from "@/lib/data";
import { ArrowRight, Shield, Leaf, TrendingUp, Globe, Lock, Eye } from "lucide-react";

export default function HomePage() {
  const lotesEnPreventa = MOCK_LOTES.filter((l) => l.estado === "PREVENTA");
  const lotesDisponibles = MOCK_LOTES.filter((l) => l.estado !== "FALLIDO" && l.estado !== "AGOTADO");

  return (
    <div className="space-y-16">
      {/* Hero Section */}
      <section className="relative overflow-hidden rounded-3xl bg-gradient-to-br from-white/95 to-primary/5 border border-border p-8 md:p-12">
        <div className="absolute -top-20 -left-20 w-64 h-64 bg-primary/10 rounded-full blur-3xl pointer-events-none" />
        <div className="relative z-10 grid md:grid-cols-2 gap-8 items-center">
          <div>
            <Badge variant="default" className="mb-4">Tokenización RWA</Badge>
            <h1 className="text-4xl md:text-5xl font-bold tracking-tight mb-4">
              Tokeniza miel, café o cacao con una experiencia premium
            </h1>
            <p className="text-lg text-muted mb-6">
              Trazabilidad completa desde la cosecha hasta tu mesa. Cada token representa
              500g de miel monofloral boliviana certificada.
            </p>
            <div className="flex flex-wrap gap-3">
              <Link href="/catalogo">
                <Button size="lg">
                  Ver Catálogo
                  <ArrowRight className="h-5 w-5" />
                </Button>
              </Link>
              <Link href="/como-funciona">
                <Button variant="outline" size="lg">
                  Cómo Funciona
                </Button>
              </Link>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Card className="bg-gradient-to-br from-primary/10 to-primary/5 border-primary/20">
              <CardContent className="p-4 text-center">
                <p className="text-3xl font-bold text-primary">{MOCK_LOTES.length}</p>
                <p className="text-sm text-muted">Lotes Registrados</p>
              </CardContent>
            </Card>
            <Card className="bg-gradient-to-br from-accent/10 to-accent/5 border-accent/20">
              <CardContent className="p-4 text-center">
                <p className="text-3xl font-bold text-accent">
                  {MOCK_LOTES.reduce((acc, l) => acc + l.kgEsperados, 0).toLocaleString()}
                </p>
                <p className="text-sm text-muted">Kg Totales</p>
              </CardContent>
            </Card>
            <Card className="bg-gradient-to-br from-success/10 to-success/5 border-success/20">
              <CardContent className="p-4 text-center">
                <p className="text-3xl font-bold text-success">3</p>
                <p className="text-sm text-muted">Contratos On-Chain</p>
              </CardContent>
            </Card>
            <Card className="bg-gradient-to-br from-info/10 to-info/5 border-info/20">
              <CardContent className="p-4 text-center">
                <p className="text-3xl font-bold text-info">Plume</p>
                <p className="text-sm text-muted">Red Primaria</p>
              </CardContent>
            </Card>
          </div>
        </div>
      </section>

      {/* How it works */}
      <section>
        <div className="text-center mb-8">
          <Badge variant="default" className="mb-3">Proceso</Badge>
          <h2 className="text-3xl font-bold">Cómo Funciona</h2>
        </div>
        <div className="grid md:grid-cols-3 gap-6">
          {[
            {
              icon: <Leaf className="h-6 w-6" />,
              title: "1. Registro del Lote",
              description: "El productor registra su lote con metadatos, origen geográfico y documentación SENASAG.",
            },
            {
              icon: <Lock className="h-6 w-6" />,
              title: "2. Escrow On-Chain",
              description: "Los compradores pagan USDC que queda retenido en el contrato hasta confirmar cosecha.",
            },
            {
              icon: <TrendingUp className="h-6 w-6" />,
              title: "3. Tokenización",
              "description": "Se emiten tokens ERC-1155 representando 500g de miel cada uno, listos para redención.",
            },
          ].map((step, i) => (
            <Card key={i} className="relative">
              <CardHeader>
                <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-primary/10 text-primary mb-2">
                  {step.icon}
                </div>
                <CardTitle className="text-lg">{step.title}</CardTitle>
              </CardHeader>
              <CardContent>
                <p className="text-muted">{step.description}</p>
              </CardContent>
            </Card>
          ))}
        </div>
      </section>

      {/* Featured Lots */}
      <section>
        <div className="flex items-center justify-between mb-6">
          <div>
            <Badge variant="default" className="mb-3">Catálogo</Badge>
            <h2 className="text-3xl font-bold">Lotes Disponibles</h2>
          </div>
          <Link href="/catalogo">
            <Button variant="outline">
              Ver Todos
              <ArrowRight className="h-4 w-4" />
            </Button>
          </Link>
        </div>
        <div className="grid md:grid-cols-3 gap-6">
          {lotesDisponibles.slice(0, 3).map((lote) => (
            <Link key={lote.loteId} href={`/lote/${lote.loteId}`}>
              <Card className="h-full cursor-pointer hover:scale-[1.02] transition-transform">
                <div className="h-40 bg-gradient-to-br from-primary/20 to-accent/20 rounded-t-2xl flex items-center justify-center">
                  <div className="text-6xl">🍯</div>
                </div>
                <CardHeader>
                  <div className="flex items-center justify-between">
                    <Badge variant={getEstadoColor(lote.estado) as any}>
                      {getEstadoLabel(lote.estado)}
                    </Badge>
                    <span className="text-xs text-muted">#{lote.loteId}</span>
                  </div>
                  <CardTitle className="text-lg">{lote.variedadMonofloral}</CardTitle>
                </CardHeader>
                <CardContent>
                  <p className="text-sm text-muted mb-4 line-clamp-2">{lote.descripcion}</p>
                  <div className="flex justify-between items-center">
                    <div>
                      <p className="text-xs text-muted">Precio por token</p>
                      <p className="font-bold text-primary">{formatUSDC(lote.precioPorTokenUSDC)}</p>
                    </div>
                    <div className="text-right">
                      <p className="text-xs text-muted">Disponible</p>
                      <p className="font-bold">{getKgDisponibles(lote)} kg</p>
                    </div>
                  </div>
                </CardContent>
              </Card>
            </Link>
          ))}
        </div>
      </section>

      {/* Trust Section */}
      <section className="bg-white/60 backdrop-blur-sm rounded-3xl border border-border p-8 md:p-12">
        <div className="text-center mb-8">
          <Badge variant="success" className="mb-3">Seguridad</Badge>
          <h2 className="text-3xl font-bold">Garantías On-Chain</h2>
        </div>
        <div className="grid md:grid-cols-3 gap-6">
          {[
            {
              icon: <Shield className="h-6 w-6" />,
              title: "Escrow Total",
              description: "El USDC de los compradores queda retenido en el contrato hasta que se confirme la cosecha.",
            },
            {
              icon: <Globe className="h-6 w-6" />,
              title: "Trazabilidad",
              description: "Cada lote tiene hashes SHA-256 de documentos SENASAG, análisis de laboratorio y certificados.",
            },
            {
              icon: <Eye className="h-6 w-6" />,
              title: "Transparencia",
              description: "Todo el historial de transacciones visible en blockchain. Sin intermediarios opacos.",
            },
          ].map((item, i) => (
            <div key={i} className="flex gap-4">
              <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-success/10 text-success">
                {item.icon}
              </div>
              <div>
                <h3 className="font-semibold mb-1">{item.title}</h3>
                <p className="text-sm text-muted">{item.description}</p>
              </div>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}
