import { Switch, Route, Router as WouterRouter, useLocation } from "wouter";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { Toaster } from "@/components/ui/toaster";
import { TooltipProvider } from "@/components/ui/tooltip";
import { useGetMe, useLogout } from "@workspace/api-client-react";
import { Loader2, Package, LayoutDashboard, MapPin, Users, BarChart3, Search, LogOut } from "lucide-react";
import { Link } from "wouter";
import { Button } from "@/components/ui/button";

import Login from "./pages/login";
import Dashboard from "./pages/dashboard";
import ColisList from "./pages/colis/index";
import ColisDetail from "./pages/colis/detail";
import ColisNouveau from "./pages/colis/nouveau";
import GaresList from "./pages/gares/index";
import UsersList from "./pages/utilisateurs/index";
import Rapports from "./pages/rapports";
import Recherche from "./pages/recherche";

const queryClient = new QueryClient();

function Layout({ children }: { children: React.ReactNode }) {
  const { data: user, isLoading, error } = useGetMe();
  const logout = useLogout();
  const [location] = useLocation();

  if (isLoading) return <div className="min-h-screen flex items-center justify-center"><Loader2 className="animate-spin w-8 h-8 text-primary" /></div>;
  if (!user || error) {
    window.location.href = import.meta.env.BASE_URL + "login";
    return null;
  }

  const menu = [
    { href: "/", label: "Tableau de bord", icon: LayoutDashboard },
    { href: "/colis", label: "Colis", icon: Package },
    { href: "/recherche", label: "Recherche", icon: Search },
    { href: "/rapports", label: "Rapports", icon: BarChart3 },
  ];

  if (user.role === "admin") {
    menu.push({ href: "/gares", label: "Gares", icon: MapPin });
    menu.push({ href: "/utilisateurs", label: "Utilisateurs", icon: Users });
  }

  return (
    <div className="flex min-h-screen w-full">
      <aside className="w-64 bg-sidebar text-sidebar-foreground flex flex-col">
        <div className="p-4 md:p-6 flex items-center gap-3">
          <Package className="w-8 h-8 text-primary" />
          <span className="font-bold text-xl tracking-tight">VIP COLIS</span>
        </div>
        <nav className="flex-1 px-4 flex flex-col gap-2 mt-4">
          {menu.map(item => {
            const Icon = item.icon;
            const active = location === item.href || (item.href !== "/" && location.startsWith(item.href));
            return (
              <Link key={item.href} href={item.href} className={`flex items-center gap-3 px-3 py-2 rounded-md transition-colors ${active ? 'bg-sidebar-primary text-sidebar-primary-foreground' : 'hover:bg-sidebar-accent text-sidebar-foreground/80 hover:text-sidebar-foreground'}`}>
                <Icon className="w-5 h-5" />
                <span className="font-medium">{item.label}</span>
              </Link>
            )
          })}
        </nav>
        <div className="p-4 border-t border-sidebar-border mt-auto">
          <div className="text-sm font-medium mb-1 truncate">{user.nom}</div>
          <div className="text-xs text-sidebar-foreground/60 mb-4 capitalize">{user.role} {user.gare_nom ? `- ${user.gare_nom}` : ''}</div>
          <Button variant="outline" className="w-full justify-start text-black" onClick={() => logout.mutate(undefined, { onSuccess: () => window.location.href = import.meta.env.BASE_URL + "login" })}>
            <LogOut className="w-4 h-4 mr-2" /> Déconnexion
          </Button>
        </div>
      </aside>
      <main className="flex-1 bg-background overflow-auto flex flex-col h-[100dvh]">
        <div className="p-6 md:p-8 max-w-7xl mx-auto w-full flex-1 flex flex-col">
          {children}
        </div>
      </main>
    </div>
  );
}

function Router() {
  const [location] = useLocation();
  if (location === "/login") return <Login />;

  return (
    <Layout>
      <Switch>
        <Route path="/" component={Dashboard} />
        <Route path="/colis" component={ColisList} />
        <Route path="/colis/nouveau" component={ColisNouveau} />
        <Route path="/colis/:id" component={ColisDetail} />
        <Route path="/gares" component={GaresList} />
        <Route path="/utilisateurs" component={UsersList} />
        <Route path="/rapports" component={Rapports} />
        <Route path="/recherche" component={Recherche} />
        <Route>
          <div className="flex-1 flex items-center justify-center text-muted-foreground">Page introuvable</div>
        </Route>
      </Switch>
    </Layout>
  );
}

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <TooltipProvider>
        <WouterRouter base={import.meta.env.BASE_URL.replace(/\/$/, "")}>
          <Router />
        </WouterRouter>
        <Toaster />
      </TooltipProvider>
    </QueryClientProvider>
  );
}

export default App;
