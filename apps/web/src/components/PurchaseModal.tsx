"use client";

import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { X, Wallet, Shield, AlertCircle, CheckCircle2, Loader2 } from "lucide-react";
import { formatUSDC, getKgDisponibles, getTokensDisponibles, type LoteMiel } from "@/lib/data";

interface PurchaseModalProps {
  lote: LoteMiel;
  onClose: () => void;
}

type PurchaseStep = "connect" | "select" | "confirm" | "processing" | "success";

export function PurchaseModal({ lote, onClose }: PurchaseModalProps) {
  const [step, setStep] = useState<PurchaseStep>("connect");
  const [walletConnected, setWalletConnected] = useState(false);
  const [cantidadTokens, setCantidadTokens] = useState(1);
  const [walletAddress] = useState("0x1234...abcd");

  const tokensDisponibles = getTokensDisponibles(lote);
  const kgDisponibles = getKgDisponibles(lote);
  const montoTotal = cantidadTokens * lote.precioPorTokenUSDC;
  const montoNeto = Math.round(montoTotal * (1 - lote.reservaBps / 10000));

  const handleConnectWallet = () => {
    setWalletConnected(true);
    setStep("select");
  };

  const handleConfirmPurchase = () => {
    setStep("processing");
    setTimeout(() => {
      setStep("success");
    }, 2000);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm p-4">
      <Card className="w-full max-w-md relative">
        <button
          onClick={onClose}
          className="absolute right-4 top-4 p-1 rounded-full hover:bg-muted/10"
        >
          <X className="h-5 w-5" />
        </button>

        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            {step === "connect" && <Wallet className="h-5 w-5 text-primary" />}
            {step === "select" && <span>🛒</span>}
            {step === "confirm" && <Shield className="h-5 w-5 text-primary" />}
            {step === "processing" && <Loader2 className="h-5 w-5 text-primary animate-spin" />}
            {step === "success" && <CheckCircle2 className="h-5 w-5 text-success" />}
            {step === "connect" && "Conectar Wallet"}
            {step === "select" && "Seleccionar Cantidad"}
            {step === "confirm" && "Confirmar Compra"}
            {step === "processing" && "Procesando..."}
            {step === "success" && "¡Compra Exitosa!"}
          </CardTitle>
        </CardHeader>

        <CardContent className="space-y-4">
          {/* Step: Connect Wallet */}
          {step === "connect" && (
            <>
              <p className="text-sm text-muted">
                Conecta tu wallet para comprar tokens de{' '}
                <strong>{lote.variedadMonofloral}</strong>.
              </p>
              <div className="p-4 rounded-xl bg-primary/5 border border-primary/20">
                <p className="text-sm font-medium mb-1">¿Por qué necesito una wallet?</p>
                <p className="text-xs text-muted">
                  Los tokens se emiten directamente en la blockchain de Plume Network.
                  Necesitas una wallet compatible para recibir y gestionar tus tokens.
                </p>
              </div>
              <Button className="w-full" onClick={handleConnectWallet}>
                <Wallet className="h-4 w-4" />
                Conectar MetaMask
              </Button>
              <div className="text-center">
                <p className="text-xs text-muted">
                  ¿No tienes wallet?{' '}
                  <a href="#" className="text-primary hover:underline">
                    Guía para principiantes
                  </a>
                </p>
              </div>
            </>
          )}

          {/* Step: Select Quantity */}
          {step === "select" && (
            <>
              <div className="flex items-center gap-3 p-3 rounded-xl bg-muted/10">
                <div className="h-10 w-10 rounded-full bg-primary/10 flex items-center justify-center">
                  <Wallet className="h-5 w-5 text-primary" />
                </div>
                <div>
                  <p className="text-sm font-medium">Wallet Conectada</p>
                  <p className="text-xs text-muted font-mono">{walletAddress}</p>
                </div>
              </div>

              <div className="space-y-2">
                <label className="text-sm font-medium">Cantidad de Tokens</label>
                <div className="flex items-center gap-3">
                  <Button
                    variant="outline"
                    size="icon"
                    onClick={() => setCantidadTokens(Math.max(1, cantidadTokens - 1))}
                  >
                    -
                  </Button>
                  <input
                    type="number"
                    min={1}
                    max={tokensDisponibles}
                    value={cantidadTokens}
                    onChange={(e) =>
                      setCantidadTokens(
                        Math.min(tokensDisponibles, Math.max(1, parseInt(e.target.value) || 1))
                      )
                    }
                    className="flex-1 text-center text-2xl font-bold py-3 rounded-xl border border-border focus:outline-none focus:ring-2 focus:ring-primary/50"
                  />
                  <Button
                    variant="outline"
                    size="icon"
                    onClick={() =>
                      setCantidadTokens(Math.min(tokensDisponibles, cantidadTokens + 1))
                    }
                  >
                    +
                  </Button>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-muted">Máximo: {tokensDisponibles} tokens</span>
                  <button
                    onClick={() => setCantidadTokens(tokensDisponibles)}
                    className="text-primary hover:underline"
                  >
                    Máximo
                  </button>
                </div>
              </div>

              <div className="p-4 rounded-xl bg-muted/10 space-y-2">
                <div className="flex justify-between">
                  <span className="text-sm text-muted">Precio por token</span>
                  <span className="text-sm">{formatUSDC(lote.precioPorTokenUSDC)}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-sm text-muted">Gramos por token</span>
                  <span className="text-sm">500g</span>
                </div>
                <div className="flex justify-between font-semibold border-t border-border pt-2">
                  <span>Total</span>
                  <span className="text-primary">{formatUSDC(montoTotal)}</span>
                </div>
              </div>

              <Button className="w-full" onClick={() => setStep("confirm")}>
                Continuar
              </Button>
            </>
          )}

          {/* Step: Confirm */}
          {step === "confirm" && (
            <>
              <div className="p-4 rounded-xl bg-primary/5 border border-primary/20 space-y-3">
                <h4 className="font-semibold flex items-center gap-2">
                  <Shield className="h-4 w-4 text-primary" />
                  Resumen de Compra
                </h4>
                <div className="space-y-2 text-sm">
                  <div className="flex justify-between">
                    <span className="text-muted">Producto</span>
                    <span>{lote.variedadMonofloral}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-muted">Tokens</span>
                    <span>{cantidadTokens} tokens</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-muted">Equivalente</span>
                    <span>{cantidadTokens * 0.5} kg</span>
                  </div>
                  <div className="flex justify-between font-semibold border-t border-border pt-2">
                    <span>Total a pagar</span>
                    <span className="text-primary">{formatUSDC(montoTotal)}</span>
                  </div>
                </div>
              </div>

              <div className="p-3 rounded-xl bg-success/5 border border-success/20">
                <p className="text-xs text-success flex items-center gap-2">
                  <Shield className="h-4 w-4" />
                  Tu pago queda retenido en escrow hasta confirmar cosecha. 100% seguro.
                </p>
              </div>

              <div className="flex gap-3">
                <Button variant="outline" className="flex-1" onClick={() => setStep("select")}>
                  Volver
                </Button>
                <Button className="flex-1" onClick={handleConfirmPurchase}>
                  Confirmar Pago
                </Button>
              </div>
            </>
          )}

          {/* Step: Processing */}
          {step === "processing" && (
            <div className="text-center py-8">
              <Loader2 className="h-12 w-12 text-primary animate-spin mx-auto mb-4" />
              <p className="font-semibold">Procesando tu transacción...</p>
              <p className="text-sm text-muted mt-2">
                Por favor espera mientras confirmamos el pago en la blockchain.
              </p>
            </div>
          )}

          {/* Step: Success */}
          {step === "success" && (
            <div className="text-center py-4">
              <CheckCircle2 className="h-16 w-16 text-success mx-auto mb-4" />
              <h3 className="text-xl font-bold mb-2">¡Compra Exitosa!</h3>
              <p className="text-muted mb-4">
                Has comprado {cantidadTokens} tokens de {lote.variedadMonofloral}.
              </p>
              <div className="p-4 rounded-xl bg-muted/10 text-left space-y-2 text-sm">
                <div className="flex justify-between">
                  <span className="text-muted">Tokens</span>
                  <span className="font-semibold">{cantidadTokens}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted">Monto</span>
                  <span className="font-semibold">{formatUSDC(montoTotal)}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted">Estado</span>
                  <Badge variant="success">En Escrow</Badge>
                </div>
              </div>
              <Button className="w-full mt-4" onClick={onClose}>
                Cerrar
              </Button>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
