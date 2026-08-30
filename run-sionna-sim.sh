#!/bin/bash
# =============================================================================
# run-sionna-sim.sh — Lanza dentro del contenedor la simulación de ejemplo
#                     v2v-cam-exchange-sionna-80211p apuntando al servidor
#                     Sionna que corre NATIVO en el Mac (UDP/8103).
#
# Requisitos:
#   1. Servidor Sionna corriendo en el Mac:   ./run-sionna-server.sh
#   2. GUI disponible: visor VNC abierto (open vnc://127.0.0.1:5901).
#      Este ejemplo abre sumo-gui SIEMPRE: SumoGUI está fijado a true en su
#      código; para correr sin GUI, edita la línea
#      `SetAttribute ("SumoGUI", ...)` del ejemplo y recompila con ./ns3 build.
#
# Detalle técnico: el código C++ de VaN3Twin usa inet_aton(), que NO resuelve
# nombres DNS, por lo que hay que pasar la IP numérica del host. La resolvemos
# dentro del contenedor a partir de host.docker.internal.
# =============================================================================
set -e

docker compose up -d

docker compose exec van3twin bash -c '
    SIONNA_IP=$(getent hosts host.docker.internal | cut -d" " -f1)
    if [ -z "$SIONNA_IP" ]; then
        echo "ERROR: no se pudo resolver host.docker.internal"
        exit 1
    fi
    echo "[sim] Servidor Sionna (Mac): $SIONNA_IP:8103"
    ./ns3 run "v2v-cam-exchange-sionna-80211p --sionna=true --sionna-server-ip=$SIONNA_IP"
'
