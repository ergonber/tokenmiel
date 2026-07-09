export type LoteEstado = "PREVENTA" | "COSECHADO" | "ALMACENADO" | "REDENCION_PARCIAL" | "AGOTADO" | "FALLIDO";

export type TipoCertificadoOrigen = "NONE" | "FORM_A" | "EUR_1" | "OTHER";

export interface LoteMiel {
  loteId: number;
  kgEsperados: number;
  kgCosechadosReal: number;
  kgRedimidos: number;
  precioPorTokenUSDC: number;
  reservaTecnicaUSDC: number;
  reservaTecnicaLiberada: number;
  montoNetoPendiente: number;
  fechaCosechaEstimada: number;
  estado: LoteEstado;
  fechaCreacion: number;
  origenGeografico: string;
  reservaBps: number;
  variedadMonofloral: string;
  productorSRL: string;
  motivoFallo?: string;
  descripcion: string;
  imagenUrl: string;
  hashesDocumentos: {
    hashFSA: string;
    hashSenasag?: string;
    hashAnalisisLab?: string;
    hashActaCosecha?: string;
    hashFotosApiario?: string;
    hashCertificadoOrigen?: string;
  };
}

export interface TimelineEvent {
  fecha: number;
  tipo: string;
  descripcion: string;
  hash?: string;
  completado: boolean;
}

