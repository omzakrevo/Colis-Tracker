import { useEffect, useRef, useState, useCallback } from "react";
import {
  useGetColisByNumero,
  useUpdateStatutColis,
  useRetirerColis,
} from "@workspace/api-client-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent } from "@/components/ui/card";
import { Camera, QrCode, X, PackageCheck, PackageOpen, CheckCircle2, AlertCircle, ChevronRight } from "lucide-react";
import { ColisBadge } from "./colis/index";
import { SignaturePad } from "@/components/signature-pad";

// ─── Types ────────────────────────────────────────────────────────────────────

type ScanMode = "embarquement" | "deparquement" | "remise";

type Phase =
  | "idle"       // mode not selected
  | "scanning"   // camera / manual input active
  | "processing" // QR detected, fetching colis
  | "retrait"    // remise mode: show retrait form
  | "feedback";  // brief flash after auto-action (chain modes)

interface LogEntry {
  id: number;
  numero: string;
  description: string;
  ok: boolean;
  ts: string;
}

// ─── Mode config ──────────────────────────────────────────────────────────────

const MODES = {
  embarquement: {
    label: "Embarquement",
    sub: "Charger les colis sur le véhicule",
    icon: PackageCheck,
    validStatuts: ["enregistre"],
    targetStatut: "charge",
    noteAuto: "Chargement validé par scan",
    colorClass: "bg-orange-500",
    borderClass: "border-orange-400",
    textClass: "text-orange-600",
    lightClass: "bg-orange-50",
    autoConfirm: true,
  },
  deparquement: {
    label: "Débarquement",
    sub: "Valider l'arrivée des colis en gare",
    icon: PackageOpen,
    validStatuts: ["en_route", "charge"],
    targetStatut: "arrive",
    noteAuto: "Arrivée validée par scan",
    colorClass: "bg-green-600",
    borderClass: "border-green-400",
    textClass: "text-green-700",
    lightClass: "bg-green-50",
    autoConfirm: true,
  },
  remise: {
    label: "Remise client",
    sub: "Remettre un colis à son destinataire",
    icon: CheckCircle2,
    validStatuts: ["arrive"],
    targetStatut: "retire",
    noteAuto: "",
    colorClass: "bg-blue-600",
    borderClass: "border-blue-400",
    textClass: "text-blue-700",
    lightClass: "bg-blue-50",
    autoConfirm: false,
  },
} as const satisfies Record<ScanMode, {
  label: string; sub: string; icon: any;
  validStatuts: readonly string[]; targetStatut: string; noteAuto: string;
  colorClass: string; borderClass: string; textClass: string; lightClass: string;
  autoConfirm: boolean;
}>;

// ─── Camera component ─────────────────────────────────────────────────────────

