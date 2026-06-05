import { useEffect, useRef, useState } from "react";
import {
  useGetColisByNumero,
  useUpdateStatutColis,
  useRetirerColis,
} from "@workspace/api-client-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { useToast } from "@/hooks/use-toast";
import { QrCode, CheckCircle2, PackageCheck, X, RefreshCw } from "lucide-react";
import { Link } from "wouter";
import { ColisBadge } from "./colis/index";

const STATUTS_LABELS: Record<string, string> = {
  enregistre: "Enregistré",
  charge: "Chargé",
  en_route: "En route",
  arrive: "Arrivé",
  retire: "Retiré",
  annule: "Annulé",
};

/* ── Sub-component: only mounts when we have a numero to look up ── */
function ColisResult({
  numero,
  onReset,
}: {
  numero: string;
  onReset: () => void;
}) {
  const { toast } = useToast();
  const { data: colis, isLoading, isError, refetch } = useGetColisByNumero(numero);
  const updateStatut = useUpdateStatutColis();
  const retirer = useRetirerColis();

  const [retraitDialogOpen, setRetraitDialogOpen] = useState(false);
  const [retraitNom, setRetraitNom] = useState("");
  const [retraitTel, setRetraitTel] = useState("");
  const [retraitPiece, setRetraitPiece] = useState("");

  const handleValiderChargement = () => {
    if (!colis) return;
    updateStatut.mutate(
      { id: colis.id, data: { statut: "charge", notes: "Chargement validé par scan" } },
      {
        onSuccess: () => { toast({ title: "Chargement validé !" }); refetch(); },
        onError: () => toast({ title: "Erreur", variant: "destructive" }),
      }
    );
  };

  const handleValiderArrivee = () => {
    if (!colis) return;
    updateStatut.mutate(
      { id: colis.id, data: { statut: "arrive", notes: "Arrivée validée par scan" } },
      {
        onSuccess: () => { toast({ title: "Arrivée validée !" }); refetch(); },
        onError: () => toast({ title: "Erreur", variant: "destructive" }),
      }
    );
  };

  const handleRetrait = () => {
    if (!colis || !retraitNom || !retraitTel) return;
    retirer.mutate(
      {
        id: colis.id,
        data: {
          retrait_nom: retraitNom,
          retrait_telephone: retraitTel,
          retrait_piece_identite: retraitPiece || undefined,
        },
      },
      {
        onSuccess: () => {
          toast({ title: "Retrait enregistré !" });
          setRetraitDialogOpen(false);
          refetch();
        },
        onError: () => toast({ title: "Erreur", variant: "destructive" }),
      }
    );
  };

  if (isLoading) {
    return (
      <Card>
        <CardContent className="py-8 text-center text-muted-foreground">
          Recherche du colis…
        </CardContent>
      </Card>
    );
  }

  if (isError || !colis) {
    return (
      <Card className="border-destructive/30 bg-destructive/5">
        <CardContent className="py-6 text-center">
          <p className="font-semibold text-destructive">Colis introuvable</p>
          <p className="text-sm text-muted-foreground mt-1">
            Aucun colis avec le numéro <strong>{numero}</strong>
          </p>
          <Button variant="outline" className="mt-4" onClick={onReset}>
            Réessayer
          </Button>
        </CardContent>
      </Card>
    );
  }

  return (
    <>
      <div className="space-y-4">
        {/* Colis info card */}
        <Card className="border-primary/30 bg-primary/5">
          <CardHeader className="pb-3">
            <div className="flex items-start justify-between">
              <div>
                <CardTitle className="text-lg">{colis.numero}</CardTitle>
                <div className="mt-1"><ColisBadge statut={colis.statut} /></div>
              </div>
              <Link href={`/colis/${colis.id}`}>
                <Button variant="outline" size="sm">Voir détail</Button>
              </Link>
            </div>
          </CardHeader>
          <CardContent className="space-y-3 text-sm">
            <div className="grid grid-cols-2 gap-2">
              <div>
                <p className="text-xs text-muted-foreground">Expéditeur</p>
                <p className="font-semibold">{colis.expediteur_nom}</p>
                <p className="text-xs text-muted-foreground">{colis.expediteur_telephone}</p>
              </div>
              <div>
                <p className="text-xs text-muted-foreground">Destinataire</p>
                <p className="font-semibold">{colis.destinataire_nom}</p>
                <p className="text-xs text-muted-foreground">{colis.destinataire_telephone}</p>
              </div>
            </div>
            <div className="bg-white/70 rounded-md p-2 text-center font-medium">
              {colis.gare_depart_nom} → {colis.gare_arrivee_nom}
            </div>
            <p className="text-center font-bold text-primary text-base">
              {colis.prix.toLocaleString("fr-FR")} FCFA
            </p>
          </CardContent>
        </Card>

        {/* Action buttons */}
        {colis.statut === "enregistre" && (
          <Button className="w-full" onClick={handleValiderChargement} disabled={updateStatut.isPending}>
            <PackageCheck className="w-4 h-4 mr-2" />
            {updateStatut.isPending ? "En cours…" : "Valider le chargement"}
          </Button>
        )}

        {colis.statut === "en_route" && (
          <Button
            className="w-full bg-green-600 hover:bg-green-700 text-white"
            onClick={handleValiderArrivee}
            disabled={updateStatut.isPending}
          >
            <CheckCircle2 className="w-4 h-4 mr-2" />
            {updateStatut.isPending ? "En cours…" : "Valider l'arrivée en gare"}
          </Button>
        )}

        {colis.statut === "arrive" && (
          <Button
            className="w-full bg-green-600 hover:bg-green-700 text-white"
            onClick={() => setRetraitDialogOpen(true)}
          >
            <CheckCircle2 className="w-4 h-4 mr-2" /> Enregistrer le retrait
          </Button>
        )}

        {(colis.statut === "retire" || colis.statut === "annule" || colis.statut === "charge") && (
          <Card className="border-muted">
            <CardContent className="py-4 text-center text-muted-foreground text-sm">
              Ce colis est <strong>{STATUTS_LABELS[colis.statut]}</strong>.{" "}
              {colis.statut === "charge" ? "Aucune action de scan disponible." : "Aucune action disponible."}
            </CardContent>
          </Card>
        )}
      </div>

      {/* Retrait dialog */}
      <Dialog open={retraitDialogOpen} onOpenChange={setRetraitDialogOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle>Enregistrer le retrait</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1">
              <Label>Nom du retrayant *</Label>
              <Input value={retraitNom} onChange={(e) => setRetraitNom(e.target.value)} placeholder="Nom complet" />
            </div>
            <div className="space-y-1">
              <Label>Téléphone *</Label>
              <Input value={retraitTel} onChange={(e) => setRetraitTel(e.target.value)} placeholder="+226…" />
            </div>
            <div className="space-y-1">
              <Label>Pièce d'identité (optionnel)</Label>
              <Input value={retraitPiece} onChange={(e) => setRetraitPiece(e.target.value)} placeholder="CNI, Passeport…" />
            </div>
            <Button
              className="w-full"
              onClick={handleRetrait}
              disabled={!retraitNom || !retraitTel || retirer.isPending}
            >
              {retirer.isPending ? "En cours…" : "Confirmer le retrait"}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </>
  );
}

/* ── Main scanner page ── */
export default function Scanner() {
  const scannerRef = useRef<any>(null);
  const [scannedNumero, setScannedNumero] = useState<string | null>(null);
  const [manualInput, setManualInput] = useState("");
  const [scannerActive, setScannerActive] = useState(false);
  const [cameraError, setCameraError] = useState<string | null>(null);

  const startScanner = async () => {
    if (scannerRef.current) return;
    try {
      const { Html5Qrcode } = await import("html5-qrcode");
      const scanner = new Html5Qrcode("qr-reader-container");
      scannerRef.current = scanner;
      await scanner.start(
        { facingMode: "environment" },
        { fps: 10, qrbox: { width: 250, height: 250 } },
        (decoded: string) => {
          const clean = decoded.trim().toUpperCase();
          setScannedNumero(clean);
          stopScanner();
        },
        () => {}
      );
      setScannerActive(true);
      setCameraError(null);
    } catch {
      setCameraError("Impossible d'accéder à la caméra. Vérifiez les permissions.");
      setScannerActive(false);
    }
  };

  const stopScanner = () => {
    if (!scannerRef.current) return;
    scannerRef.current.stop().catch(() => {}).finally(() => {
      scannerRef.current = null;
      setScannerActive(false);
    });
  };

  useEffect(() => { return () => { stopScanner(); }; }, []);

  const reset = () => {
    setScannedNumero(null);
    setManualInput("");
  };

  const handleManualSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!manualInput.trim()) return;
    setScannedNumero(manualInput.trim().toUpperCase());
  };

  return (
    <div className="space-y-6 max-w-lg w-full mx-auto">
      <div>
        <h1 className="text-3xl font-bold tracking-tight flex items-center gap-3">
          <QrCode className="w-8 h-8 text-primary" /> Scanner QR
        </h1>
        <p className="text-muted-foreground">
          Scannez le QR d'un colis pour valider la réception ou le retrait.
        </p>
      </div>

      {!scannedNumero ? (
        <div className="space-y-4">
          {/* Camera scanner */}
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-sm font-semibold">Scanner avec la caméra</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <div
                id="qr-reader-container"
                className="w-full rounded-lg overflow-hidden bg-black min-h-[220px] flex items-center justify-center"
              >
                {!scannerActive && (
                  <p className="text-white/40 text-sm">Caméra inactive</p>
                )}
              </div>
              {cameraError && (
                <p className="text-sm text-destructive">{cameraError}</p>
              )}
              <div className="flex gap-2">
                {!scannerActive ? (
                  <Button className="flex-1" onClick={startScanner}>
                    <QrCode className="w-4 h-4 mr-2" /> Activer la caméra
                  </Button>
                ) : (
                  <Button variant="outline" className="flex-1" onClick={stopScanner}>
                    <X className="w-4 h-4 mr-2" /> Arrêter
                  </Button>
                )}
              </div>
            </CardContent>
          </Card>

          {/* Manual input fallback */}
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-sm font-semibold">Saisie manuelle</CardTitle>
            </CardHeader>
            <CardContent>
              <form onSubmit={handleManualSubmit} className="flex gap-2">
                <Input
                  value={manualInput}
                  onChange={(e) => setManualInput(e.target.value.toUpperCase())}
                  placeholder="Ex: COL-2026-000001"
                  className="flex-1"
                />
                <Button type="submit" disabled={!manualInput.trim()}>
                  Rechercher
                </Button>
              </form>
            </CardContent>
          </Card>
        </div>
      ) : (
        <div className="space-y-4">
          {/* Scanned header */}
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2 text-sm text-muted-foreground">
              <QrCode className="w-4 h-4" />
              <span>Numéro : <strong className="text-foreground">{scannedNumero}</strong></span>
            </div>
            <Button variant="ghost" size="sm" onClick={reset}>
              <RefreshCw className="w-4 h-4 mr-1" /> Nouveau scan
            </Button>
          </div>

          {/* Lookup result — unmounts/remounts on each new scan */}
          <ColisResult key={scannedNumero} numero={scannedNumero} onReset={reset} />
        </div>
      )}
    </div>
  );
}
