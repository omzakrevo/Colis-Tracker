import { useParams, useLocation } from "wouter";
import {
  useGetColis,
  useGetHistoriqueColis,
  useUpdateStatutColis,
  useRetirerColis,
  useGetMe,
} from "@workspace/api-client-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { useToast } from "@/hooks/use-toast";
import { ArrowLeft, Printer, Package, User, MapPin, Clock, CheckCircle2 } from "lucide-react";
import { Link } from "wouter";
import { useState } from "react";
import { ColisBadge } from "./index";

const STATUTS_LABELS: Record<string, string> = {
  enregistre: "Enregistré",
  charge: "Chargé",
  en_route: "En route",
  arrive: "Arrivé",
  retire: "Retiré",
  annule: "Annulé",
};

const STATUTS_TRANSITIONS: Record<string, string[]> = {
  enregistre: ["charge", "annule"],
  charge: ["en_route", "annule"],
  en_route: ["arrive", "annule"],
  arrive: ["annule"],
  retire: [],
  annule: [],
};

export default function ColisDetail() {
  const { id } = useParams();
  const [, setLocation] = useLocation();
  const { toast } = useToast();
  const { data: colis, refetch } = useGetColis(Number(id));
  const { data: historique, refetch: refetchHisto } = useGetHistoriqueColis(Number(id));
  const { data: me } = useGetMe();
  const updateStatut = useUpdateStatutColis();
  const retirer = useRetirerColis();

  const [statutDialogOpen, setStatutDialogOpen] = useState(false);
  const [retraitDialogOpen, setRetraitDialogOpen] = useState(false);
  const [newStatut, setNewStatut] = useState("");
  const [statutNotes, setStatutNotes] = useState("");
  const [retraitNom, setRetraitNom] = useState("");
  const [retraitTel, setRetraitTel] = useState("");
  const [retraitPiece, setRetraitPiece] = useState("");

  if (!colis) {
    return (
      <div className="flex items-center justify-center p-16 text-muted-foreground">
        Chargement...
      </div>
    );
  }

  const handleUpdateStatut = () => {
    if (!newStatut) return;
    updateStatut.mutate(
      { id: Number(id), data: { statut: newStatut as any, notes: statutNotes || undefined } },
      {
        onSuccess: () => {
          toast({ title: "Statut mis à jour" });
          setStatutDialogOpen(false);
          setNewStatut("");
          setStatutNotes("");
          refetch();
          refetchHisto();
        },
        onError: () => toast({ title: "Erreur", variant: "destructive" }),
      }
    );
  };

  const handleRetrait = () => {
    if (!retraitNom || !retraitTel) return;
    retirer.mutate(
      {
        id: Number(id),
        data: {
          retrait_nom: retraitNom,
          retrait_telephone: retraitTel,
          retrait_piece_identite: retraitPiece || undefined,
        },
      },
      {
        onSuccess: () => {
          toast({ title: "Retrait enregistré avec succès" });
          setRetraitDialogOpen(false);
          refetch();
          refetchHisto();
        },
        onError: () => toast({ title: "Erreur", variant: "destructive" }),
      }
    );
  };

  const nextStatuts = STATUTS_TRANSITIONS[colis.statut] ?? [];
  const canRetirer = colis.statut === "arrive";
  const canChangeStatut = nextStatuts.length > 0;

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row justify-between items-start gap-4 print:hidden">
        <div className="flex items-start gap-3">
          <Link href="/colis">
            <Button variant="ghost" size="sm" className="mt-1">
              <ArrowLeft className="w-4 h-4 mr-1" /> Retour
            </Button>
          </Link>
          <div>
            <h1 className="text-2xl font-bold tracking-tight">{colis.numero}</h1>
            <div className="mt-1">
              <ColisBadge statut={colis.statut} />
            </div>
          </div>
        </div>
        <div className="flex gap-2 flex-wrap w-full sm:w-auto">
          {canRetirer && (
            <Button
              onClick={() => setRetraitDialogOpen(true)}
              className="bg-green-600 hover:bg-green-700 text-white flex-1 sm:flex-none"
            >
              <CheckCircle2 className="w-4 h-4 mr-2" /> Retrait
            </Button>
          )}
          {canChangeStatut && (
            <Button
              variant="outline"
              onClick={() => setStatutDialogOpen(true)}
              className="flex-1 sm:flex-none"
            >
              Changer statut
            </Button>
          )}
          <Button variant="outline" onClick={() => window.print()} className="flex-1 sm:flex-none">
            <Printer className="w-4 h-4 mr-2" /> Imprimer
          </Button>
        </div>
      </div>

      {/* Print header */}
      <div className="hidden print:block text-center border-b pb-6 mb-6">
        <div className="text-3xl font-bold">VIP COLIS</div>
        <div className="text-lg text-gray-600">Reçu d'expédition</div>
        <div className="text-2xl font-bold mt-2">{colis.numero}</div>
        <div className="text-sm text-gray-500">
          Statut : {STATUTS_LABELS[colis.statut]} — Émis le {new Date().toLocaleDateString("fr-FR")}
        </div>
      </div>

      {/* Cards grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-semibold flex items-center gap-2">
              <User className="w-4 h-4 text-primary" /> Expéditeur
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <Row label="Nom" value={colis.expediteur_nom} bold />
            <Row label="Téléphone" value={colis.expediteur_telephone} />
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-semibold flex items-center gap-2">
              <User className="w-4 h-4 text-primary" /> Destinataire
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <Row label="Nom" value={colis.destinataire_nom} bold />
            <Row label="Téléphone" value={colis.destinataire_telephone} />
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-semibold flex items-center gap-2">
              <MapPin className="w-4 h-4 text-primary" /> Trajet
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <Row label="Départ" value={colis.gare_depart_nom ?? "—"} bold />
            <Row label="Arrivée" value={colis.gare_arrivee_nom ?? "—"} bold />
            <Row label="Date d'envoi" value={new Date(colis.date_envoi).toLocaleDateString("fr-FR")} />
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-semibold flex items-center gap-2">
              <Package className="w-4 h-4 text-primary" /> Colis
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <Row label="Description" value={colis.description} />
            <Row label="Nombre" value={String(colis.nombre)} />
            {colis.poids != null && <Row label="Poids" value={`${colis.poids} kg`} />}
            <Row label="Prix" value={`${colis.prix.toLocaleString("fr-FR")} FCFA`} bold />
            {colis.notes && <Row label="Notes" value={colis.notes} />}
          </CardContent>
        </Card>
      </div>

      {/* Retrait info */}
      {colis.statut === "retire" && colis.retrait_nom && (
        <Card className="border-green-200 bg-green-50">
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-semibold text-green-800 flex items-center gap-2">
              <CheckCircle2 className="w-4 h-4" /> Informations de retrait
            </CardTitle>
          </CardHeader>
          <CardContent className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-sm">
            <Row label="Retiré par" value={colis.retrait_nom} bold />
            <Row label="Téléphone" value={colis.retrait_telephone ?? "—"} />
            {colis.retrait_piece_identite && (
              <Row label="Pièce d'identité" value={colis.retrait_piece_identite} />
            )}
            {colis.retrait_date && (
              <Row label="Date" value={new Date(colis.retrait_date).toLocaleString("fr-FR")} />
            )}
          </CardContent>
        </Card>
      )}

      {/* Historique */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-sm font-semibold flex items-center gap-2">
            <Clock className="w-4 h-4 text-primary" /> Historique des statuts
          </CardTitle>
        </CardHeader>
        <CardContent>
          {(!historique || historique.length === 0) ? (
            <p className="text-sm text-muted-foreground">Aucun historique disponible.</p>
          ) : (
            <div>
              {historique.map((h, i) => (
                <div key={h.id} className="flex gap-3 pb-5 last:pb-0">
                  <div className="flex flex-col items-center shrink-0">
                    <div className="w-3 h-3 rounded-full bg-primary mt-0.5" />
                    {i < historique.length - 1 && (
                      <div className="w-px flex-1 bg-border mt-1" />
                    )}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex flex-wrap items-center gap-2 text-sm">
                      <ColisBadge statut={h.statut} />
                      <span className="text-muted-foreground text-xs">
                        {new Date(h.date_changement).toLocaleString("fr-FR")}
                      </span>
                      {h.agent_nom && (
                        <span className="text-muted-foreground text-xs">— {h.agent_nom}</span>
                      )}
                    </div>
                    {h.notes && (
                      <p className="mt-1 text-xs text-muted-foreground">{h.notes}</p>
                    )}
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Changer statut dialog */}
      <Dialog open={statutDialogOpen} onOpenChange={setStatutDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Changer le statut</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1">
              <Label>Nouveau statut</Label>
              <Select value={newStatut} onValueChange={setNewStatut}>
                <SelectTrigger>
                  <SelectValue placeholder="Sélectionner un statut" />
                </SelectTrigger>
                <SelectContent>
                  {nextStatuts.map((s) => (
                    <SelectItem key={s} value={s}>
                      {STATUTS_LABELS[s]}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label>Notes (optionnel)</Label>
              <Textarea
                value={statutNotes}
                onChange={(e) => setStatutNotes(e.target.value)}
                placeholder="Informations complémentaires..."
                rows={3}
              />
            </div>
            <Button
              className="w-full"
              onClick={handleUpdateStatut}
              disabled={!newStatut || updateStatut.isPending}
            >
              {updateStatut.isPending ? "En cours..." : "Confirmer"}
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Retrait dialog */}
      <Dialog open={retraitDialogOpen} onOpenChange={setRetraitDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Enregistrer le retrait</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1">
              <Label>Nom du retrayant *</Label>
              <Input
                value={retraitNom}
                onChange={(e) => setRetraitNom(e.target.value)}
                placeholder="Nom complet"
              />
            </div>
            <div className="space-y-1">
              <Label>Téléphone *</Label>
              <Input
                value={retraitTel}
                onChange={(e) => setRetraitTel(e.target.value)}
                placeholder="+226..."
              />
            </div>
            <div className="space-y-1">
              <Label>Pièce d'identité (optionnel)</Label>
              <Input
                value={retraitPiece}
                onChange={(e) => setRetraitPiece(e.target.value)}
                placeholder="CNI, Passeport, Permis..."
              />
            </div>
            <Button
              className="w-full"
              onClick={handleRetrait}
              disabled={!retraitNom || !retraitTel || retirer.isPending}
            >
              {retirer.isPending ? "En cours..." : "Confirmer le retrait"}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}

function Row({ label, value, bold }: { label: string; value: string; bold?: boolean }) {
  return (
    <div className="flex justify-between gap-2 flex-wrap">
      <span className="text-muted-foreground shrink-0">{label}</span>
      <span className={bold ? "font-semibold" : ""}>{value}</span>
    </div>
  );
}