function CameraScanner({ onScan }: { onScan: (v: string) => void }) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const rafRef = useRef<number | null>(null);
  const [active, setActive] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [supported] = useState(() => "BarcodeDetector" in window);

  const stopCamera = useCallback(() => {
    if (rafRef.current != null) { cancelAnimationFrame(rafRef.current); rafRef.current = null; }
    if (streamRef.current) { streamRef.current.getTracks().forEach((t) => t.stop()); streamRef.current = null; }
    setActive(false);
  }, []);

  useEffect(() => () => stopCamera(), [stopCamera]);

  const startCamera = async () => {
    setError(null);
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "environment", width: { ideal: 640 }, height: { ideal: 480 } },
      });
      streamRef.current = stream;
      const video = videoRef.current;
      if (!video) { stream.getTracks().forEach((t) => t.stop()); return; }
      video.srcObject = stream;
      await video.play();
      setActive(true);
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const detector = new (window as any).BarcodeDetector({ formats: ["qr_code"] });
      const tick = async () => {
        if (!streamRef.current) return;
        const v = videoRef.current;
        if (v && v.readyState >= HTMLMediaElement.HAVE_ENOUGH_DATA) {
          try {
            const codes = await detector.detect(v);
            if (codes.length > 0) { stopCamera(); onScan(codes[0].rawValue as string); return; }
          } catch { /* ignore */ }
        }
        rafRef.current = requestAnimationFrame(tick);
      };
      rafRef.current = requestAnimationFrame(tick);
    } catch {
      setError("Impossible d'accéder à la caméra. Vérifiez les permissions.");
    }
  };

  if (!supported) {
    return (
      <p className="text-sm text-muted-foreground text-center py-4">
        Scanner non disponible sur ce navigateur. Utilisez <strong>Chrome</strong> sur Android ou la saisie manuelle.
      </p>
    );
  }

  return (
    <div className="space-y-3">
      <div className="relative w-full aspect-[4/3] bg-black rounded-xl overflow-hidden">
        <video ref={videoRef} muted playsInline className={`w-full h-full object-cover ${active ? "opacity-100" : "opacity-0"}`} />
        {!active && <div className="absolute inset-0 flex items-center justify-center"><Camera className="w-12 h-12 text-white/20" /></div>}
        {active && (
          <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
            <div className="w-52 h-52 border-2 border-white rounded-2xl shadow-[0_0_0_9999px_rgba(0,0,0,0.45)]" />
            <div className="absolute bottom-6 text-white/80 text-xs font-medium tracking-wide">Pointez vers le QR code</div>
          </div>
        )}
      </div>
      {error && <p className="text-sm text-destructive text-center">{error}</p>}
      {!active
        ? <Button className="w-full" onClick={startCamera}><QrCode className="w-4 h-4 mr-2" />Activer la caméra</Button>
        : <Button variant="outline" className="w-full" onClick={stopCamera}><X className="w-4 h-4 mr-2" />Arrêter la caméra</Button>
      }
    </div>
  );
}

// ─── Auto-action processor (chain modes: embarquement / débarquement) ─────────

function ChainProcessor({
  numero,
  mode,
  onDone,
}: {
  numero: string;
  mode: ScanMode;
  onDone: (ok: boolean, msg: string, colisInfo?: string) => void;
}) {
  const cfg = MODES[mode];
  const { data: colis, isLoading, isError } = useGetColisByNumero(numero);
  const updateStatut = useUpdateStatutColis();
  const doneRef = useRef(false);

  useEffect(() => {
    if (doneRef.current || isLoading || !cfg.autoConfirm) return;
    if (isError || !colis) {
      doneRef.current = true;
      onDone(false, "Colis introuvable");
      return;
    }
    if (!cfg.validStatuts.includes(colis.statut as never)) {
      doneRef.current = true;
      const statutLabels: Record<string, string> = { enregistre: "Enregistré", charge: "Chargé", en_route: "En route", arrive: "Arrivé", retire: "Retiré", annule: "Annulé" };
      onDone(false, `Statut invalide : ${statutLabels[colis.statut] ?? colis.statut}`);
      return;
    }
    doneRef.current = true;
    updateStatut.mutate(
      { id: colis.id, data: { statut: cfg.targetStatut as any, notes: cfg.noteAuto } },
      {
        onSuccess: () => onDone(true, `${colis.expediteur_nom} → ${colis.destinataire_nom}`, colis.gare_arrivee_nom ?? ""),
        onError: () => onDone(false, "Erreur lors de la mise à jour"),
      }
    );
  }, [colis, isLoading, isError]); // eslint-disable-line

  if (isLoading) {
    return <p className="text-center text-muted-foreground py-4 animate-pulse">Recherche du colis…</p>;
  }
  return null;
}

// ─── Retrait form (remise mode) ───────────────────────────────────────────────