export const MOCK_LOTES: LoteMiel[] = [
  {
    loteId: 1,
    kgEsperados: 500,
    kgCosechadosReal: 0,
    kgRedimidos: 0,
    precioPorTokenUSDC: 25,
    reservaTecnicaUSDC: 1875,
    reservaTecnicaLiberada: 0,
    montoNetoPendiente: 10625,
    fechaCosechaEstimada: Date.now() + 90 * 24 * 60 * 60 * 1000,
    estado: "PREVENTA",
    fechaCreacion: Date.now() - 30 * 24 * 60 * 60 * 1000,
    origenGeografico: "CB",
    reservaBps: 1500,
    variedadMonofloral: "Yerba Santa",
    productorSRL: "0x1234...abcd",
    descripcion: "Miel monofloral de Yerba Santa, cosecha de altillanura cochabambina. Notas herbales y mentoladas con textura cristalina.",
    imagenUrl: "/images/honey-yerba-santa.jpg",
    hashesDocumentos: {
      hashFSA: "0xabc123...def456",
    },
  },
  {
    loteId: 2,
    kgEsperados: 300,
    kgCosechadosReal: 312,
    kgRedimidos: 0,
    precioPorTokenUSDC: 30,
    reservaTecnicaUSDC: 1350,
    reservaTecnicaLiberada: 0,
    montoNetoPendiente: 7650,
    fechaCosechaEstimada: Date.now() - 15 * 24 * 60 * 60 * 1000,
    estado: "COSECHADO",
    fechaCreacion: Date.now() - 120 * 24 * 60 * 60 * 1000,
    origenGeografico: "SC",
    reservaBps: 1500,
    variedadMonofloral: "Quilliquivi",
    productorSRL: "0x5678...efgh",
    descripcion: "Miel de Quilliquivi del valle de Santa Cruz. Sabor suave con notas cítricas y color ámbar claro. Certificada SENASAG.",
    imagenUrl: "/images/honey-quilliquivi.jpg",
    hashesDocumentos: {
      hashFSA: "0xdef789...ghi012",
      hashSenasag: "0x111aaa...bbb222",
      hashAnalisisLab: "0x333ccc...ddd444",
      hashActaCosecha: "0x555eee...fff666",
      hashFotosApiario: "0x777ggg...hhh888",
      hashCertificadoOrigen: "0x999iii...jjj000",
    },
  },
  {
    loteId: 3,
    kgEsperados: 200,
    kgCosechadosReal: 205,
    kgRedimidos: 150,
    precioPorTokenUSDC: 35,
    reservaTecnicaUSDC: 1050,
    reservaTecnicaLiberada: 1050,
    montoNetoPendiente: 0,
    fechaCosechaEstimada: Date.now() - 60 * 24 * 60 * 60 * 1000,
    estado: "REDENCION_PARCIAL",
    fechaCreacion: Date.now() - 180 * 24 * 60 * 60 * 1000,
    origenGeografico: "CH",
    reservaBps: 1500,
    variedadMonofloral: "Tarqui",
    productorSRL: "0x9abc...ijkl",
    descripcion: "Miel de Tarqui, Chuquisaca. Perfil floral intenso con notas de eucalipto. Alta demanda en mercados europeos.",
    imagenUrl: "/images/honey-tarqui.jpg",
    hashesDocumentos: {
      hashFSA: "0xaaa111...bbb222",
      hashSenasag: "0xccc333...ddd444",
      hashAnalisisLab: "0xeee555...fff666",
      hashActaCosecha: "0xggg777...hhh888",
      hashFotosApiario: "0xiii999...jjj000",
      hashCertificadoOrigen: "0xkkk111...lll222",
    },
  },
  {
    loteId: 4,
    kgEsperados: 150,
    kgCosechadosReal: 0,
    kgRedimidos: 0,
    precioPorTokenUSDC: 28,
    reservaTecnicaUSDC: 630,
    reservaTecnicaLiberada: 0,
    montoNetoPendiente: 3570,
    fechaCosechaEstimada: Date.now() + 45 * 24 * 60 * 60 * 1000,
    estado: "PREVENTA",
    fechaCreacion: Date.now() - 10 * 24 * 60 * 60 * 1000,
    origenGeografico: "OR",
    reservaBps: 1500,
    variedadMonofloral: "Encenillo",
    productorSRL: "0xdef4...mnop",
    descripcion: "Miel de Encenillo de los Yungas de Oruro. Textura cremosa, sabor dulce con notas boscosas. Edición limitada.",
    imagenUrl: "/images/honey-encenillo.jpg",
    hashesDocumentos: {
      hashFSA: "0xmmm333...nnn444",
    },
  },
  {
    loteId: 5,
    kgEsperados: 400,
    kgCosechadosReal: 395,
    kgRedimidos: 395,
    precioPorTokenUSDC: 32,
    reservaTecnicaUSDC: 1920,
    reservaTecnicaLiberada: 1920,
    montoNetoPendiente: 0,
    fechaCosechaEstimada: Date.now() - 90 * 24 * 60 * 60 * 1000,
    estado: "AGOTADO",
    fechaCreacion: Date.now() - 270 * 24 * 60 * 60 * 1000,
    origenGeografico: "CB",
    reservaBps: 1500,
    variedadMonofloral: "Retama",
    productorSRL: "0xghi5...qrst",
    descripcion: "Miel de Retama del altiplano cochabambino. Sabor intenso con notas amargas y dulces. Totalmente redimida.",
    imagenUrl: "/images/honey-retama.jpg",
    hashesDocumentos: {
      hashFSA: "0xooo555...ppp666",
      hashSenasag: "0xqqq777...rrr888",
      hashAnalisisLab: "0xsss999...ttt000",
      hashActaCosecha: "0xuuu111...vvv222",
      hashFotosApiario: "0xwww333...xxx444",
      hashCertificadoOrigen: "0xyyy555...zzz666",
    },
  },
  {
    loteId: 6,
    kgEsperados: 250,
    kgCosechadosReal: 0,
    kgRedimidos: 0,
    precioPorTokenUSDC: 22,
    reservaTecnicaUSDC: 825,
    reservaTecnicaLiberada: 0,
    montoNetoPendiente: 4675,
    fechaCosechaEstimada: Date.now() - 5 * 24 * 60 * 60 * 1000,
    estado: "FALLIDO",
    fechaCreacion: Date.now() - 100 * 24 * 60 * 60 * 1000,
    origenGeografico: "TJ",
    reservaBps: 1500,
    variedadMonofloral: "Alfalfa",
    productorSRL: "0xjkl6...uvwx",
    descripcion: "Lote de miel de Alfalfa de Tarija. Cosecha afectada por sequía. Reembolso completo procesado.",
    imagenUrl: "/images/honey-alfalfa.jpg",
    motivoFallo: "Sequía prolongada afectó la producción. Cosecha insuficiente para cumplir estándares de calidad.",
    hashesDocumentos: {
      hashFSA: "0x777aaa...888bbb",
    },
  },
];

