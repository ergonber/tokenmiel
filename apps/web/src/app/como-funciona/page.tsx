import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import {
  Leaf,
  Shield,
  Lock,
  TrendingUp,
  FileCheck,
  Globe,
  Eye,
  CheckCircle2,
  ArrowRight,
} from "lucide-react";

const steps = [
  {
    icon: <Leaf className="h-6 w-6" />,
    title: "1. Registro del Lote",
    description:
      "El productor registra su lote con metadatos completos: variedad, origen geográfico, cantidad esperada y documentación SENASAG.",
    details: [
      "Cada lote tiene un ID único en-chain",
      "Se registra la variedad monofloral (Yerba Santa, Quilliquivi, etc.)",
      "Coordenadas geográficas del apiario",
      "Hash SHA-256 del Formulario de Sanidad Animal (FSA)",
    ],
  },
  {
    icon: <Lock className="h-6 w-6" />,
    title: "2. Preventa y Escrow",
    description:
      "Los compradores adquieren tokens pagando USDC. El dinero queda retenido en el contrato inteligente hasta confirmar cosecha.",
    details: [
      "1 token = 500g de miel monofloral",
      "USDC retenido en escrow (no va al productor aún)",
      "Reserva técnica del 15-20% como garantía",
      "KYC obligatorio para compradores (Tier 1 mínimo)",
    ],
  },
  {
    icon: <CheckCircle2 className="h-6 w-6" />,
    title: "3. Confirmación de Cosecha",
    description:
      "Un oráculo multi-sig (Safe 2-de-3) verifica la producción real y libera el monto neto al productor.",
    details: [
      "Verificación de documentos SENASAG on-chain",
      "Análisis de laboratorio certificado",
      "Fotos del apiario y acta de cosecha",
      "El monto neto se transfiere al productor SRL",
    ],
  },
  {
    icon: <FileCheck className="h-6 w-6" />,
    title: "4. Almacenamiento",
    description:
      "El producto se almacena en un almacén autorizado. Se registra el contrato de depósito on-chain.",
    details: [
      "Contrato de depósito con almacén autorizado",
      "Estado ALMACENADO visible para compradores",
      "Producto disponible para redención física",
    ],
  },
  {
    icon: <TrendingUp className="h-6 w-6" />,
    title: "5. Redención",
    description:
      "Los compradores canjean sus tokens por miel física. El token se quema y el producto se envía.",
    details: [
      "Flujo de exportación SENASAG/DUE",
      "Tokens quemados vía RedemptionManager",
      "Envío documentado con trazabilidad completa",
      "Estado cambia a REDENCION_PARCIAL o AGOTADO",
    ],
  },
];

const guarantees = [
  {
    icon: <Shield className="h-6 w-6" />,
    title: "Escrow Total",
    description:
      "El USDC del comprador nunca toca las manos del productor hasta que se confirme la cosecha. Si falla, reembolso 100%.",
  },
  {
    icon: <Globe className="h-6 w-6" />,
    title: "Trazabilidad On-Chain",
    description:
      "Cada documento tiene un hash SHA-256 registrado en blockchain. Senasag, laboratorio, certificados - todo verificable.",
  },
  {
    icon: <Eye className="h-6 w-6" />,
    title: "Transparencia Total",
    description:
      "Todo el historial de transacciones es público y verificable. Sin intermediarios opacos.",
  },
];

export default function ComoFuncionaPage() {
  return (
    <div className="space-y-12">
      {/* Header */}
      <div className="text-center max-w-2xl mx-auto">
        <Badge variant="default" className="mb-3">
          Proceso
        </Badge>
        <h1 className="text-4xl font-bold mb-4">Cómo Funciona TokenMiel</h1>
        <p className="text-lg text-muted">
          Un flujo seguro y transparente que conecta productores de miel boliviana con compradores
          internacionales mediante blockchain.
        </p>
      </div>

      {/* Steps */}
      <div className="space-y-6">
        {steps.map((step, i) => (
          <Card key={i} className="relative overflow-hidden">
            <div className="absolute left-0 top-0 bottom-0 w-1 bg-gradient-to-b from-primary to-primary-dark" />
            <CardHeader>
              <div className="flex items-center gap-4">
                <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-primary/10 text-primary">
                  {step.icon}
                </div>
                <div>
                  <CardTitle className="text-xl">{step.title}</CardTitle>
                </div>
              </div>
            </CardHeader>
            <CardContent>
              <p className="text-muted mb-4 ml-16">{step.description}</p>
              <ul className="ml-16 space-y-2">
                {step.details.map((detail, j) => (
                  <li key={j} className="flex items-start gap-2 text-sm">
                    <CheckCircle2 className="h-4 w-4 text-success mt-0.5 shrink-0" />
                    <span>{detail}</span>
                  </li>
                ))}
              </ul>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Guarantees */}
      <section className="bg-white/60 backdrop-blur-sm rounded-3xl border border-border p-8 md:p-12">
        <div className="text-center mb-8">
          <Badge variant="success" className="mb-3">
            Garantías
          </Badge>
          <h2 className="text-3xl font-bold">Tu Dinero Está Seguro</h2>
        </div>
        <div className="grid md:grid-cols-3 gap-6">
          {guarantees.map((item, i) => (
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

      {/* FAQ */}
      <section>
        <div className="text-center mb-8">
          <Badge variant="default" className="mb-3">
            Preguntas Frecuentes
          </Badge>
          <h2 className="text-3xl font-bold">¿Qué Pasa Si...?</h2>
        </div>
        <div className="grid md:grid-cols-2 gap-6">
          {[
            {
              q: "¿Qué pasa si el productor no cosecha?",
              a: "El 100% del USDC pagado se devuelve a los compradores. El dinero está retenido en el contrato inteligente (escrow) hasta que se confirme la cosecha.",
            },
            {
              q: "¿Qué pasa si la miel no cumple calidad?",
              a: "La reserva técnica (15-20%) sirve como compensación. Además, el oráculo multi-sig puede marcar el lote como FALLIDO antes de liberar el pago.",
            },
            {
              q: "¿Puedo vender mis tokens a otro?",
              a: "No. El sistema es 'Solo Primario' - no se permiten transferencias P2P. Los tokens solo se pueden quemar mediante redención física del producto.",
            },
            {
              q: "¿Cómo sé que la miel es realmente boliviana?",
              a: "Cada lote tiene hashes de documentos SENASAG, análisis de laboratorio y fotos del apiario registrados on-chain. Todo es verificable.",
            },
          ].map((faq, i) => (
            <Card key={i}>
              <CardHeader>
                <CardTitle className="text-base">{faq.q}</CardTitle>
              </CardHeader>
              <CardContent>
                <p className="text-sm text-muted">{faq.a}</p>
              </CardContent>
            </Card>
          ))}
        </div>
      </section>
    </div>
  );
}
