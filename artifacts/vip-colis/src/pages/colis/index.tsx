import { useListColis } from "@workspace/api-client-react";
import { Link } from "wouter";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { useState } from "react";
import { Plus, Printer, Package } from "lucide-react";

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

export default function ColisList() {
  const [search, setSearch] = useState("");
  const { data: colis } = useListColis({ search: search || undefined });

  const handlePrint = () => window.print();

  return (
    <div className="space-y-6">
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

      {/* Search – hidden on print */}
      <div className="flex items-center gap-2 max-w-sm print:hidden">
        <Input
          placeholder="Rechercher par numéro, nom, téléphone..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
      </div>

      {/* Print header – only visible on print */}
      <div className="hidden print:block mb-6">
        <h1 className="text-2xl font-bold">VIP COLIS — Liste des expéditions</h1>
        <p className="text-sm text-gray-500">
          Imprimé le {new Date().toLocaleDateString("fr-FR")} à {new Date().toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" })}
          {search ? ` — Filtre : "${search}"` : ""} — {colis?.length ?? 0} colis
        </p>
      </div>

      {/* Desktop table */}
      <div className="hidden sm:block bg-card border rounded-lg overflow-hidden print:block print:border-none print:shadow-none">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Numéro</TableHead>
              <TableHead>Date</TableHead>
              <TableHead>Trajet</TableHead>
              <TableHead>Expéditeur</TableHead>
              <TableHead>Destinataire</TableHead>
              <TableHead>Prix</TableHead>
              <TableHead>Statut</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {colis?.map((c) => (
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
            {(!colis || colis.length === 0) && (
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
        {colis?.map((c) => (
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
        {(!colis || colis.length === 0) && (
          <p className="text-center py-8 text-muted-foreground">Aucun colis trouvé.</p>
        )}
      </div>
    </div>
  );
}
