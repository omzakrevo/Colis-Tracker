import { useCreateColis, useListGares, useGetMe } from "@workspace/api-client-react";
import { useLocation, Link } from "wouter";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { NativeSelect } from "@/components/ui/native-select";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useToast } from "@/hooks/use-toast";
import { ArrowLeft } from "lucide-react";
import { useState } from "react";
import { PhotoCapture } from "@/components/photo-capture";

export default function ColisNouveau() {
  const [, setLocation] = useLocation();
  const { toast } = useToast();
  const { data: gares } = useListGares();
  const { data: me } = useGetMe();
  const createColis = useCreateColis();

  const today = new Date().toISOString().slice(0, 10);

  const [form, setForm] = useState({
    expediteur_nom: "",
    expediteur_telephone: "",
    destinataire_nom: "",
    destinataire_telephone: "",
    gare_depart_id: me?.gare_id ? String(me.gare_id) : "",
    gare_arrivee_id: "",
    description: "",
    nombre: "1",
    poids: "",
    prix: "",
    date_envoi: today,
    notes: "",
  });
  const [photo, setPhoto] = useState<string | null>(null);

  const set = (key: string, value: string) =>
    setForm((f) => ({ ...f, [key]: value }));

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.gare_depart_id || !form.gare_arrivee_id) {
      toast({ title: "Veuillez sélectionner les gares de départ et d'arrivée", variant: "destructive" });
      return;
    }
    if (Number(form.prix) <= 0) {
      toast({ title: "Le prix doit être supérieur à 0", variant: "destructive" });
      return;
    }
    createColis.mutate(
      {
        data: {
          expediteur_nom: form.expediteur_nom,
          expediteur_telephone: form.expediteur_telephone,
          destinataire_nom: form.destinataire_nom,
          destinataire_telephone: form.destinataire_telephone,
          gare_depart_id: Number(form.gare_depart_id),
          gare_arrivee_id: Number(form.gare_arrivee_id),
          description: form.description,
          nombre: Number(form.nombre),
          poids: form.poids ? Number(form.poids) : undefined,
          prix: Number(form.prix),
          date_envoi: form.date_envoi,
          notes: form.notes || undefined,
          photo: photo || undefined,
        },
      },
      {
        onSuccess: (data) => {
          toast({ title: `Colis ${data.numero} enregistré avec succès !` });
          setLocation(`/colis/${data.id}`);
        },
        onError: () =>
          toast({ title: "Erreur lors de l'enregistrement", variant: "destructive" }),
      }
    );
  };

  return (
    <div className="space-y-6 max-w-2xl w-full mx-auto">
      <div className="flex items-center gap-3">
        <Link href="/colis">
          <Button variant="ghost" size="sm">
            <ArrowLeft className="w-4 h-4 mr-1" /> Retour
          </Button>
        </Link>
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Nouveau colis</h1>
          <p className="text-muted-foreground text-sm">Enregistrement d'une nouvelle expédition</p>
        </div>
      </div>

      <form onSubmit={handleSubmit} className="space-y-4">
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-semibold">Expéditeur</CardTitle>
          </CardHeader>
          <CardContent className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div className="space-y-1">
              <Label htmlFor="exp_nom">Nom complet *</Label>
              <Input id="exp_nom" required value={form.expediteur_nom}
                onChange={(e) => set("expediteur_nom", e.target.value)} placeholder="Moussa Traoré" />
            </div>
            <div className="space-y-1">
              <Label htmlFor="exp_tel">Téléphone *</Label>
              <Input id="exp_tel" required value={form.expediteur_telephone}
                onChange={(e) => set("expediteur_telephone", e.target.value)} placeholder="+226 70 00 00 00" />
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-semibold">Destinataire</CardTitle>
          </CardHeader>
          <CardContent className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div className="space-y-1">
              <Label htmlFor="dest_nom">Nom complet *</Label>
              <Input id="dest_nom" required value={form.destinataire_nom}
                onChange={(e) => set("destinataire_nom", e.target.value)} placeholder="Fatoumata Coulibaly" />
            </div>
            <div className="space-y-1">
              <Label htmlFor="dest_tel">Téléphone *</Label>
              <Input id="dest_tel" required value={form.destinataire_telephone}
                onChange={(e) => set("destinataire_telephone", e.target.value)} placeholder="+226 60 00 00 00" />
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-semibold">Trajet</CardTitle>
          </CardHeader>
          <CardContent className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div className="space-y-1">
              <Label htmlFor="gare_dep">Gare de départ *</Label>
              <NativeSelect
                id="gare_dep"
                value={form.gare_depart_id}
                onChange={(e) => set("gare_depart_id", e.target.value)}
                placeholder="Sélectionner une gare"
                required
              >
                {gares?.map((g) => (
                  <option key={g.id} value={String(g.id)}>{g.nom}</option>
                ))}
              </NativeSelect>
            </div>
            <div className="space-y-1">
              <Label htmlFor="gare_arr">Gare d'arrivée *</Label>
              <NativeSelect
                id="gare_arr"
                value={form.gare_arrivee_id}
                onChange={(e) => set("gare_arrivee_id", e.target.value)}
                placeholder="Sélectionner une gare"
                required
              >
                {gares?.map((g) => (
                  <option key={g.id} value={String(g.id)}>{g.nom}</option>
                ))}
              </NativeSelect>
            </div>
            <div className="space-y-1 sm:col-span-2">
              <Label htmlFor="date_envoi">Date d'envoi *</Label>
              <Input id="date_envoi" type="date" required value={form.date_envoi}
                onChange={(e) => set("date_envoi", e.target.value)} />
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-semibold">Détails du colis</CardTitle>
          </CardHeader>
          <CardContent className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div className="space-y-1 sm:col-span-2">
              <Label htmlFor="description">Description *</Label>
              <Input id="description" required value={form.description}
                onChange={(e) => set("description", e.target.value)}
                placeholder="Vêtements, électronique, documents..." />
            </div>
            <div className="space-y-1">
              <Label htmlFor="nombre">Nombre de pièces *</Label>
              <Input id="nombre" type="number" required min={1}
                value={form.nombre} onChange={(e) => set("nombre", e.target.value)} />
            </div>
            <div className="space-y-1">
              <Label htmlFor="poids">Poids (kg)</Label>
              <Input id="poids" type="number" min={0} step={0.1}
                value={form.poids} onChange={(e) => set("poids", e.target.value)} placeholder="Optionnel" />
            </div>
            <div className="space-y-1">
              <Label htmlFor="prix">Prix (FCFA) *</Label>
              <Input id="prix" type="number" required min={1}
                value={form.prix} onChange={(e) => set("prix", e.target.value)} placeholder="Ex: 2500" />
            </div>
            <div className="space-y-1 sm:col-span-2">
              <Label htmlFor="notes">Notes</Label>
              <Textarea id="notes" value={form.notes}
                onChange={(e) => set("notes", e.target.value)}
                rows={2} placeholder="Informations complémentaires..." />
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-semibold flex items-center gap-2">
              Photo du colis
              <span className="text-xs font-normal text-muted-foreground">(optionnel — facilite la reconnaissance à la réception)</span>
            </CardTitle>
          </CardHeader>
          <CardContent>
            <PhotoCapture value={photo} onChange={setPhoto} />
          </CardContent>
        </Card>

        <Button type="submit" className="w-full" size="lg" disabled={createColis.isPending}>
          {createColis.isPending ? "Enregistrement en cours..." : "Enregistrer le colis"}
        </Button>
      </form>
    </div>
  );
}
