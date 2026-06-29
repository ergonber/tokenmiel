'use client';

import { useEffect, useState } from 'react';
import { fetchApiJson } from '../lib/api';

type ContractStatusResponse = {
  name: string;
  address: string;
  chainId: number;
  paused: boolean;
  status?: 'ok' | 'error';
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

const CONTRACTS = ['AssetVault', 'IdentityRegistry', 'RedemptionManager'] as const;

export function BackendStatusPanel() {
  const [summary, setSummary] = useState<BackendSummaryResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function loadStatus() {
      try {
        const response = await fetchApiJson<BackendSummaryResponse>('/api/status/summary');
        setSummary(response);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Unable to reach the backend');
      } finally {
        setLoading(false);
      }
    }

    void loadStatus();
  }, []);

  return (
    <section className="panel" aria-labelledby="backend-status-title">
      <div className="panel-header">
        <div>
          <p className="eyebrow">Integración en vivo</p>
          <h2 id="backend-status-title">Estado del backend</h2>
        </div>
        <span className={`pill ${loading ? 'neutral' : error ? 'danger' : 'success'}`}>
          {loading ? 'Verificando…' : error ? 'Desconectado' : 'Conectado'}
        </span>
      </div>

      {error ? (
        <p className="helper-text">El frontend está listo, pero el backend no responde. Arranca el servidor de la API para mostrar el estado en vivo aquí.</p>
      ) : (
        <>
          <div className="status-grid">
            <div className="status-card">
              <p className="status-label">Servicio</p>
              <strong>{summary?.service ?? '—'}</strong>
              <span>{summary ? `${summary.status} · chain ${summary.chainId}` : 'Cargando…'}</span>
            </div>
            <div className="status-card">
              <p className="status-label">Resumen</p>
              <strong>{summary?.summary?.healthyContracts ?? '—'}/{summary?.summary?.totalContracts ?? '—'}</strong>
              <span>{summary?.summary?.pausedContracts ? `${summary.summary.pausedContracts} pausados` : 'Todos operativos'}</span>
            </div>
          </div>

          <ul className="contract-list">
            {CONTRACTS.map((contract) => {
              const status = summary?.contracts[contract];
              const state = status?.status === 'error' ? 'Error' : status?.paused ? 'Pausado' : 'Activo';

              return (
                <li key={contract}>
                  <div>
                    <strong>{contract}</strong>
                    <span>{status ? state : 'Cargando…'}</span>
                  </div>
                  <code>{status?.address ? status.address : '—'}</code>
                </li>
              );
            })}
          </ul>
        </>
      )}
    </section>
  );
}
