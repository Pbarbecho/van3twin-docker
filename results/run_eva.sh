#!/usr/bin/env bash
# Lanza el ejemplo EVA 802.11p de VaN3Twin sobre el escenario de Cuenca.
# Se ejecuta DENTRO del contenedor van3twin (queda en ~/results/run_eva.sh):
#
#   bash ~/results/run_eva.sh            # 2 clientes TraCI: ns-3 + visor web
#   bash ~/results/run_eva.sh 3          # 3 clientes: ns-3 + visor + cliente_traci.py
#   bash ~/results/run_eva.sh 3 600      # idem, 600 s de simulación
#
# Variables opcionales (exportar antes de llamar):
#   ESCENARIO   carpeta dentro de ~/results   (defecto: cuenca)
#   SUMOCFG     archivo .sumocfg              (defecto: <ESCENARIO>.sumocfg)
#   ROU         archivo de rutas (--mob-trace)(defecto: <ESCENARIO>.rou.xml)
set -euo pipefail

CLIENTES="${1:-2}"          # --num-traci-clients
SIM_TIME="${2:-300}"        # --sim-time (segundos simulados)

ESCENARIO="${ESCENARIO:-cuenca}"
SUMO_DIR="$HOME/results/$ESCENARIO"
SUMOCFG="${SUMOCFG:-$ESCENARIO.sumocfg}"
ROU="${ROU:-$ESCENARIO.rou.xml}"
NS3_DIR="$HOME/VaN3Twin/ns-3-dev"

# Comprobaciones previas: fallar aquí es más claro que el SIGABRT de ns-3
for f in "$SUMO_DIR/$SUMOCFG" "$SUMO_DIR/$ROU"; do
    [ -f "$f" ] || { echo "No existe: $f" >&2; exit 1; }
done
[ -x "$NS3_DIR/ns3" ] || { echo "No se encuentra $NS3_DIR/ns3" >&2; exit 1; }

echo ">> Escenario : $SUMO_DIR ($SUMOCFG, rutas $ROU)"
echo ">> Clientes  : $CLIENTES   (1 = ns-3, 2 = visor web, 3 = cliente_traci.py)"
echo ">> Duración  : $SIM_TIME s"
echo

cd "$NS3_DIR"
exec ./ns3 run "v2v-emergencyVehicleAlert-80211p \
    --sumo-gui=false --met-sup=true --sumo-updates=0.1 \
    --sim-time=$SIM_TIME \
    --num-traci-clients=$CLIENTES \
    --sumo-folder=$SUMO_DIR/ \
    --mob-trace=$ROU \
    --sumo-config=$SUMO_DIR/$SUMOCFG"