function RetraitForm({
  numero,
  onDone,
  onCancel,
}: {
  numero: string;
  onDone: () => void;
  onCancel: () => void;
}) {
  const { data: colis, isLoading, isError } = useGetColisByNumero(numero);
  const retirer = useRetirerColis();
  const [nom, setNom] = useState("");
  const [tel, setTel] = useState("");
  const [piece, setPiece] = useState("");
  const [signature, setSignature] = useState<string | null>(null);

  if (isLoading) return <p className="text-center text-muted-foreground py-6 animate-pulse">Chargement…</p>;
  if (isError || !colis) {
    return (
      <div className="text-center py-6 space-y-3">
        <AlertCircle className="w-10 h-10 text-destructive mx-auto" />
        <p className="font-semibold text-destructive">Colis introuvable</p>
        <p className="text-sm text-muted-foreground">{numero}</p>
        <Button variant="outline" className="w-full" onClick={onCancel}>Réessayer</Button>
      </div>
    );
  }
  if (colis.statut !== "arrive") {
    const statutLabels: Record<string, string> = { enregistre: "Enregistré", charge: "Chargé", en_route: "En route", arrive: "Arrivé", retire: "Retiré", annule: "Annulé" };
    return (
      <div className="text-center py-6 space-y-3">
        <AlertCircle className="w-10 h-10 text-orange-500 mx-auto" />
        <p className="font-semibold">Ce colis n'est pas disponible</p>
        <p className="text-sm text-muted-foreground">Statut actuel : <ColisBadge statut={colis.statut} /></p>
        <p className="text-xs text-muted-foreground">Seuls les colis <strong>Arrivé</strong> peuvent être remis.</p>
        <Button variant="outline" className="w-full" onClick={onCancel}>Retour</Button>
      </div>
    );
  }

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!nom || !tel) return;
    retirer.mutate(
      { id: colis.id, data: { retrait_nom: nom, retrait_telephone: tel, retrait_piece_identite: piece || undefined, retrait_signature: signature || undefined } },
      { onSuccess: onDone, onError: () => {} }
    );
  };

  return (
    <div className="space-y-4">
      {/* Colis summary */}
      <div className="bg-blue-50 border border-blue-200 rounded-xl p-4 space-y-2">
        <div className="flex items-center justify-between">
          <span className="font-bold text-blue-900">{colis.numero}</span>
          <ColisBadge statut={colis.statut} />
        </div>
        <p className="text-sm font-semibold">{colis.destinataire_nom}</p>
        <p className="text-xs text-muted-foreground">{colis.gare_depart_nom} → {colis.gare_arrivee_nom}</p>
        <p className="text-sm font-bold text-blue-700">{colis.prix.toLocaleString("fr-FR")} FCFA</p>
      </div>

      <form onSubmit={handleSubmit} className="space-y-3">
        <div className="space-y-1">
          <Label>Nom du retrayant *</Label>
          <Input required value={nom} onChange={(e) => setNom(e.target.value)} placeholder="Nom complet" />
        </div>
        <div className="space-y-1">
          <Label>Téléphone *</Label>
          <Input required value={tel} onChange={(e) => setTel(e.target.value)} placeholder="+226…" />
        </div>
        <div className="space-y-1">
          <Label>Pièce d'identité (optionnel)</Label>
          <Input value={piece} onChange={(e) => setPiece(e.target.value)} placeholder="CNI, Passeport…" />
        </div>
        <div className="space-y-1">
          <Label>Signature *</Label>
          <SignaturePad onChange={setSignature} />
        </div>
        <Button type="submit" className="w-full bg-blue-600 hover:bg-blue-700 text-white" disabled={!nom || !tel || !signature || retirer.isPending}>
          {retirer.isPending ? "En cours…" : "Confirmer le retrait"}
        </Button>
        <Button type="button" variant="outline" className="w-full" onClick={onCancel}>Annuler</Button>
      </form>
    </div>
  );
}

// ─── Main page ────────────────────────────────────────────────────────────────

let logIdCounter = 0;

