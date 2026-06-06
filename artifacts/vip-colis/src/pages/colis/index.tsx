import { useListColis, useGetMe } from "@workspace/api-client-react";
import { Link } from "wouter";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { NativeSelect } from "@/components/ui/native-select";
import { useState, useMemo } from "react";
import { Plus, Printer, Package, ArrowUpDown, X } from "lucide-react";

export function ColisBadge({ statut }: { statut: string }) {
  const colors: Record<string, string> = {
    enregistre: "bg-blue-100 text-blue-800",
    charge: "bg-orange-100 text-orange-800",
    en_route: "bg-yellow-100 text-yellow-800",
    arrive: "bg-green-100 text-green-800",
    retire: "bg-gray-100 text-gray-800",
    annule: "bg-red-100 text-red-800",
  };
  const labels: Record<string, string> = {
    enregistre: "Enregistré",
    charge: "Chargé",
    en_route: "En route",
    arrive: "Arrivé",
    retire: "Retiré",
    annule: "Annulé",
  };
  return (
    <Badge variant="outline" className={`${colors[statut]} border-0 capitalize`}>
      {labels[statut]}
    </Badge>
  );
}

const STATUTS_LABELS: Record<string, string> = {
  enregistre: "Enregistré",
  charge: "Chargé",
  en_route: "En route",
  arrive: "Arrivé",
  retire: "Retiré",
  annule: "Annulé",
};

