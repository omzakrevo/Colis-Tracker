import {
  useListGares,
  useCreateGare,
  useUpdateGare,
  useDeleteGare,
} from "@workspace/api-client-react";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Card, CardContent } from "@/components/ui/card";
import { useToast } from "@/hooks/use-toast";
import { Plus, Pencil, Trash2, MapPin } from "lucide-react";

type GareForm = {
  nom: string;
  ville: string;
  adresse: string;
  responsable: string;
  telephone: string;
};

const emptyForm: GareForm = {
  nom: "",
  ville: "",
  adresse: "",
  responsable: "",
  telephone: "",
};

export default function GaresList() {
  const { toast } = useToast();
  const { data: gares, refetch } = useListGares();
  const createGare = useCreateGare();
  const updateGare = useUpdateGare();
  const deleteGare = useDeleteGare();

  const [dialogOpen, setDialogOpen] = useState(false);
  const [deleteId, setDeleteId] = useState<number | null>(null);
  const [editId, setEditId] = useState<number | null>(null);
  const [form, setForm] = useState<GareForm>(emptyForm);

  const set = (key: keyof GareForm, value: string) =>
    setForm((f) => ({ ...f, [key]: value }));

  const openCreate = () => {
    setEditId(null);
    setForm(emptyForm);
    setDialogOpen(true);
  };

  const openEdit = (g: any) => {
    setEditId(g.id);
    setForm({
      nom: g.nom,
      ville: g.ville,
      adresse: g.adresse,
      responsable: g.responsable ?? "",
      telephone: g.telephone ?? "",
    });
    setDialogOpen(true);
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const data = {
      nom: form.nom,
      ville: form.ville,
      adresse: form.adresse,
      responsable: form.responsable || undefined,
      telephone: form.telephone || undefined,
    };
    if (editId) {
      updateGare.mutate(
        { id: editId, data },
        {
          onSuccess: () => {
            toast({ title: "Gare mise à jour" });
            setDialogOpen(false);
            refetch();
          },
          onError: () => toast({ title: "Erreur", variant: "destructive" }),
        }
      );
    } else {
      createGare.mutate(
        { data },
        {
          onSuccess: () => {
            toast({ title: "Gare créée avec succès" });
            setDialogOpen(false);
            refetch();
          },
          onError: () => toast({ title: "Erreur", variant: "destructive" }),
        }
      );
    }
  };

  const handleDelete = () => {
    if (!deleteId) return;
    deleteGare.mutate(
      { id: deleteId },
      {
        onSuccess: () => {
          toast({ title: "Gare supprimée" });
          setDeleteId(null);
          refetch();
        },
        onError: () => toast({ title: "Erreur lors de la suppression", variant: "destructive" }),
      }
    );
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Gares</h1>
          <p className="text-muted-foreground">
            Gérez les agences et gares du réseau.
          </p>
        </div>
        <Button onClick={openCreate}>
          <Plus className="w-4 h-4 mr-2" /> Nouvelle gare
        </Button>
      </div>

      {/* Desktop table */}
      <div className="hidden md:block bg-card border rounded-lg overflow-hidden">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Nom</TableHead>
              <TableHead>Ville</TableHead>
              <TableHead>Adresse</TableHead>
              <TableHead>Responsable</TableHead>
              <TableHead>Téléphone</TableHead>
              <TableHead className="w-24">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {gares?.map((g) => (
              <TableRow key={g.id}>
                <TableCell className="font-medium">{g.nom}</TableCell>
                <TableCell>{g.ville}</TableCell>
                <TableCell>{g.adresse}</TableCell>
                <TableCell>{g.responsable ?? "—"}</TableCell>
                <TableCell>{g.telephone ?? "—"}</TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => openEdit(g)}
                    >
                      <Pencil className="w-4 h-4" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="sm"
                      className="text-destructive hover:text-destructive"
                      onClick={() => setDeleteId(g.id)}
                    >
                      <Trash2 className="w-4 h-4" />
                    </Button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
            {(!gares || gares.length === 0) && (
              <TableRow>
                <TableCell
                  colSpan={6}
                  className="text-center py-8 text-muted-foreground"
                >
                  Aucune gare enregistrée.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>

      {/* Mobile cards */}
      <div className="md:hidden space-y-3">
        {gares?.map((g) => (
          <Card key={g.id}>
            <CardContent className="pt-4">
              <div className="flex items-start justify-between gap-2">
                <div className="flex items-start gap-3">
                  <div className="w-9 h-9 rounded-full bg-primary/10 flex items-center justify-center shrink-0">
                    <MapPin className="w-4 h-4 text-primary" />
                  </div>
                  <div className="min-w-0">
                    <p className="font-semibold">{g.nom}</p>
                    <p className="text-sm text-muted-foreground">{g.ville} — {g.adresse}</p>
                    {g.responsable && (
                      <p className="text-sm text-muted-foreground">
                        Responsable : {g.responsable}
                      </p>
                    )}
                    {g.telephone && (
                      <p className="text-sm text-muted-foreground">{g.telephone}</p>
                    )}
                  </div>
                </div>
                <div className="flex gap-1 shrink-0">
                  <Button variant="ghost" size="sm" onClick={() => openEdit(g)}>
                    <Pencil className="w-4 h-4" />
                  </Button>
                  <Button
                    variant="ghost"
                    size="sm"
                    className="text-destructive"
                    onClick={() => setDeleteId(g.id)}
                  >
                    <Trash2 className="w-4 h-4" />
                  </Button>
                </div>
              </div>
            </CardContent>
          </Card>
        ))}
        {(!gares || gares.length === 0) && (
          <p className="text-center py-8 text-muted-foreground">
            Aucune gare enregistrée.
          </p>
        )}
      </div>

      {/* Create / Edit dialog */}
      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{editId ? "Modifier la gare" : "Nouvelle gare"}</DialogTitle>
          </DialogHeader>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-1">
              <Label>Nom *</Label>
              <Input
                required
                value={form.nom}
                onChange={(e) => set("nom", e.target.value)}
                placeholder="Gare de Bobo-Dioulasso"
              />
            </div>
            <div className="space-y-1">
              <Label>Ville *</Label>
              <Input
                required
                value={form.ville}
                onChange={(e) => set("ville", e.target.value)}
                placeholder="Bobo-Dioulasso"
              />
            </div>
            <div className="space-y-1">
              <Label>Adresse *</Label>
              <Input
                required
                value={form.adresse}
                onChange={(e) => set("adresse", e.target.value)}
                placeholder="Secteur 3, Avenue..."
              />
            </div>
            <div className="space-y-1">
              <Label>Responsable</Label>
              <Input
                value={form.responsable}
                onChange={(e) => set("responsable", e.target.value)}
                placeholder="Nom du responsable"
              />
            </div>
            <div className="space-y-1">
              <Label>Téléphone</Label>
              <Input
                value={form.telephone}
                onChange={(e) => set("telephone", e.target.value)}
                placeholder="+226..."
              />
            </div>
            <Button
              type="submit"
              className="w-full"
              disabled={createGare.isPending || updateGare.isPending}
            >
              {createGare.isPending || updateGare.isPending
                ? "En cours..."
                : editId
                ? "Enregistrer les modifications"
                : "Créer la gare"}
            </Button>
          </form>
        </DialogContent>
      </Dialog>

      {/* Delete confirmation */}
      <AlertDialog open={!!deleteId} onOpenChange={() => setDeleteId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Supprimer cette gare ?</AlertDialogTitle>
            <AlertDialogDescription>
              Cette action est irréversible. La gare sera définitivement supprimée.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Annuler</AlertDialogCancel>
            <AlertDialogAction
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
              onClick={handleDelete}
            >
              Supprimer
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
