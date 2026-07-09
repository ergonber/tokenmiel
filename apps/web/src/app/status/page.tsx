"use client";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { useState, useEffect } from "react";
import { fetchApiJson } from "@/lib/api";
import {
  Activity,
  CheckCircle2,
  XCircle,
  AlertTriangle,
  RefreshCw,
  Wifi,
  WifiOff,
} from "lucide-react";

type ContractStatusResponse = {
  name: string;
  address: string;
  chainId: number;
  paused: boolean;
  status?: "ok" | "error";
  message?: string;
};

type BackendSummaryResponse = {
  status: string;
  chainId: number;
  service: string;
  version: string;
  contracts: Record<string, ContractStatusResponse>;
  summary?: {
    totalContracts: number;
    healthyContracts: number;
    pausedContracts: number;
  };
};

const CONTRACTS = ["AssetVault", "IdentityRegistry", "RedemptionManager"] as const;

export default function StatusPage() {
  const [summary, setSummary] = useState<BackendSummaryResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [lastRefresh, setLastRefresh] = useState<Date>(new Date());

  const loadStatus = async () => {
    setLoading(true);
    setError(null);
    try {
      const response = await fetchApiJson<BackendSummaryResponse>("/api/status/summary");
      setSummary(response);
      setLastRefresh(new Date());
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unable to reach the backend");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void loadStatus();
    const interval = setInterval(loadStatus, 30000);
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="space-y-8">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold mb-2">Estado del Sistema</h1>
          <p className="text-muted">
            Monitoreo en tiempo real de los contratos inteligentes y servicios backend.
          </p>
        </div>
        <Button variant="outline" onClick={loadStatus} disabled={loading}>
          <RefreshCw className={`h-4 w-4 ${loading ? "animate-spin" : ""}`} />
          Actualizar
        </Button>
      </div>

      {/* Connection Status */}
      <Card
        className={
          error
            ? "border-danger/30 bg-danger/5"
            : "border-success/30 bg-success/5"
        }
      >
        <CardContent className="p-6">
          <div className="flex items-center gap-4">
            {error ? (
              <WifiOff className="h-8 w-8 text-danger" />
            ) : (
              <Wifi className="h-8 w-8 text-success" />
            )}
            <div className="flex-1">
              <h3 className="font-semibold">
                {error ? "Backend Desconectado" : "Backend Conectado"}
              </h3>
              <p className="text-sm text-muted">
                {error
                  ? "No se puede conectar al servidor API. Asegúrate de que el backend esté ejecutándose en el puerto 3001."
                  : `${summary?.service} v${summary?.version} - Chain ID: ${summary?.chainId}`}
              </p>
            </div>
            <Badge variant={error ? "danger" : "success"}>
              {error ? "Offline" : "Online"}
            </Badge>
          </div>
        </CardContent>
      </Card>

      {/* Summary Stats */}
      {summary && (
        <div className="grid md:grid-cols-3 gap-4">
          <Card>
            <CardContent className="p-6 text-center">
              <Activity className="h-8 w-8 text-primary mx-auto mb-2" />
              <p className="text-3xl font-bold">{summary.summary?.totalContracts ?? 0}</p>
              <p className="text-sm text-muted">Contratos</p>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="p-6 text-center">
              <CheckCircle2 className="h-8 w-8 text-success mx-auto mb-2" />
              <p className="text-3xl font-bold text-success">
                {summary.summary?.healthyContracts ?? 0}
              </p>
              <p className="text-sm text-muted">Saludables</p>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="p-6 text-center">
              <AlertTriangle className="h-8 w-8 text-warning mx-auto mb-2" />
              <p className="text-3xl font-bold text-warning">
                {summary.summary?.pausedContracts ?? 0}
              </p>
              <p className="text-sm text-muted">Pausados</p>
            </CardContent>
          </Card>
        </div>
      )}

      {/* Contract Details */}
      <Card>
        <CardHeader>
          <CardTitle>Contratos Inteligentes</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            {CONTRACTS.map((contract) => {
              const status = summary?.contracts[contract];
              const isHealthy = status?.status === "ok" && !status?.paused;
              const isPaused = status?.paused;
              const isError = status?.status === "error";

              return (
                <div
                  key={contract}
                  className={`flex items-center justify-between p-4 rounded-xl border ${
                    isHealthy
                      ? "border-success/20 bg-success/5"
                      : isPaused
                      ? "border-warning/20 bg-warning/5"
                      : isError
                      ? "border-danger/20 bg-danger/5"
                      : "border-border bg-muted/5"
                  }`}
                >
                  <div className="flex items-center gap-4">
                    {isHealthy ? (
                      <CheckCircle2 className="h-6 w-6 text-success" />
                    ) : isPaused ? (
                      <AlertTriangle className="h-6 w-6 text-warning" />
                    ) : isError ? (
                      <XCircle className="h-6 w-6 text-danger" />
                    ) : (
                      <Activity className="h-6 w-6 text-muted" />
                    )}
                    <div>
                      <h4 className="font-semibold">{contract}</h4>
                      <p className="text-xs text-muted font-mono">
                        {status?.address ?? "—"}
                      </p>
                    </div>
                  </div>
                  <div className="text-right">
                    <Badge
                      variant={
                        isHealthy
                          ? "success"
                          : isPaused
                          ? "warning"
                          : isError
                          ? "danger"
                          : "default"
                      }
                    >
                      {loading
                        ? "Cargando..."
                        : isHealthy
                        ? "Activo"
                        : isPaused
                        ? "Pausado"
                        : isError
                        ? "Error"
                        : "Sin datos"}
                    </Badge>
                    {status?.message && (
                      <p className="text-xs text-muted mt-1">{status.message}</p>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </CardContent>
      </Card>

      {/* Network Info */}
      <Card>
        <CardHeader>
          <CardTitle>Información de Red</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid md:grid-cols-2 gap-4">
            <div className="p-4 rounded-xl bg-muted/5">
              <p className="text-sm text-muted mb-1">Red Primaria</p>
              <p className="font-semibold">Plume Network</p>
              <p className="text-xs text-muted">Chain ID: 98867 (Testnet)</p>
            </div>
            <div className="p-4 rounded-xl bg-muted/5">
              <p className="text-sm text-muted mb-1">Moneda</p>
              <p className="font-semibold">USDC</p>
              <p className="text-xs text-muted">6 decimales (Circle)</p>
            </div>
            <div className="p-4 rounded-xl bg-muted/5">
              <p className="text-sm text-muted mb-1">Última Actualización</p>
              <p className="font-semibold">
                {lastRefresh.toLocaleTimeString("es-BO")}
              </p>
              <p className="text-xs text-muted">Auto-refresh cada 30s</p>
            </div>
            <div className="p-4 rounded-xl bg-muted/5">
              <p className="text-sm text-muted mb-1">Oráculo</p>
              <p className="font-semibold">Safe Multi-sig</p>
              <p className="text-xs text-muted">2-de-3 confirmaciones</p>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
