import { useGetDashboardStats } from "@workspace/api-client-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Package, Truck, CheckCircle, Clock, Banknote, MapPin, Users } from "lucide-react";

export default function Dashboard() {
  const { data: stats, isLoading } = useGetDashboardStats();

  if (isLoading || !stats) return <div className="text-center p-8">Chargement...</div>;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Tableau de bord</h1>
        <p className="text-muted-foreground">Aperçu en temps réel de l'activité du réseau VIP Colis.</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard title="Colis du jour" value={stats.colis_aujourd_hui} icon={Package} color="text-primary" />
        <StatCard title="En route" value={stats.colis_en_route} icon={Truck} color="text-yellow-500" />
        <StatCard title="Arrivés" value={stats.colis_arrives} icon={CheckCircle} color="text-green-500" />
        <StatCard title="Non retirés" value={stats.colis_non_retires} icon={Clock} color="text-gray-500" />
        
        <StatCard title="Recette du jour" value={`${stats.recette_aujourd_hui.toLocaleString()} FCFA`} icon={Banknote} color="text-green-600" />
        <StatCard title="Recette totale" value={`${stats.recette_totale.toLocaleString()} FCFA`} icon={Banknote} color="text-primary" />
        <StatCard title="Gares" value={stats.total_gares} icon={MapPin} color="text-blue-500" />
        <StatCard title="Agents" value={stats.total_agents} icon={Users} color="text-purple-500" />
      </div>
    </div>
  )
}

function StatCard({ title, value, icon: Icon, color }: any) {
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground">{title}</CardTitle>
        <Icon className={`w-4 h-4 ${color}`} />
      </CardHeader>
      <CardContent>
        <div className="text-2xl font-bold">{value}</div>
      </CardContent>
    </Card>
  )
}
