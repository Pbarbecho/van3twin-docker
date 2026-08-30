#!/bin/bash
# =============================================================================
# run-sionna-server.sh — Arranca el servidor Sionna v1.0 NATIVO en el Mac,
#                        en modo CPU (sin GPU NVIDIA), escuchando en UDP/8103.
#
# El contenedor VaN3Twin le enviará las posiciones de los vehículos y le
# pedirá pathloss/retardo por ray tracing (ver run-sionna-sim.sh).
#
# Notas:
#   * SIN --local-machine el script hace bind a 0.0.0.0 ("external server"),
#     necesario porque el tráfico del contenedor llega vía la VM de Docker.
#   * --gpu 0 = solo CPU (backend LLVM de Dr.Jit). Documentado por los
#     propios autores del script.
#   * macOS puede preguntar si permites que Python acepte conexiones
#     entrantes: acepta.
#
# Uso: ./run-sionna-server.sh [args extra del servidor]
#      p. ej.: ./run-sionna-server.sh --verbose --max-depth 3
# =============================================================================
set -e

SIONNA_DIR="$HOME/van3twin-sionna"

if [ ! -f "$SIONNA_DIR/sionna_v1_server_script.py" ]; then
    echo "ERROR: no existe $SIONNA_DIR. Ejecuta primero ./setup-sionna-macos.sh"
    exit 1
fi

# Dr.Jit necesita libLLVM para el backend CPU
export DRJIT_LIBLLVM_PATH="$(brew --prefix llvm)/lib/libLLVM.dylib"

cd "$SIONNA_DIR"
source venv/bin/activate

echo "[sionna] Servidor CPU-only en UDP/8103 (Ctrl+C para detener)"
echo "[sionna] Escenario por defecto: scenarios/SionnaCircleScenario/scene.xml"
exec python sionna_v1_server_script.py \
    --gpu 0 \
    --port 8103 \
    "$@"
