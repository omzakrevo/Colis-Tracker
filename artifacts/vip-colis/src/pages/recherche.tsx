import { useListColis } from "@workspace/api-client-react";
import { useState } from "react";
import { Input } from "@/components/ui/input";
import { Card, CardContent } from "@/components/ui/card";
import { Link } from "wouter";
import { ColisBadge } from "./colis/index";
import { Search, Package } from "lucide-react";

export default function Recherche() {
  const [query, setQuery] = useState("");
  const { data: results, isFetching } = useListColis(
    { search: query || undefined },
    { query: { enabled: query.length >= 2, queryKey: ["listColis", query] } }
  );

  return (
    <div className="space-y-6 max-w-2xl w-full mx-auto">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Recherche</h1>
        <p className="text-muted-foreground">
          Retrouvez un colis par numéro, nom ou téléphone.
        </p>
      </div>

      <div className="relative">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
        <Input
          className="pl-9 h-12 text-base"
          placeholder="Numéro de colis, nom, téléphone..."
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          autoFocus
        />
      </div>

      {query.length >= 2 && (
        <div>
          {isFetching && (
            <p className="text-sm text-muted-foreground text-center py-4">
              Recherche en cours...
            </p>
          )}

          {!isFetching && results && results.length === 0 && (
            <div className="text-center py-12">
              <Package className="w-10 h-10 text-muted-foreground mx-auto mb-3" />
              <p className="text-muted-foreground">
                Aucun résultat pour <strong>"{query}"</strong>
              </p>
            </div>
          )}

          {!isFetching && results && results.length > 0 && (
            <div className="space-y-2">
              <p className="text-sm text-muted-foreground">
                {results.length} résultat{results.length > 1 ? "s" : ""} trouvé
                {results.length > 1 ? "s" : ""}
              </p>
              {results.map((c) => (
                <Link key={c.id} href={`/colis/${c.id}`}>
                  <Card className="hover:border-primary/50 transition-colors cursor-pointer">
                    <CardContent className="pt-4 pb-4">
                      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
                        <div className="flex items-start gap-3">
                          <div className="w-9 h-9 rounded-full bg-primary/10 flex items-center justify-center shrink-0 mt-0.5">
                            <Package className="w-4 h-4 text-primary" />
                          </div>
                          <div>
                            <p className="font-semibold text-primary">{c.numero}</p>
                            <p className="text-sm">
                              <span className="text-muted-foreground">De </span>
                              {c.expediteur_nom}
                              <span className="text-muted-foreground"> pour </span>
                              {c.destinataire_nom}
                            </p>
                            <p className="text-xs text-muted-foreground">
                              {c.gare_depart_nom} → {c.gare_arrivee_nom} —{" "}
                              {new Date(c.date_envoi).toLocaleDateString("fr-FR")}
                            </p>
                          </div>
                        </div>
                        <div className="flex items-center gap-3 ml-12 sm:ml-0">
                          <ColisBadge statut={c.statut} />
                          <span className="text-sm font-semibold text-muted-foreground">
                            {c.prix.toLocaleString("fr-FR")} FCFA
                          </span>
                        </div>
                      </div>
                    </CardContent>
                  </Card>
                </Link>
              ))}
            </div>
          )}
        </div>
      )}

      {query.length > 0 && query.length < 2 && (
        <p className="text-sm text-muted-foreground text-center py-4">
          Tapez au moins 2 caractères pour rechercher.
        </p>
      )}

      {query.length === 0 && (
        <div className="text-center py-16">
          <Search className="w-12 h-12 text-muted-foreground/40 mx-auto mb-4" />
          <p className="text-muted-foreground">
            Saisissez un terme de recherche pour commencer.
          </p>
        </div>
      )}
    </div>
  );
}
