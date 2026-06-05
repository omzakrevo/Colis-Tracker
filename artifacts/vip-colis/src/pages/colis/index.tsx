import { useListColis } from "@workspace/api-client-react";
import { Link } from "wouter";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { useState } from "react";
import { Plus } from "lucide-react";

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

  return <Badge variant="outline" className={`${colors[statut]} border-0 capitalize`}>{labels[statut]}</Badge>;
}

export default function ColisList() {
  const [search, setSearch] = useState("");
  const { data: colis } = useListColis({ search: search || undefined });

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Colis</h1>
          <p className="text-muted-foreground">Gérez l'ensemble des expéditions.</p>
        </div>
        <Link href="/colis/nouveau" className="inline-flex items-center justify-center whitespace-nowrap rounded-md text-sm font-medium ring-offset-background transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50 bg-primary text-primary-foreground hover:bg-primary/90 h-10 px-4 py-2">
          <Plus className="w-4 h-4 mr-2" /> Nouveau Colis
        </Link>
      </div>

      <div className="flex items-center gap-2 max-w-sm">
        <Input placeholder="Rechercher par numéro, nom, téléphone..." value={search} onChange={(e) => setSearch(e.target.value)} />
      </div>

      <div className="bg-card border rounded-lg overflow-hidden">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Numéro</TableHead>
              <TableHead>Date</TableHead>
              <TableHead>Trajet</TableHead>
              <TableHead>Expéditeur</TableHead>
              <TableHead>Destinataire</TableHead>
              <TableHead>Statut</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {colis?.map(c => (
              <TableRow key={c.id}>
                <TableCell><Link href={`/colis/${c.id}`} className="font-medium text-primary hover:underline">{c.numero}</Link></TableCell>
                <TableCell>{new Date(c.date_envoi).toLocaleDateString()}</TableCell>
                <TableCell>{c.gare_depart_nom} &rarr; {c.gare_arrivee_nom}</TableCell>
                <TableCell>{c.expediteur_nom}</TableCell>
                <TableCell>{c.destinataire_nom}</TableCell>
                <TableCell><ColisBadge statut={c.statut} /></TableCell>
              </TableRow>
            ))}
            {(!colis || colis.length === 0) && (
              <TableRow>
                <TableCell colSpan={6} className="text-center py-8 text-muted-foreground">Aucun colis trouvé.</TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>
    </div>
  )
}