export default function Scanner() {
  const [mode, setMode] = useState<ScanMode | null>(null);
  const [phase, setPhase] = useState<Phase>("idle");
  const [scannedNumero, setScannedNumero] = useState<string | null>(null);
  const [manualInput, setManualInput] = useState("");
  const [cameraKey, setCameraKey] = useState(0);
  const [feedback, setFeedback] = useState<{ ok: boolean; msg: string; sub?: string } | null>(null);
  const [log, setLog] = useState<LogEntry[]>([]);

  // Select mode → enter scanning phase
  const selectMode = (m: ScanMode) => {
    setMode(m);
    setPhase("scanning");
    setScannedNumero(null);
    setManualInput("");
    setFeedback(null);
  };

  // Called when a QR is scanned or manual submitted
  const handleScan = (value: string) => {
    const numero = value.trim().toUpperCase();
    if (!numero) return;
    setScannedNumero(numero);
    setPhase(mode === "remise" ? "retrait" : "processing");
    setManualInput("");
  };

  // Called after ChainProcessor finishes
  const handleChainDone = (ok: boolean, msg: string, sub?: string) => {
    const entry: LogEntry = {
      id: ++logIdCounter,
      numero: scannedNumero ?? "",
      description: msg,
      ok,
      ts: new Date().toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit", second: "2-digit" }),
    };
    setLog((prev) => [entry, ...prev].slice(0, 20));
    setFeedback({ ok, msg, sub });
    setPhase("feedback");
    // Auto-restart scan after 2 seconds
    setTimeout(() => {
      setFeedback(null);
      setScannedNumero(null);
      setPhase("scanning");
      setCameraKey((k) => k + 1);
    }, 2000);
  };

  // Called after remise confirmed
  const handleRetraitDone = () => {
    const entry: LogEntry = {
      id: ++logIdCounter,
      numero: scannedNumero ?? "",
      description: "Retrait enregistré",
      ok: true,
      ts: new Date().toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit", second: "2-digit" }),
    };
    setLog((prev) => [entry, ...prev].slice(0, 20));
    setFeedback({ ok: true, msg: "Retrait enregistré !", sub: scannedNumero ?? "" });
    setPhase("feedback");
    setTimeout(() => {
      setFeedback(null);
      setScannedNumero(null);
      setPhase("scanning");
      setCameraKey((k) => k + 1);
    }, 2000);
  };

  const handleCancel = () => {
    setScannedNumero(null);
    setPhase("scanning");
    setCameraKey((k) => k + 1);
  };

  const handleManualSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!manualInput.trim()) return;
    handleScan(manualInput);
  };

  const cfg = mode ? MODES[mode] : null;

  // ── Idle: mode selection ───────────────────────────────────────────────────
  if (!mode || phase === "idle") {
    return (
      <div className="space-y-6 max-w-lg w-full mx-auto">
        <div>
          <h1 className="text-3xl font-bold tracking-tight flex items-center gap-3">
            <QrCode className="w-8 h-8 text-primary" /> Scanner QR
          </h1>
          <p className="text-muted-foreground">Sélectionnez une opération pour commencer.</p>
        </div>

        <div className="grid gap-3">
          {(Object.entries(MODES) as [ScanMode, typeof MODES[ScanMode]][]).map(([key, m]) => {
            const Icon = m.icon;
            return (
              <button
                key={key}
                onClick={() => selectMode(key)}
                className={`flex items-center gap-4 w-full text-left p-5 rounded-2xl border-2 ${m.borderClass} ${m.lightClass} hover:opacity-90 transition-opacity`}
              >
                <div className={`w-12 h-12 rounded-xl ${m.colorClass} flex items-center justify-center shrink-0`}>
                  <Icon className="w-6 h-6 text-white" />
                </div>
                <div className="flex-1 min-w-0">
                  <p className={`font-bold text-lg ${m.textClass}`}>{m.label}</p>
                  <p className="text-sm text-muted-foreground">{m.sub}</p>
                </div>
                <ChevronRight className="w-5 h-5 text-muted-foreground shrink-0" />
              </button>
            );
          })}
        </div>
      </div>
    );
  }

  const Icon = cfg!.icon;

  return (
    <div className="space-y-5 max-w-lg w-full mx-auto">
      {/* Header */}
      <div className="flex items-center gap-3">
        <button onClick={() => { setMode(null); setPhase("idle"); setLog([]); setFeedback(null); setScannedNumero(null); }}
          className="text-sm text-muted-foreground hover:text-foreground transition-colors">← Retour</button>
        <div className={`flex items-center gap-2 px-3 py-1.5 rounded-full ${cfg!.colorClass} text-white`}>
          <Icon className="w-4 h-4" />
          <span className="text-sm font-semibold">{cfg!.label}</span>
        </div>
        {log.length > 0 && (
          <span className="ml-auto text-sm text-muted-foreground">{log.filter(l => l.ok).length}/{log.length} OK</span>
        )}
      </div>

      {/* Feedback flash (chain modes after action) */}
      {phase === "feedback" && feedback && (
        <div className={`rounded-2xl p-6 text-center space-y-2 border-2 ${feedback.ok ? "bg-green-50 border-green-300" : "bg-red-50 border-red-300"}`}>
          {feedback.ok
            ? <CheckCircle2 className="w-14 h-14 text-green-500 mx-auto" />
            : <AlertCircle className="w-14 h-14 text-red-400 mx-auto" />
          }
          <p className={`font-bold text-lg ${feedback.ok ? "text-green-700" : "text-red-600"}`}>
            {feedback.ok ? (mode === "embarquement" ? "Chargé ✓" : mode === "deparquement" ? "Arrivée validée ✓" : "Remis ✓") : "Échec"}
          </p>
          <p className="text-sm text-muted-foreground">{feedback.msg}</p>
          {feedback.sub && <p className="text-xs text-muted-foreground">{feedback.sub}</p>}
          <p className="text-xs text-muted-foreground mt-2 animate-pulse">Scan suivant dans un instant…</p>
        </div>
      )}

      {/* ChainProcessor: only mounts in processing phase */}
      {phase === "processing" && scannedNumero && mode !== "remise" && (
        <div className="rounded-xl border bg-card p-4">
          <p className="text-sm text-muted-foreground mb-3">Numéro : <strong className="text-foreground">{scannedNumero}</strong></p>
          <ChainProcessor
            key={scannedNumero}
            numero={scannedNumero}
            mode={mode}
            onDone={handleChainDone}
          />
        </div>
      )}

      {/* Retrait form: remise mode */}
      {phase === "retrait" && scannedNumero && (
        <div className="rounded-xl border bg-card p-5">
          <p className="text-xs text-muted-foreground mb-4">Numéro scanné : <strong>{scannedNumero}</strong></p>
          <RetraitForm
            key={scannedNumero}
            numero={scannedNumero}
            onDone={handleRetraitDone}
            onCancel={handleCancel}
          />
        </div>
      )}

      {/* Camera + manual input: visible in scanning phase */}
      {phase === "scanning" && (
        <div className="space-y-4">
          <Card>
            <CardContent className="pt-4 pb-4">
              <CameraScanner key={cameraKey} onScan={handleScan} />
            </CardContent>
          </Card>
          <div className="relative flex items-center gap-3">
            <div className="flex-1 h-px bg-border" />
            <span className="text-xs text-muted-foreground shrink-0">ou saisie manuelle</span>
            <div className="flex-1 h-px bg-border" />
          </div>
          <form onSubmit={handleManualSubmit} className="flex gap-2">
            <Input
              value={manualInput}
              onChange={(e) => setManualInput(e.target.value.toUpperCase())}
              placeholder="Ex: COL-2026-000001"
              className="flex-1 font-mono"
            />
            <Button type="submit" disabled={!manualInput.trim()}>OK</Button>
          </form>
        </div>
      )}

      {/* Session log */}
      {log.length > 0 && (
        <div className="space-y-2">
          <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">Session en cours</p>
          <div className="space-y-1.5 max-h-52 overflow-y-auto">
            {log.map((entry) => (
              <div key={entry.id}
                className={`flex items-center gap-3 px-3 py-2 rounded-lg text-sm ${entry.ok ? "bg-green-50 border border-green-200" : "bg-red-50 border border-red-200"}`}>
                {entry.ok
                  ? <CheckCircle2 className="w-4 h-4 text-green-500 shrink-0" />
                  : <AlertCircle className="w-4 h-4 text-red-400 shrink-0" />
                }
                <span className="font-mono text-xs font-semibold shrink-0">{entry.numero}</span>
                <span className="text-muted-foreground truncate flex-1">{entry.description}</span>
                <span className="text-xs text-muted-foreground shrink-0">{entry.ts}</span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
