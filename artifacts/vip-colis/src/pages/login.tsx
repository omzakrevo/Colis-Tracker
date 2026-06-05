import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { useLogin, useGetMe } from "@workspace/api-client-react";
import { useLocation } from "wouter";
import { Form, FormControl, FormField, FormItem, FormLabel, FormMessage } from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Package } from "lucide-react";
import { useEffect } from "react";

const schema = z.object({
  username: z.string().min(1, "Nom d'utilisateur requis"),
  password: z.string().min(1, "Mot de passe requis"),
});

export default function Login() {
  const [, setLocation] = useLocation();
  const { data: user } = useGetMe();
  const login = useLogin();

  useEffect(() => {
    if (user) setLocation("/");
  }, [user, setLocation]);

  const form = useForm({
    resolver: zodResolver(schema),
    defaultValues: { username: "", password: "" }
  });

  const onSubmit = (data: z.infer<typeof schema>) => {
    login.mutate({ data }, {
      onSuccess: () => setLocation("/")
    });
  };

  return (
    <div className="min-h-screen flex flex-col md:flex-row bg-background">
      <div className="flex-1 bg-sidebar text-sidebar-foreground flex items-center justify-center p-12">
        <div className="max-w-md">
          <div className="flex items-center gap-4 mb-8">
            <Package className="w-12 h-12 text-primary" />
            <h1 className="text-4xl font-bold">VIP COLIS</h1>
          </div>
          <p className="text-xl text-sidebar-foreground/80 leading-relaxed">
            Le centre névralgique de vos expéditions. Suivez, gérez et sécurisez chaque colis à travers tout le réseau.
          </p>
        </div>
      </div>
      <div className="flex-1 flex items-center justify-center p-8 bg-card">
        <div className="w-full max-w-md">
          <div className="mb-8">
            <h2 className="text-2xl font-bold mb-2">Connexion</h2>
            <p className="text-muted-foreground">Entrez vos identifiants pour accéder au portail.</p>
          </div>
          
          <Form {...form}>
            <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
              <FormField control={form.control} name="username" render={({ field }) => (
                <FormItem>
                  <FormLabel>Nom d'utilisateur</FormLabel>
                  <FormControl>
                    <Input {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )} />
              <FormField control={form.control} name="password" render={({ field }) => (
                <FormItem>
                  <FormLabel>Mot de passe</FormLabel>
                  <FormControl>
                    <Input type="password" {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )} />
              {login.isError && <div className="text-destructive text-sm font-medium">Identifiants incorrects.</div>}
              <Button type="submit" className="w-full" disabled={login.isPending}>
                {login.isPending ? "Connexion..." : "Se connecter"}
              </Button>
            </form>
          </Form>
        </div>
      </div>
    </div>
  )
}
