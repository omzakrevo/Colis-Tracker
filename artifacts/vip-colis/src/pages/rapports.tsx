import {
  useGetColisParJour,
  useGetRecettesParGare,
  useGetRecettesParAgent,
  useGetStatutsSummary,
  useGetColisNonRetires,
} from "@workspace/api-client-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  PieChart,
  Pie,
  Cell,
  Legend,
} from "recharts";
import { ColisBadge } from "./colis/index";
import { Link } from "wouter";

const COLORS = ["#f97316", "#22c55e", "#eab308", "#3b82f6", "#a855f7", "#ef4444"];

const STATUT_LABELS: Record<string, string> = {
  enregistre: "Enregistré",
  charge: "Chargé",
  en_route: "En route",
  arrive: "Arrivé",
  retire: "Retiré",
  annule: "Annulé",
};

function formatMontant(v: number) {
  return `${v.toLocaleString("fr-FR")} FCFA`;
}

export default function Rapports() {
  const { data: colisParJour } = useGetColisParJour({});
  const { data: parGare } = useGetRecettesParGare();
  const { data: parAgent } = useGetRecettesParAgent();
  const { data: statuts } = useGetStatutsSummary();
  const { data: nonRetires } = useGetColisNonRetires();

  const pieData = statuts?.map((s) => ({
    name: STATUT_LABELS[s.statut] ?? s.statut,
    value: s.total,
  }));

  const jourData = colisParJour?.slice(-14).map((d) => ({
    date: new Date(d.date).toLocaleDateString("fr-FR", { day: "2-digit", month: "2-digit" }),
    "Colis": d.total,
    "Recette": d.recette,
  }));

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Rapports</h1>
        <p className="text-muted-foreground">
          Statistiques et analyses de l'activité.
        </p>
      </div>

      <Tabs defaultValue="activite">
        <TabsList className="flex-wrap h-auto gap-1">
          <TabsTrigger value="activite">Activité</TabsTrigger>
          <TabsTrigger value="gares">Par gare</TabsTrigger>
          <TabsTrigger value="agents">Par agent</TabsTrigger>
          <TabsTrigger value="statuts">Statuts</TabsTrigger>
          <TabsTrigger value="nonretires">Non retirés</TabsTrigger>
        </TabsList>

        {/* Activité quotidienne */}
        <TabsContent value="activite" className="space-y-4 mt-4">
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-sm font-semibold">
                  Colis expédiés (14 derniers jours)
                </CardTitle>
              </CardHeader>
              <CardContent>
                {!jourData || jourData.length === 0 ? (
                  <p className="text-sm text-muted-foreground text-center py-8">
                    Aucune donnée disponible.
                  </p>
                ) : (
                  <ResponsiveContainer width="100%" height={260}>
                    <BarChart data={jourData} margin={{ left: -10, right: 10, top: 5, bottom: 5 }}>
                      <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
                      <XAxis dataKey="date" tick={{ fontSize: 11 }} />
                      <YAxis tick={{ fontSize: 11 }} allowDecimals={false} />
                      <Tooltip />
                      <Bar dataKey="Colis" fill="#f97316" radius={[4, 4, 0, 0]} />
                    </BarChart>
                  </ResponsiveContainer>
                )}
              </CardContent>
            </Card>

            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-sm font-semibold">
                  Recettes (14 derniers jours, FCFA)
                </CardTitle>
              </CardHeader>
              <CardContent>
                {!jourData || jourData.length === 0 ? (
                  <p className="text-sm text-muted-foreground text-center py-8">
                    Aucune donnée disponible.
                  </p>
                ) : (
                  <ResponsiveContainer width="100%" height={260}>
                    <BarChart data={jourData} margin={{ left: 0, right: 10, top: 5, bottom: 5 }}>
                      <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
                      <XAxis dataKey="date" tick={{ fontSize: 11 }} />
                      <YAxis tick={{ fontSize: 11 }} tickFormatter={(v) => `${(v / 1000).toFixed(0)}k`} />
                      <Tooltip formatter={(v) => formatMontant(v as number)} />
                      <Bar dataKey="Recette" fill="#22c55e" radius={[4, 4, 0, 0]} />
                    </BarChart>
                  </ResponsiveContainer>
                )}
              </CardContent>
            </Card>
          </div>
        </TabsContent>

        {/* Recettes par gare */}
        <TabsContent value="gares" className="space-y-4 mt-4">
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-semibold">
                Recettes et colis par gare
              </CardTitle>
            </CardHeader>
            <CardContent>
              {!parGare || parGare.length === 0 ? (
                <p className="text-sm text-muted-foreground text-center py-8">
                  Aucune donnée disponible.
                </p>
              ) : (
                <>
                  <ResponsiveContainer width="100%" height={300}>
                    <BarChart
                      data={parGare}
                      layout="vertical"
                      margin={{ left: 20, right: 30, top: 5, bottom: 5 }}
                    >
                      <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
                      <XAxis
                        type="number"
                        tick={{ fontSize: 11 }}
                        tickFormatter={(v) => `${(v / 1000).toFixed(0)}k`}
                      />
                      <YAxis
                        type="category"
                        dataKey="gare_nom"
                        tick={{ fontSize: 11 }}
                        width={110}
                      />
                      <Tooltip formatter={(v) => formatMontant(v as number)} />
                      <Bar
                        dataKey="recette_totale"
                        name="Recette (FCFA)"
                        fill="#f97316"
                        radius={[0, 4, 4, 0]}
                      />
                    </BarChart>
                  </ResponsiveContainer>
                  <div className="mt-4 divide-y">
                    {parGare.map((g) => (
                      <div
                        key={g.gare_id}
                        className="flex justify-between items-center py-2 text-sm"
                      >
                        <span className="font-medium">{g.gare_nom}</span>
                        <div className="flex gap-4 text-muted-foreground">
                          <span>{g.total_colis} colis</span>
                          <span className="font-semibold text-foreground">
                            {g.recette_totale.toLocaleString("fr-FR")} FCFA
                          </span>
                        </div>
                      </div>
                    ))}
                  </div>
                </>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        {/* Recettes par agent */}
        <TabsContent value="agents" className="space-y-4 mt-4">
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-semibold">
                Performance par agent
              </CardTitle>
            </CardHeader>
            <CardContent>
              {!parAgent || parAgent.length === 0 ? (
                <p className="text-sm text-muted-foreground text-center py-8">
                  Aucune donnée disponible.
                </p>
              ) : (
                <>
                  <ResponsiveContainer width="100%" height={Math.max(200, parAgent.length * 50)}>
                    <BarChart
                      data={parAgent}
                      layout="vertical"
                      margin={{ left: 20, right: 30, top: 5, bottom: 5 }}
                    >
                      <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
                      <XAxis
                        type="number"
                        tick={{ fontSize: 11 }}
                        tickFormatter={(v) => `${(v / 1000).toFixed(0)}k`}
                      />
                      <YAxis
                        type="category"
                        dataKey="agent_nom"
                        tick={{ fontSize: 11 }}
                        width={110}
                      />
                      <Tooltip formatter={(v) => formatMontant(v as number)} />
                      <Bar
                        dataKey="recette_totale"
                        name="Recette (FCFA)"
                        fill="#3b82f6"
                        radius={[0, 4, 4, 0]}
                      />
                    </BarChart>
                  </ResponsiveContainer>
                  <div className="mt-4 divide-y">
                    {parAgent.map((a) => (
                      <div
                        key={a.agent_id}
                        className="flex justify-between items-center py-2 text-sm"
                      >
                        <span className="font-medium">{a.agent_nom}</span>
                        <div className="flex gap-4 text-muted-foreground">
                          <span>{a.total_colis} colis</span>
                          <span className="font-semibold text-foreground">
                            {a.recette_totale.toLocaleString("fr-FR")} FCFA
                          </span>
                        </div>
                      </div>
                    ))}
                  </div>
                </>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        {/* Statuts */}
        <TabsContent value="statuts" className="space-y-4 mt-4">
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-semibold">
                Répartition par statut
              </CardTitle>
            </CardHeader>
            <CardContent className="flex flex-col items-center">
              {!pieData || pieData.length === 0 ? (
                <p className="text-sm text-muted-foreground text-center py-8">
                  Aucune donnée disponible.
                </p>
              ) : (
                <>
                  <ResponsiveContainer width="100%" height={300}>
                    <PieChart>
                      <Pie
                        data={pieData}
                        cx="50%"
                        cy="50%"
                        innerRadius={70}
                        outerRadius={110}
                        dataKey="value"
                        label={({ name, percent }) =>
                          `${name} (${(percent * 100).toFixed(0)}%)`
                        }
                        labelLine={false}
                      >
                        {pieData.map((_, i) => (
                          <Cell key={i} fill={COLORS[i % COLORS.length]} />
                        ))}
                      </Pie>
                      <Legend />
                      <Tooltip />
                    </PieChart>
                  </ResponsiveContainer>
                  <div className="w-full mt-2 divide-y">
                    {statuts?.map((s, i) => (
                      <div
                        key={s.statut}
                        className="flex justify-between items-center py-2 text-sm"
                      >
                        <div className="flex items-center gap-2">
                          <div
                            className="w-3 h-3 rounded-full"
                            style={{ backgroundColor: COLORS[i % COLORS.length] }}
                          />
                          <ColisBadge statut={s.statut} />
                        </div>
                        <span className="font-semibold">{s.total}</span>
                      </div>
                    ))}
                  </div>
                </>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        {/* Non retirés */}
        <TabsContent value="nonretires" className="space-y-4 mt-4">
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-semibold">
                Colis arrivés non retirés ({nonRetires?.length ?? 0})
              </CardTitle>
            </CardHeader>
            <CardContent>
              {!nonRetires || nonRetires.length === 0 ? (
                <p className="text-sm text-muted-foreground text-center py-8">
                  Tous les colis arrivés ont été retirés.
                </p>
              ) : (
                <div className="divide-y">
                  {nonRetires.map((c) => (
                    <div
                      key={c.id}
                      className="py-3 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-1"
                    >
                      <div>
                        <Link
                          href={`/colis/${c.id}`}
                          className="font-medium text-primary hover:underline"
                        >
                          {c.numero}
                        </Link>
                        <p className="text-sm text-muted-foreground">
                          {c.destinataire_nom} — {c.gare_arrivee_nom}
                        </p>
                        <p className="text-xs text-muted-foreground">
                          {c.destinataire_telephone}
                        </p>
                      </div>
                      <div className="text-sm text-muted-foreground">
                        {new Date(c.date_envoi).toLocaleDateString("fr-FR")}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  );
}
