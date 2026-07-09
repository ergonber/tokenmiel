"use client";

import { useParams, useRouter } from "next/navigation";
import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Progress } from "@/components/ui/progress";
import {
  MOCK_LOTES,
  formatUSDC,
  formatDate,
  getKgDisponibles,
  getTokensDisponibles,
  getProgreso,
  getEstadoLabel,
  getEstadoColor,
  getTimeline,
  type LoteMiel,
} from "@/lib/data";
import {
  ArrowLeft,
  MapPin,
  Calendar,
  Shield,
  FileCheck,
  Clock,
  CheckCircle2,
  XCircle,
  AlertCircle,
  Wallet,
  ShoppingCart,
  ExternalLink,
} from "lucide-react";
import Link from "next/link";
import { PurchaseModal } from "@/components/PurchaseModal";

const REGIONES: Record<string, string> = {
  CB: "Cochabamba",
  SC: "Santa Cruz",
  CH: "Chuquisaca",
  OR: "Oruro",
  TJ: "Tarija",
  LP: "La Paz",
  PD: "Pando",
  BN: "Beni",
};

export default function LoteDetailPage() {
  const params = useParams();
  const router = useRouter();
  const loteId = Number(params.id);
  const lote = MOCK_LOTES.find((l) => l.loteId === loteId);
  const [showPurchaseModal, setShowPurchaseModal] = useState(false);

  if (!lote) {
    return (
      <div className="text-center py-20">
        <p className="text-6xl mb-4">❌</p>
        <h1 className="text-2xl font-bold mb-2">Lote no encontrado</h1>
        <p className="text-muted mb-6">El lote #{loteId} no existe en el sistema.</p>
        <Link href="/catalogo">
          <Button>
            <ArrowLeft className="h-4 w-4" />
            Volver al Catálogo
          </Button>
        </Link>
      </div>
    );
  }

  const timeline = getTimeline(lote);
  const kgDisponibles = getKgDisponibles(lote);
  const tokensDisponibles = getTokensDisponibles(lote);
  const progreso = getProgreso(lote);

  return (
    <div className="space-y-8">
      {/* Header */}
      <div className="flex items-center gap-4">
        <Button variant="ghost" size="icon" onClick={() => router.back()}>
          <ArrowLeft className="h-5 w-5" />
        </Button>
        <div className="flex-1">
          <div className="flex items-center gap-3">
            <h1 className="text-3xl font-bold">{lote.variedadMonofloral}</h1>
            <Badge variant={getEstadoColor(lote.estado) as any}>
              {getEstadoLabel(lote.estado)}
            </Badge>
          </div>
          <div className="flex items-center gap-4 mt-1 text-sm text-muted">
            <span className="flex items-center gap-1">
              <MapPin className="h-4 w-4" />
              {REGIONES[lote.origenGeografico] || lote.origenGeografico}
            </span>
            <span className="flex items-center gap-1">
              <Calendar className="h-4 w-4" />
              Lote #{lote.loteId}
            </span>
          </div>
        </div>
        {lote.estado === "PREVENTA" && (
          <Button size="lg" onClick={() => setShowPurchaseModal(true)}>
            <ShoppingCart className="h-5 w-5" />
            Comprar Tokens
          </Button>
        )}
      </div>

      <div className="grid lg:grid-cols-3 gap-8">
        {/* Main Content */}
        <div className="lg:col-span-2 space-y-6">
          {/* Description */}
          <Card>
            <CardHeader>
              <CardTitle>Descripción del Producto</CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-muted leading-relaxed">{lote.descripcion}</p>
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mt-6">
                <div className="p-3 rounded-xl bg-primary/5">
                  <p className="text-xs text-muted">Variedad</p>
                  <p className="font-semibold">{lote.variedadMonofloral}</p>
                </div>
                <div className="p-3 rounded-xl bg-primary/5">
                  <p className="text-xs text-muted">Región</p>
                  <p className="font-semibold">{REGIONES[lote.origenGeografico]}</p>
                </div>
                <div className="p-3 rounded-xl bg-primary/5">
                  <p className="text-xs text-muted">Productor</p>
                  <p className="font-semibold font-mono text-sm">{lote.productorSRL}</p>
                </div>
                <div className="p-3 rounded-xl bg-primary/5">
                  <p className="text-xs text-muted">Reserva Técnica</p>
                  <p className="font-semibold">{lote.reservaBps / 100}%</p>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Timeline */}
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Clock className="h-5 w-5 text-primary" />
                Línea de Tiempo
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="relative">
                <div className="absolute left-4 top-0 bottom-0 w-0.5 bg-border" />
                <div className="space-y-6">
                  {timeline.map((event, i) => (
                    <div key={i} className="relative flex gap-4">
                      <div
                        className={`relative z-10 flex h-8 w-8 shrink-0 items-center justify-center rounded-full ${
                          event.completado
                            ? "bg-success text-white"
                            : "bg-border text-muted"
                        }`}
                      >
                        {event.completado ? (
                          <CheckCircle2 className="h-4 w-4" />
                        ) : (
                          <Clock className="h-4 w-4" />
                        )}
                      </div>
                      <div className="flex-1 pb-2">
                        <div className="flex items-center gap-2">
                          <h4 className="font-semibold">{event.tipo}</h4>
                          {!event.completado && (
                            <Badge variant="info" className="text-[10px]">Pendiente</Badge>
                          )}
                        </div>
                        <p className="text-sm text-muted mt-1">{event.descripcion}</p>
                        <div className="flex items-center gap-3 mt-2">
                          <span className="text-xs text-muted">
                            {formatDate(event.fecha)}
                          </span>
                          {event.hash && (
                            <span className="text-xs font-mono text-primary/70 truncate max-w-[200px]">
                              {event.hash}
                            </span>
                          )}
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Documents */}
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <FileCheck className="h-5 w-5 text-primary" />
                Documentos Verificados
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="grid md:grid-cols-2 gap-3">
                {[
                  { label: "FSA (Formulario de Sanidad Animal)", hash: lote.hashesDocumentos.hashFSA },
                  { label: " SENASAG", hash: lote.hashesDocumentos.hashSenasag },
                  { label: "Análisis de Laboratorio", hash: lote.hashesDocumentos.hashAnalisisLab },
                  { label: "Acta de Cosecha", hash: lote.hashesDocumentos.hashActaCosecha },
                  { label: "Fotos del Apiario", hash: lote.hashesDocumentos.hashFotosApiario },
                  { label: "Certificado de Origen", hash: lote.hashesDocumentos.hashCertificadoOrigen },
                ].filter((doc) => doc.hash).map((doc, i) => (
                  <div key={i} className="flex items-center gap-3 p-3 rounded-xl bg-success/5 border border-success/20">
                    <Shield className="h-5 w-5 text-success shrink-0" />
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium truncate">{doc.label}</p>
                      <p className="text-xs font-mono text-muted truncate">{doc.hash}</p>
                    </div>
                    <ExternalLink className="h-4 w-4 text-muted shrink-0" />
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        </div>

        {/* Sidebar */}
        <div className="space-y-6">
          {/* Purchase Info */}
          <Card className="border-primary/20 bg-gradient-to-br from-primary/5 to-white">
            <CardHeader>
              <CardTitle className="text-lg">Información de Compra</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="flex justify-between items-center">
                <span className="text-muted">Precio por Token</span>
                <span className="text-2xl font-bold text-primary">{formatUSDC(lote.precioPorTokenUSDC)}</span>
              </div>
              <div className="flex justify-between items-center">
                <span className="text-muted">1 Token =</span>
                <span className="font-semibold">500g de miel</span>
              </div>
              <div className="border-t border-border pt-4">
                <div className="flex justify-between items-center mb-2">
                  <span className="text-muted">Tokens Disponibles</span>
                  <span className="font-bold">{tokensDisponibles}</span>
                </div>
                <Progress value={progreso} className="h-3" />
                <div className="flex justify-between items-center mt-2 text-sm">
                  <span className="text-muted">{kgDisponibles} kg disponibles</span>
                  <span className="text-muted">{lote.kgEsperados} kg totales</span>
                </div>
              </div>
              {lote.estado === "PREVENTA" && (
                <Button className="w-full" size="lg" onClick={() => setShowPurchaseModal(true)}>
                  <Wallet className="h-5 w-5" />
                  Comprar Ahora
                </Button>
              )}
              {lote.estado !== "PREVENTA" && (
                <div className="p-3 rounded-xl bg-muted/10 text-center">
                  <p className="text-sm text-muted">
                    {lote.estado === "FALLIDO"
                      ? "Este lote falló. Reembolso procesado."
                      : "Este lote no está disponible para compra."}
                  </p>
                </div>
              )}
            </CardContent>
          </Card>

          {/* Escrow Info */}
          <Card>
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2">
                <Shield className="h-5 w-5 text-success" />
                Garantía Escrow
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <div className="p-3 rounded-xl bg-success/5 border border-success/20">
                <p className="text-sm font-medium text-success">100% Garantizado</p>
                <p className="text-xs text-muted mt-1">
                  Tu USDC queda retenido en el contrato inteligente hasta que se confirme la cosecha.
                </p>
              </div>
              <div className="space-y-2 text-sm">
                <div className="flex justify-between">
                  <span className="text-muted">Monto Neto (productor)</span>
                  <span>{formatUSDC(lote.montoNetoPendiente)}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted">Reserva Técnica</span>
                  <span>{formatUSDC(lote.reservaTecnicaUSDC)}</span>
                </div>
                <div className="flex justify-between font-semibold border-t border-border pt-2">
                  <span>Total en Escrow</span>
                  <span>{formatUSDC(lote.montoNetoPendiente + lote.reservaTecnicaUSDC)}</span>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Network Info */}
          <Card>
            <CardHeader>
              <CardTitle className="text-lg">Red y Contratos</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm">
              <div className="flex justify-between">
                <span className="text-muted">Red</span>
                <Badge variant="info">Plume Network</Badge>
              </div>
              <div className="flex justify-between">
                <span className="text-muted">Token Standard</span>
                <span>ERC-1155</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted">Contrato</span>
                <span className="font-mono text-xs">AssetVault</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted">Moneda</span>
                <span>USDC</span>
              </div>
            </CardContent>
          </Card>
        </div>
      </div>

      {/* Purchase Modal */}
      {showPurchaseModal && (
        <PurchaseModal
          lote={lote}
          onClose={() => setShowPurchaseModal(false)}
        />
      )}
    </div>
  );
}