export default function ColisList() {
  const { data: me } = useGetMe();

  const [search, setSearch]       = useState("");
  const [statut, setStatut]       = useState("");
  const [dateDebut, setDateDebut] = useState("");
  const [dateFin, setDateFin]     = useState("");
  const [direction, setDirection] = useState<"" | "envoi" | "reception">("");
  const [sortOrder, setSortOrder] = useState<"desc" | "asc">("desc");

  const gareId = me?.gare_id ?? null;
  const hasGare = !!gareId;

  const params = useMemo(() => ({
    search:         search   || undefined,
    statut:         statut   || undefined,
    date_debut:     dateDebut|| undefined,
    date_fin:       dateFin  || undefined,
    gare_depart_id: direction === "envoi"      && gareId ? gareId : undefined,
    gare_arrivee_id:direction === "reception"  && gareId ? gareId : undefined,
  }), [search, statut, dateDebut, dateFin, direction, gareId]);

  const { data: rawColis } = useListColis(params);

  const colis = useMemo(() => {
    if (!rawColis) return [];
    return [...rawColis].sort((a, b) => {
      const diff = new Date(a.date_envoi).getTime() - new Date(b.date_envoi).getTime();
      return sortOrder === "asc" ? diff : -diff;
    });
  }, [rawColis, sortOrder]);

  const activeFilterCount = [statut, dateDebut, dateFin, direction].filter(Boolean).length;

  const clearFilters = () => {
    setStatut("");
    setDateDebut("");
    setDateFin("");
    setDirection("");
  };

  const handlePrint = () => window.print();

  return (
    <div className="space-y-5">
      {/* Header – hidden on print */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 print:hidden">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Colis</h1>
          <p className="text-muted-foreground">Gérez l'ensemble des expéditions.</p>
        </div>
        <div className="flex gap-2 flex-wrap">
          <Button variant="outline" onClick={handlePrint}>
            <Printer className="w-4 h-4 mr-2" /> Imprimer PDF
          </Button>
          <Link href="/colis/nouveau">
            <Button><Plus className="w-4 h-4 mr-2" /> Nouveau Colis</Button>
          </Link>
        </div>
      </div>

      {/* Filters – hidden on print */}
      <div className="print:hidden space-y-3">
        {/* Row 1 — search + statut + envoi/réception */}
        <div className="flex flex-wrap gap-3 items-end">
          <div className="flex-1 min-w-[180px] max-w-xs">
            <Input
              placeholder="Rechercher…"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </div>

          <div className="space-y-1 min-w-[140px]">
            <Label className="text-xs text-muted-foreground">Statut</Label>
            <NativeSelect
              value={statut}
              onChange={(e) => setStatut(e.target.value)}
              className="h-9 text-sm"
            >
              <option value="">Tous les statuts</option>
              {Object.entries(STATUTS_LABELS).map(([val, label]) => (
                <option key={val} value={val}>{label}</option>
              ))}
            </NativeSelect>
          </div>

          {hasGare && (
            <div className="space-y-1 min-w-[140px]">
              <Label className="text-xs text-muted-foreground">Direction</Label>
              <NativeSelect
                value={direction}
                onChange={(e) => setDirection(e.target.value as "" | "envoi" | "reception")}
                className="h-9 text-sm"
              >
                <option value="">Tous</option>
                <option value="envoi">Envoi (départ)</option>
                <option value="reception">Réception (arrivée)</option>
              </NativeSelect>
            </div>
          )}

          <div className="space-y-1">
            <Label className="text-xs text-muted-foreground">Du</Label>
            <input
              type="date"
              value={dateDebut}
              onChange={(e) => setDateDebut(e.target.value)}
              className="h-9 px-3 rounded-md border border-input bg-background text-sm focus:outline-none focus:ring-2 focus:ring-ring"
            />
          </div>

          <div className="space-y-1">
            <Label className="text-xs text-muted-foreground">Au</Label>
            <input
              type="date"
              value={dateFin}
              onChange={(e) => setDateFin(e.target.value)}
              className="h-9 px-3 rounded-md border border-input bg-background text-sm focus:outline-none focus:ring-2 focus:ring-ring"
            />
          </div>

          {activeFilterCount > 0 && (
            <Button variant="ghost" size="sm" onClick={clearFilters} className="text-muted-foreground h-9 self-end">
              <X className="w-3.5 h-3.5 mr-1" /> Effacer ({activeFilterCount})
            </Button>
          )}
        </div>

        {/* Results count */}
        <p className="text-xs text-muted-foreground">
          {colis.length} colis{activeFilterCount > 0 ? " (filtré)" : ""}
        </p>
      </div>

      {/* Print header – only visible on print */}
      <div className="hidden print:block mb-6">
        <h1 className="text-2xl font-bold">VIP COLIS — Liste des expéditions</h1>
        <p className="text-sm text-gray-500">
          Imprimé le {new Date().toLocaleDateString("fr-FR")} à {new Date().toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" })}
          {search ? ` — Filtre : "${search}"` : ""}
          {statut ? ` — Statut : ${STATUTS_LABELS[statut]}` : ""}
          {dateDebut ? ` — Du ${new Date(dateDebut).toLocaleDateString("fr-FR")}` : ""}
          {dateFin ? ` — Au ${new Date(dateFin).toLocaleDateString("fr-FR")}` : ""}
          {" "} — {colis.length} colis
        </p>
      </div>

      {/* Desktop table */}
      <div className="hidden sm:block bg-card border rounded-lg overflow-hidden print:block print:border-none print:shadow-none">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Numéro</TableHead>
              <TableHead>
                <button
                  className="flex items-center gap-1 hover:text-foreground transition-colors"
                  onClick={() => setSortOrder(s => s === "desc" ? "asc" : "desc")}
                >
                  Date <ArrowUpDown className="w-3.5 h-3.5" />
                  <span className="text-[10px] text-muted-foreground">{sortOrder === "desc" ? "récent" : "ancien"}</span>
                </button>
              </TableHead>
              <TableHead>Trajet</TableHead>
              <TableHead>Expéditeur</TableHead>
              <TableHead>Destinataire</TableHead>
              <TableHead>Prix</TableHead>
              <TableHead>Statut</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {colis.map((c) => (
              <TableRow key={c.id}>
                <TableCell>
                  <Link href={`/colis/${c.id}`} className="font-medium text-primary hover:underline print:text-black print:no-underline">
                    {c.numero}
                  </Link>
                </TableCell>
                <TableCell>{new Date(c.date_envoi).toLocaleDateString("fr-FR")}</TableCell>
                <TableCell className="text-sm">{c.gare_depart_nom} → {c.gare_arrivee_nom}</TableCell>
                <TableCell>{c.expediteur_nom}</TableCell>
                <TableCell>{c.destinataire_nom}</TableCell>
                <TableCell className="font-medium">{c.prix.toLocaleString("fr-FR")} FCFA</TableCell>
                <TableCell><ColisBadge statut={c.statut} /></TableCell>
              </TableRow>
            ))}
            {colis.length === 0 && (
              <TableRow>
                <TableCell colSpan={7} className="text-center py-8 text-muted-foreground">
                  Aucun colis trouvé.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>

      {/* Mobile cards – hidden on print */}
      <div className="sm:hidden space-y-3 print:hidden">
        {colis.map((c) => (
          <Link key={c.id} href={`/colis/${c.id}`}>
            <Card className="hover:border-primary/50 transition-colors cursor-pointer mb-3">
              <CardContent className="pt-4 pb-4">
                <div className="flex items-start justify-between gap-2">
                  <div className="flex items-start gap-3">
                    <div className="w-9 h-9 rounded-full bg-primary/10 flex items-center justify-center shrink-0">
                      <Package className="w-4 h-4 text-primary" />
                    </div>
                    <div className="min-w-0">
                      <p className="font-semibold text-primary text-sm">{c.numero}</p>
                      <p className="text-xs text-muted-foreground">
                        {new Date(c.date_envoi).toLocaleDateString("fr-FR")}
                      </p>
                      <p className="text-sm text-muted-foreground">
                        {c.expediteur_nom} → {c.destinataire_nom}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        {c.gare_depart_nom} → {c.gare_arrivee_nom}
                      </p>
                    </div>
                  </div>
                  <div className="flex flex-col items-end gap-1 shrink-0">
                    <ColisBadge statut={c.statut} />
                    <span className="text-xs font-semibold">{c.prix.toLocaleString("fr-FR")} FCFA</span>
                  </div>
                </div>
              </CardContent>
            </Card>
          </Link>
        ))}
        {colis.length === 0 && (
          <p className="text-center py-8 text-muted-foreground">Aucun colis trouvé.</p>
        )}
      </div>
    </div>
  );
}
