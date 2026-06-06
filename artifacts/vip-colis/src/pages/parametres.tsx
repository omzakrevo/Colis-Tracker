import { useGetCompanySettings, useUpdateCompanySettings } from "@workspace/api-client-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useToast } from "@/hooks/use-toast";
import { Building2, Save, ImageIcon } from "lucide-react";
import { useState, useEffect, useRef } from "react";

const MAX_LOGO_WIDTH = 400;

function compressLogo(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    const url = URL.createObjectURL(file);
    img.onload = () => {
      URL.revokeObjectURL(url);
      const scale = img.width > MAX_LOGO_WIDTH ? MAX_LOGO_WIDTH / img.width : 1;
      const w = Math.round(img.width * scale);
      const h = Math.round(img.height * scale);
      const canvas = document.createElement("canvas");
      canvas.width = w;
      canvas.height = h;
      canvas.getContext("2d")!.drawImage(img, 0, 0, w, h);
      resolve(canvas.toDataURL("image/png"));
    };
    img.onerror = reject;
    img.src = url;
  });
}

export default function Parametres() {
  const { data: settings, refetch } = useGetCompanySettings();
  const update = useUpdateCompanySettings();
  const { toast } = useToast();
  const logoRef = useRef<HTMLInputElement>(null);

  const [form, setForm] = useState({
    nom: "", slogan: "", telephone: "", email: "",
    adresse: "", ville: "", pays: "",
  });
  const [logo, setLogo] = useState<string | null>(null);
  const [logoLoading, setLogoLoading] = useState(false);
  const [dirty, setDirty] = useState(false);

  useEffect(() => {
    if (!settings) return;
    setForm({
      nom: settings.nom,
      slogan: settings.slogan,
      telephone: settings.telephone,
      email: settings.email,
      adresse: settings.adresse,
      ville: settings.ville,
      pays: settings.pays,
    });
    setLogo(settings.logo ?? null);
    setDirty(false);
  }, [settings]);

  const set = (key: string, value: string) => {
    setForm(f => ({ ...f, [key]: value }));
    setDirty(true);
  };

  const handleLogoFile = async (file: File | undefined) => {
    if (!file) return;
    setLogoLoading(true);
    try {
      const compressed = await compressLogo(file);
      setLogo(compressed);
      setDirty(true);
    } finally {
      setLogoLoading(false);
    }
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    update.mutate(
      { data: { ...form, logo: logo } },
      {
        onSuccess: () => {
          toast({ title: "Paramètres enregistrés" });
          refetch();
          setDirty(false);
        },
        onError: () => toast({ title: "Erreur lors de l'enregistrement", variant: "destructive" }),
      }
    );
  };

  return (
    <div className="space-y-6 max-w-2xl mx-auto">
      <div>
        <h1 className="text-3xl font-bold tracking-tight flex items-center gap-3">
          <Building2 className="w-7 h-7 text-primary" /> Paramètres
        </h1>
        <p className="text-muted-foreground mt-1">Informations de la compagnie — apparaissent sur les tickets et reçus.</p>
      </div>

      <form onSubmit={handleSubmit} className="space-y-4">
        {/* Logo */}
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-semibold flex items-center gap-2">
              <ImageIcon className="w-4 h-4" /> Logo
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {logo ? (
              <div className="flex items-center gap-4">
                <img src={logo} alt="Logo" className="max-h-16 max-w-[160px] object-contain border rounded-lg p-1 bg-muted" />
                <div className="flex flex-col gap-2">
                  <Button type="button" variant="outline" size="sm" onClick={() => logoRef.current?.click()} disabled={logoLoading}>
                    Changer le logo
                  </Button>
                  <Button type="button" variant="ghost" size="sm" className="text-destructive" onClick={() => { setLogo(null); setDirty(true); }}>
                    Supprimer
                  </Button>
                </div>
              </div>
            ) : (
              <div
                className="border-2 border-dashed border-border rounded-xl py-8 flex flex-col items-center gap-2 cursor-pointer hover:bg-muted/40 transition-colors"
                onClick={() => logoRef.current?.click()}
              >
                <ImageIcon className="w-8 h-8 text-muted-foreground" />
                <p className="text-sm text-muted-foreground">Cliquez pour ajouter un logo</p>
                <p className="text-xs text-muted-foreground">PNG, JPG — sera redimensionné à 400px max</p>
              </div>
            )}
            <input ref={logoRef} type="file" accept="image/*" className="hidden"
              onChange={(e) => handleLogoFile(e.target.files?.[0])} />
          </CardContent>
        </Card>

        {/* Identité */}
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-semibold">Identité</CardTitle>
          </CardHeader>
          <CardContent className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div className="space-y-1 sm:col-span-2">
              <Label htmlFor="nom">Nom de la compagnie *</Label>
              <Input id="nom" required value={form.nom} onChange={e => set("nom", e.target.value)} placeholder="VIP Colis" />
            </div>
            <div className="space-y-1 sm:col-span-2">
              <Label htmlFor="slogan">Slogan / Description</Label>
              <Input id="slogan" value={form.slogan} onChange={e => set("slogan", e.target.value)} placeholder="Réseau de transport express…" />
            </div>
          </CardContent>
        </Card>

        {/* Contact */}
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-semibold">Contact</CardTitle>
          </CardHeader>
          <CardContent className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div className="space-y-1">
              <Label htmlFor="telephone">Téléphone</Label>
              <Input id="telephone" value={form.telephone} onChange={e => set("telephone", e.target.value)} placeholder="+226 70 00 00 00" />
            </div>
            <div className="space-y-1">
              <Label htmlFor="email">Email</Label>
              <Input id="email" type="email" value={form.email} onChange={e => set("email", e.target.value)} placeholder="contact@vipcolis.bf" />
            </div>
            <div className="space-y-1 sm:col-span-2">
              <Label htmlFor="adresse">Adresse</Label>
              <Input id="adresse" value={form.adresse} onChange={e => set("adresse", e.target.value)} placeholder="Avenue Kwamé N'Krumah, Secteur 1" />
            </div>
            <div className="space-y-1">
              <Label htmlFor="ville">Ville</Label>
              <Input id="ville" value={form.ville} onChange={e => set("ville", e.target.value)} placeholder="Ouagadougou" />
            </div>
            <div className="space-y-1">
              <Label htmlFor="pays">Pays</Label>
              <Input id="pays" value={form.pays} onChange={e => set("pays", e.target.value)} placeholder="Burkina Faso" />
            </div>
          </CardContent>
        </Card>

        <Button type="submit" className="w-full" size="lg" disabled={update.isPending || !dirty}>
          <Save className="w-4 h-4 mr-2" />
          {update.isPending ? "Enregistrement…" : "Enregistrer les paramètres"}
        </Button>
      </form>
    </div>
  );
}