export function getTimeline(lote: LoteMiel): TimelineEvent[] {
  const events: TimelineEvent[] = [];
  const now = Date.now();

  events.push({
    fecha: lote.fechaCreacion,
    tipo: "Lote Creado",
    descripcion: `Lote registrado con ${lote.kgEsperados} kg esperados de miel ${lote.variedadMonofloral}`,
    hash: lote.hashesDocumentos.hashFSA,
    completado: true,
  });

  if (["COSECHADO", "ALMACENADO", "REDENCION_PARCIAL", "AGOTADO"].includes(lote.estado)) {
    events.push({
      fecha: lote.fechaCreacion + 60 * 24 * 60 * 60 * 1000,
      tipo: "Cosecha Confirmada",
      descripcion: `${lote.kgCosechadosReal} kg cosechados. Documentos verificados por SENASAG.`,
      hash: lote.hashesDocumentos.hashSenasag,
      completado: true,
    });
  }

  if (["ALMACENADO", "REDENCION_PARCIAL", "AGOTADO"].includes(lote.estado)) {
    events.push({
      fecha: lote.fechaCreacion + 75 * 24 * 60 * 60 * 1000,
      tipo: "Almacenamiento",
      descripcion: "Producto en almacén autorizado. Contrato de depósito registrado.",
      hash: lote.hashesDocumentos.hashActaCosecha,
      completado: true,
    });
  }

  if (lote.estado === "REDENCION_PARCIAL") {
    events.push({
      fecha: lote.fechaCreacion + 90 * 24 * 60 * 60 * 1000,
      tipo: "Redención Parcial",
      descripcion: `${lote.kgRedimidos} kg de ${lote.kgCosechadosReal} kg redimidos por compradores.`,
      completado: true,
    });
  }

  if (lote.estado === "AGOTADO") {
    events.push({
      fecha: lote.fechaCreacion + 120 * 24 * 60 * 60 * 1000,
      tipo: "Lote Agotado",
      descripcion: "Todos los tokens redimidos. Producto entregado completamente.",
      completado: true,
    });
  }

  if (lote.estado === "FALLIDO") {
    events.push({
      fecha: lote.fechaCreacion + 50 * 24 * 60 * 60 * 1000,
      tipo: "Lote Fallido",
      descripcion: lote.motivoFallo || "Cosecha no exitosa",
      completado: true,
    });
    events.push({
      fecha: lote.fechaCreacion + 55 * 24 * 60 * 60 * 1000,
      tipo: "Reembolso Procesado",
      descripcion: "100% del USDC devuelto a compradores.",
      completado: true,
    });
  }

  if (lote.estado === "PREVENTA") {
    events.push({
      fecha: lote.fechaCosechaEstimada,
      tipo: "Cosecha Estimada",
      descripcion: "Fecha estimada de cosecha. El productor debe confirmar la producción.",
      completado: false,
    });
  }

  if (["PREVENTA", "COSECHADO"].includes(lote.estado)) {
    events.push({
      fecha: lote.fechaCosechaEstimada + 30 * 24 * 60 * 60 * 1000,
      tipo: "Almacenamiento Estimado",
      descripcion: "Estimación de ingreso a almacén autorizado.",
      completado: false,
    });
  }

  return events.sort((a, b) => a.fecha - b.fecha);
}

export function getKgDisponibles(lote: LoteMiel): number {
  const gramosEsperados = lote.kgEsperados * 1000;
  const gramosVendidos = lote.kgRedimidos * 1000;
  return Math.max(0, (gramosEsperados - gramosVendidos) / 1000);
}

export function getTokensDisponibles(lote: LoteMiel): number {
  return Math.floor(getKgDisponibles(lote) / 0.5);
}

export function getProgreso(lote: LoteMiel): number {
  if (lote.estado === "AGOTADO") return 100;
  if (lote.estado === "FALLIDO") return 0;
  if (lote.estado === "PREVENTA") return 0;
  if (lote.estado === "COSECHADO") return 33;
  if (lote.estado === "ALMACENADO") return 66;
  if (lote.estado === "REDENCION_PARCIAL") {
    return Math.round((lote.kgRedimidos / lote.kgCosechadosReal) * 100);
  }
  return 0;
}

export function formatUSDC(amount: number): string {
  return `$${amount.toLocaleString()} USDC`;
}

export function formatDate(timestamp: number): string {
  return new Date(timestamp).toLocaleDateString("es-BO", {
    year: "numeric",
    month: "short",
    day: "numeric",
  });
}

export function getEstadoColor(estado: LoteEstado): string {
  switch (estado) {
    case "PREVENTA": return "bg-info/10 text-info border-info/20";
    case "COSECHADO": return "bg-warning/10 text-warning border-warning/20";
    case "ALMACENADO": return "bg-primary/10 text-primary border-primary/20";
    case "REDENCION_PARCIAL": return "bg-accent/10 text-accent border-accent/20";
    case "AGOTADO": return "bg-success/10 text-success border-success/20";
    case "FALLIDO": return "bg-danger/10 text-danger border-danger/20";
    default: return "bg-muted/10 text-muted border-muted/20";
  }
}

export function getEstadoLabel(estado: LoteEstado): string {
  switch (estado) {
    case "PREVENTA": return "En Preventa";
    case "COSECHADO": return "Cosechado";
    case "ALMACENADO": return "Almacenado";
    case "REDENCION_PARCIAL": return "Redención Parcial";
    case "AGOTADO": return "Agotado";
    case "FALLIDO": return "Fallido";
    default: return estado;
  }
}
