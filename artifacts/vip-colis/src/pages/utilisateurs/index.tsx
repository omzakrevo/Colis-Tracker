import {
  useListUsers,
  useCreateUser,
  useUpdateUser,
  useDeleteUser,
  useListGares,
} from "@workspace/api-client-react";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { useToast } from "@/hooks/use-toast";
import { Plus, Pencil, Trash2, User } from "lucide-react";

const ROLES: Record<string, string> = {
  admin: "Administrateur",
  chef_gare: "Chef de gare",
  agent: "Agent",
};

const ROLE_COLORS: Record<string, string> = {
  admin: "bg-purple-100 text-purple-800",
  chef_gare: "bg-blue-100 text-blue-800",
  agent: "bg-green-100 text-green-800",
};

type UserForm = {
  nom: string;
  username: string;
  password: string;
  role: string;
  gare_id: string;
  telephone: string;
};

const emptyForm: UserForm = {
  nom: "",
  username: "",
  password: "",
  role: "agent",
  gare_id: "",
  telephone: "",
};

export default function UsersList() {
  const { toast } = useToast();
  const { data: users, refetch } = useListUsers();
  const { data: gares } = useListGares();
  const createUser = useCreateUser();
  const updateUser = useUpdateUser();
  const deleteUser = useDeleteUser();

  const [dialogOpen, setDialogOpen] = useState(false);
  const [deleteId, setDeleteId] = useState<number | null>(null);
  const [editId, setEditId] = useState<number | null>(null);
  const [form, setForm] = useState<UserForm>(emptyForm);

  const set = (key: keyof UserForm, value: string) =>
    setForm((f) => ({ ...f, [key]: value }));

  const openCreate = () => {
    setEditId(null);
    setForm(emptyForm);
    setDialogOpen(true);
  };

  const openEdit = (u: any) => {
    setEditId(u.id);
    setForm({
      nom: u.nom,
      username: u.username,
      password: "",
      role: u.role,
      gare_id: u.gare_id ? String(u.gare_id) : "",
      telephone: u.telephone ?? "",
    });
    setDialogOpen(true);
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const data: any = {
      nom: form.nom,
      username: form.username,
      role: form.role as any,
      gare_id: form.gare_id ? Number(form.gare_id) : undefined,
      telephone: form.telephone || undefined,
    };
    if (form.password) data.password = form.password;

    if (editId) {
      updateUser.mutate(
        { id: editId, data },
        {
          onSuccess: () => { toast({ title: "Utilisateur mis à jour" }); setDialogOpen(false); refetch(); },
          onError: () => toast({ title: "Erreur", variant: "destructive" }),
        }
      );
    } else {
      if (!form.password) {
        toast({ title: "Le mot de passe est requis", variant: "destructive" });
        return;
      }
      createUser.mutate(
        { data: { ...data, password: form.password } },
        {
          onSuccess: () => { toast({ title: "Utilisateur créé avec succès" }); setDialogOpen(false); refetch(); },
          onError: () => toast({ title: "Erreur", variant: "destructive" }),
        }
      );
    }
  };

  const handleDelete = () => {
    if (!deleteId) return;
    deleteUser.mutate(
      { id: deleteId },
      {
        onSuccess: () => { toast({ title: "Utilisateur supprimé" }); setDeleteId(null); refetch(); },
        onError: () => toast({ title: "Erreur lors de la suppression", variant: "destructive" }),
      }
    );
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Utilisateurs</h1>
          <p className="text-muted-foreground">Gérez les comptes du personnel.</p>
        </div>
        <Button onClick={openCreate}>
          <Plus className="w-4 h-4 mr-2" /> Nouvel utilisateur
        </Button>
      </div>

      {/* Desktop table */}
      <div className="hidden md:block bg-card border rounded-lg overflow-hidden">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Nom</TableHead>
              <TableHead>Identifiant</TableHead>
              <TableHead>Rôle</TableHead>
              <TableHead>Gare</TableHead>
              <TableHead>Téléphone</TableHead>
              <TableHead>Statut</TableHead>
              <TableHead className="w-24">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {users?.map((u) => (
              <TableRow key={u.id}>
                <TableCell className="font-medium">{u.nom}</TableCell>
                <TableCell className="font-mono text-sm">{u.username}</TableCell>
                <TableCell>
                  <Badge variant="outline" className={`${ROLE_COLORS[u.role]} border-0`}>{ROLES[u.role]}</Badge>
                </TableCell>
                <TableCell>{u.gare_nom ?? "—"}</TableCell>
                <TableCell>{u.telephone ?? "—"}</TableCell>
                <TableCell>
                  <Badge variant="outline" className={u.actif ? "bg-green-100 text-green-800 border-0" : "bg-red-100 text-red-800 border-0"}>
                    {u.actif ? "Actif" : "Inactif"}
                  </Badge>
                </TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    <Button variant="ghost" size="sm" onClick={() => openEdit(u)}><Pencil className="w-4 h-4" /></Button>
                    <Button variant="ghost" size="sm" className="text-destructive hover:text-destructive" onClick={() => setDeleteId(u.id)}><Trash2 className="w-4 h-4" /></Button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
            {(!users || users.length === 0) && (
              <TableRow><TableCell colSpan={7} className="text-center py-8 text-muted-foreground">Aucun utilisateur trouvé.</TableCell></TableRow>
            )}
          </TableBody>
        </Table>
      </div>

      {/* Mobile cards */}
      <div className="md:hidden space-y-3">
        {users?.map((u) => (
          <Card key={u.id}>
            <CardContent className="pt-4">
              <div className="flex items-start justify-between gap-2">
                <div className="flex items-start gap-3">
                  <div className="w-9 h-9 rounded-full bg-primary/10 flex items-center justify-center shrink-0">
                    <User className="w-4 h-4 text-primary" />
                  </div>
                  <div className="min-w-0">
                    <p className="font-semibold">{u.nom}</p>
                    <p className="text-sm font-mono text-muted-foreground">@{u.username}</p>
                    <div className="flex items-center gap-2 mt-1 flex-wrap">
                      <Badge variant="outline" className={`${ROLE_COLORS[u.role]} border-0 text-xs`}>{ROLES[u.role]}</Badge>
                      {u.gare_nom && <span className="text-xs text-muted-foreground">{u.gare_nom}</span>}
                    </div>
                  </div>
                </div>
                <div className="flex gap-1 shrink-0">
                  <Button variant="ghost" size="sm" onClick={() => openEdit(u)}><Pencil className="w-4 h-4" /></Button>
                  <Button variant="ghost" size="sm" className="text-destructive" onClick={() => setDeleteId(u.id)}><Trash2 className="w-4 h-4" /></Button>
                </div>
              </div>
            </CardContent>
          </Card>
        ))}
        {(!users || users.length === 0) && (
          <p className="text-center py-8 text-muted-foreground">Aucun utilisateur trouvé.</p>
        )}
      </div>

      {/* Create / Edit dialog */}
      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{editId ? "Modifier l'utilisateur" : "Nouvel utilisateur"}</DialogTitle>
          </DialogHeader>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-1">
              <Label>Nom complet *</Label>
              <Input required value={form.nom} onChange={(e) => set("nom", e.target.value)} placeholder="Prénom Nom" />
            </div>
            <div className="space-y-1">
              <Label>Identifiant *</Label>
              <Input required value={form.username} onChange={(e) => set("username", e.target.value)} placeholder="ex: agent_bobo" />
            </div>
            <div className="space-y-1">
              <Label>{editId ? "Nouveau mot de passe (laisser vide pour garder)" : "Mot de passe *"}</Label>
              <Input type="password" required={!editId} value={form.password} onChange={(e) => set("password", e.target.value)} placeholder="••••••••" />
            </div>
            <div className="space-y-1">
              <Label>Rôle *</Label>
              <Select value={form.role} onValueChange={(v) => set("role", v)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="admin">Administrateur</SelectItem>
                  <SelectItem value="chef_gare">Chef de gare</SelectItem>
                  <SelectItem value="agent">Agent</SelectItem>
                </SelectContent>
              </Select>
            </div>
            {form.role !== "admin" && (
              <div className="space-y-1">
                <Label>Gare</Label>
                <Select value={form.gare_id || undefined} onValueChange={(v) => set("gare_id", v)}>
                  <SelectTrigger><SelectValue placeholder="Sélectionner une gare" /></SelectTrigger>
                  <SelectContent>
                    {gares?.map((g) => (
                      <SelectItem key={g.id} value={String(g.id)}>{g.nom}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            )}
            <div className="space-y-1">
              <Label>Téléphone</Label>
              <Input value={form.telephone} onChange={(e) => set("telephone", e.target.value)} placeholder="+226..." />
            </div>
            <Button type="submit" className="w-full" disabled={createUser.isPending || updateUser.isPending}>
              {createUser.isPending || updateUser.isPending ? "En cours..." : editId ? "Enregistrer les modifications" : "Créer l'utilisateur"}
            </Button>
          </form>
        </DialogContent>
      </Dialog>

      <AlertDialog open={!!deleteId} onOpenChange={() => setDeleteId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Supprimer cet utilisateur ?</AlertDialogTitle>
            <AlertDialogDescription>Cette action est irréversible.</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Annuler</AlertDialogCancel>
            <AlertDialogAction className="bg-destructive text-destructive-foreground hover:bg-destructive/90" onClick={handleDelete}>Supprimer</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
