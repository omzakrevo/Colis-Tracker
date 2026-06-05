import { Switch, Route, Router as WouterRouter, useLocation } from "wouter";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { Toaster } from "@/components/ui/toaster";
import { TooltipProvider } from "@/components/ui/tooltip";
import { useGetMe, useLogout } from "@workspace/api-client-react";
import {
  Loader2,
  Package,
  LayoutDashboard,
  MapPin,
  Users,
  BarChart3,
  Search,
  LogOut,
  Menu,
  QrCode,
} from "lucide-react";
import { Link } from "wouter";
import { Button } from "@/components/ui/button";
import { Sheet, SheetContent, SheetTitle } from "@/components/ui/sheet";
import { useState } from "react";

import Login from "./pages/login";
import Dashboard from "./pages/dashboard";
import ColisList from "./pages/colis/index";
import ColisDetail from "./pages/colis/detail";
import ColisNouveau from "./pages/colis/nouveau";
import GaresList from "./pages/gares/index";
import UsersList from "./pages/utilisateurs/index";
import Rapports from "./pages/rapports";
import Recherche from "./pages/recherche";
import Scanner from "./pages/scanner";

const queryClient = new QueryClient();

type MenuItem = {
  href: string;
  label: string;
  icon: React.ComponentType<{ className?: string }>;
};

function SidebarContent({
  user,
  menu,
  location,
  onNavigate,
  onLogout,
  isLoggingOut,
}: {
  user: any;
  menu: MenuItem[];
  location: string;
  onNavigate?: () => void;
  onLogout: () => void;
  isLoggingOut: boolean;
}) {
  return (
    <div className="flex flex-col h-full">
      <div className="p-5 flex items-center gap-3 border-b border-sidebar-border">
        <Package className="w-7 h-7 text-primary shrink-0" />
        <span className="font-bold text-lg tracking-tight">VIP COLIS</span>
      </div>

      <nav className="flex-1 px-3 py-4 flex flex-col gap-1 overflow-y-auto">
        {menu.map((item) => {
          const Icon = item.icon;
          const active =
            location === item.href ||
            (item.href !== "/" && location.startsWith(item.href));
          return (
            <Link
              key={item.href}
              href={item.href}
              onClick={onNavigate}
              className={`flex items-center gap-3 px-3 py-2.5 rounded-md transition-colors text-sm ${
                active
                  ? "bg-sidebar-primary text-sidebar-primary-foreground font-semibold"
                  : "hover:bg-sidebar-accent text-sidebar-foreground/80 hover:text-sidebar-foreground"
              }`}
            >
              <Icon className="w-4 h-4 shrink-0" />
              <span>{item.label}</span>
            </Link>
          );
        })}
      </nav>

      <div className="p-4 border-t border-sidebar-border">
        <div className="text-sm font-medium truncate">{user.nom}</div>
        <div className="text-xs text-sidebar-foreground/60 mb-3 capitalize">
          {user.role === "admin"
            ? "Administrateur"
            : user.role === "chef_gare"
            ? "Chef de gare"
            : "Agent"}
          {user.gare_nom ? ` — ${user.gare_nom}` : ""}
        </div>
        <Button
          variant="outline"
          size="sm"
          className="w-full justify-start text-foreground"
          disabled={isLoggingOut}
          onClick={onLogout}
        >
          <LogOut className="w-4 h-4 mr-2" />
          Déconnexion
        </Button>
      </div>
    </div>
  );
}

function Layout({ children }: { children: React.ReactNode }) {
  const { data: user, isLoading, error } = useGetMe();
  const logout = useLogout();
  const [location] = useLocation();
  const [mobileOpen, setMobileOpen] = useState(false);

  if (isLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Loader2 className="animate-spin w-8 h-8 text-primary" />
      </div>
    );
  }

  if (!user || error) {
    window.location.href = import.meta.env.BASE_URL + "login";
    return null;
  }

  const menu: MenuItem[] = [
    { href: "/", label: "Tableau de bord", icon: LayoutDashboard },
    { href: "/colis", label: "Colis", icon: Package },
    { href: "/scanner", label: "Scanner QR", icon: QrCode },
    { href: "/recherche", label: "Recherche", icon: Search },
    { href: "/rapports", label: "Rapports", icon: BarChart3 },
  ];

  if (user.role === "admin") {
    menu.push({ href: "/gares", label: "Gares", icon: MapPin });
    menu.push({ href: "/utilisateurs", label: "Utilisateurs", icon: Users });
  }

  const handleLogout = () => {
    logout.mutate(undefined, {
      onSuccess: () => {
        window.location.href = import.meta.env.BASE_URL + "login";
      },
    });
  };

  return (
    <div className="flex min-h-screen w-full">
      {/* Desktop sidebar */}
      <aside className="hidden md:flex w-60 shrink-0 bg-sidebar text-sidebar-foreground flex-col h-screen sticky top-0">
        <SidebarContent
          user={user}
          menu={menu}
          location={location}
          onLogout={handleLogout}
          isLoggingOut={logout.isPending}
        />
      </aside>

      {/* Mobile sheet */}
      <Sheet open={mobileOpen} onOpenChange={setMobileOpen}>
        <SheetContent
          side="left"
          className="p-0 w-64 bg-sidebar text-sidebar-foreground border-r-sidebar-border"
        >
          <SheetTitle className="sr-only">Menu navigation</SheetTitle>
          <SidebarContent
            user={user}
            menu={menu}
            location={location}
            onNavigate={() => setMobileOpen(false)}
            onLogout={handleLogout}
            isLoggingOut={logout.isPending}
          />
        </SheetContent>
      </Sheet>

      {/* Main */}
      <div className="flex-1 flex flex-col min-w-0">
        {/* Mobile top bar */}
        <header className="md:hidden sticky top-0 z-30 flex items-center gap-3 bg-background border-b px-4 h-14 shrink-0 print:hidden">
          <Button
            variant="ghost"
            size="sm"
            className="p-1.5"
            onClick={() => setMobileOpen(true)}
          >
            <Menu className="w-5 h-5" />
          </Button>
          <div className="flex items-center gap-2">
            <Package className="w-5 h-5 text-primary" />
            <span className="font-bold text-base tracking-tight">VIP COLIS</span>
          </div>
        </header>

        <main className="flex-1 overflow-y-auto">
          <div className="p-4 md:p-8 max-w-7xl mx-auto w-full">
            {children}
          </div>
        </main>
      </div>
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
        <Route path="/scanner" component={Scanner} />
        <Route path="/gares" component={GaresList} />
        <Route path="/utilisateurs" component={UsersList} />
        <Route path="/rapports" component={Rapports} />
        <Route path="/recherche" component={Recherche} />
        <Route>
          <div className="flex-1 flex items-center justify-center text-muted-foreground">
            Page introuvable
          </div>
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
