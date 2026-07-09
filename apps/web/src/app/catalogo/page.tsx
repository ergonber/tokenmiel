"use client";

import Link from "next/link";
import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Progress } from "@/components/ui/progress";
import { MOCK_LOTES, formatUSDC, getKgDisponibles, getTokensDisponibles, getProgreso, getEstadoLabel, getEstadoColor, formatDate, type LoteEstado } from "@/lib/data";
import { Search, Filter, MapPin, Droplets } from "lucide-react";

const ESTADO_FILTERS: { value: LoteEstado | "TODOS"; label: string }[] = [
  { value: "TODOS", label: "Todos" },
  { value: "PREVENTA", label: "En Preventa" },
  { value: "COSECHADO", label: "Cosechados" },
  { value: "ALMACENADO", label: "Almacenados" },
  { value: "REDENCION_PARCIAL", label: "En Redención" },
  { value: "AGOTADO", label: "Agotados" },
  { value: "FALLIDO", label: "Fallidos" },
];

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

export default function CatalogoPage() {
  const [busqueda, setBusqueda] = useState("");
  const [filtroEstado, setFiltroEstado] = useState<LoteEstado | "TODOS">("TODOS");

  const lotesFiltrados = MOCK_LOTES.filter((lote) => {
    const matchBusqueda =
      lote.variedadMonofloral.toLowerCase().includes(busqueda.toLowerCase()) ||
      lote.descripcion.toLowerCase().includes(busqueda.toLowerCase()) ||
      REGIONES[lote.origenGeografico]?.toLowerCase().includes(busqueda.toLowerCase());
    const matchEstado = filtroEstado === "TODOS" || lote.estado === filtroEstado;
    return matchBusqueda && matchEstado;
  });

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-3xl font-bold mb-2">Catálogo de Lotes</h1>
        <p className="text-muted">
          Explora los lotes de miel monofloral boliviana disponibles para tokenización.
        </p>
      </div>

      {/* Filters */}
      <div className="flex flex-col md:flex-row gap-4">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted" />
          <input
            type="text"
            placeholder="Buscar por variedad, región o descripción..."
            value={busqueda}
            onChange={(e) => setBusqueda(e.target.value)}
            className="w-full pl-10 pr-4 py-3 rounded-xl border border-border bg-white/80 backdrop-blur-sm focus:outline-none focus:ring-2 focus:ring-primary/50 focus:border-primary"
          />
        </div>
        <div className="flex flex-wrap gap-2">
          {ESTADO_FILTERS.map((f) => (
            <button
              key={f.value}
              onClick={() => setFiltroEstado(f.value)}
              className={`px-4 py-2 rounded-full text-sm font-medium transition-colors ${
                filtroEstado === f.value
                  ? "bg-primary text-white"
                  : "bg-white/80 border border-border text-muted hover:bg-primary/5"
              }`}
            >
              {f.label}
            </button>
          ))}
        </div>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <Card>
          <CardContent className="p-4 text-center">
            <p className="text-2xl font-bold text-primary">{MOCK_LOTES.length}</p>
            <p className="text-xs text-muted">Total Lotes</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 text-center">
            <p className="text-2xl font-bold text-success">
              {MOCK_LOTES.filter((l) => l.estado === "PREVENTA").length}
            </p>
            <p className="text-xs text-muted">En Preventa</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 text-center">
            <p className="text-2xl font-bold text-warning">
              {MOCK_LOTES.filter((l) => ["COSECHADO", "ALMACENADO", "REDENCION_PARCIAL"].includes(l.estado)).length}
            </p>
            <p className="text-xs text-muted">En Proceso</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 text-center">
            <p className="text-2xl font-bold text-accent">
              {MOCK_LOTES.reduce((acc, l) => acc + l.kgEsperados, 0).toLocaleString()} kg
            </p>
            <p className="text-xs text-muted">Volumen Total</p>
          </CardContent>
        </Card>
      </div>

      {/* Lot Grid */}
      <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-6">
        {lotesFiltrados.map((lote) => (
          <Link key={lote.loteId} href={`/lote/${lote.loteId}`}>
            <Card className="h-full cursor-pointer hover:scale-[1.02] transition-transform group">
              <div className="h-48 bg-gradient-to-br from-primary/20 via-accent/10 to-primary/5 rounded-t-2xl flex items-center justify-center relative overflow-hidden">
                <div className="text-7xl group-hover:scale-110 transition-transform">🍯</div>
                <Badge
                  variant={getEstadoColor(lote.estado) as any}
                  className="absolute top-3 right-3"
                >
                  {getEstadoLabel(lote.estado)}
                </Badge>
                {lote.estado === "PREVENTA" && (
                  <div className="absolute bottom-3 left-3 right-3">
                    <Progress value={getProgreso(lote)} className="h-2" />
                    <p className="text-xs text-muted mt-1 text-center">
                      {getTokensDisponibles(lote)} tokens disponibles
                    </p>
                  </div>
                )}
              </div>
              <CardHeader className="pb-2">
                <div className="flex items-start justify-between">
                  <div>
                    <CardTitle className="text-lg group-hover:text-primary transition-colors">
                      {lote.variedadMonofloral}
                    </CardTitle>
                    <div className="flex items-center gap-2 mt-1">
                      <MapPin className="h-3 w-3 text-muted" />
                      <span className="text-xs text-muted">
                        {REGIONES[lote.origenGeografico] || lote.origenGeografico}
                      </span>
                      <span className="text-xs text-muted">•</span>
                      <span className="text-xs text-muted">#{lote.loteId}</span>
                    </div>
                  </div>
                </div>
              </CardHeader>
              <CardContent>
                <p className="text-sm text-muted mb-4 line-clamp-2">{lote.descripcion}</p>
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <p className="text-xs text-muted">Precio/Token</p>
                    <p className="font-bold text-primary">{formatUSDC(lote.precioPorTokenUSDC)}</p>
                  </div>
                  <div>
                    <p className="text-xs text-muted">Disponible</p>
                    <p className="font-bold">{getKgDisponibles(lote)} kg</p>
                  </div>
                  <div>
                    <p className="text-xs text-muted">1 Token =</p>
                    <p className="font-bold">500g</p>
                  </div>
                  <div>
                    <p className="text-xs text-muted">Reserva</p>
                    <p className="font-bold">{lote.reservaBps / 100}%</p>
                  </div>
                </div>
                {lote.estado === "FALLIDO" && lote.motivoFallo && (
                  <div className="mt-4 p-3 rounded-lg bg-danger/5 border border-danger/20">
                    <p className="text-xs text-danger font-medium">Motivo del fallo:</p>
                    <p className="text-xs text-muted mt-1">{lote.motivoFallo}</p>
                  </div>
                )}
              </CardContent>
            </Card>
          </Link>
        ))}
      </div>

      {lotesFiltrados.length === 0 && (
        <div className="text-center py-12">
          <p className="text-4xl mb-4">🔍</p>
          <p className="text-lg font-medium">No se encontraron lotes</p>
          <p className="text-muted">Intenta con otros filtros de búsqueda</p>
        </div>
      )}
    </div>
  );
}
