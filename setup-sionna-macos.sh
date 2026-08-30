#!/bin/bash
# =============================================================================
# setup-sionna-macos.sh — Instala el servidor NVIDIA Sionna v1.0 NATIVO en el
#                         Mac (Apple Silicon, CPU sin GPU NVIDIA) para usarlo
#                         con el contenedor VaN3Twin.
#
# Qué hace:
#   1. Instala (si faltan) python@3.12 y llvm vía Homebrew.
#   2. Crea un venv en ~/van3twin-sionna con sionna==1.0.2 (la versión
#      soportada por VaN3Twin) + TensorFlow arm64.
#   3. Copia el script servidor y los escenarios desde el contenedor.
#
# Requisitos: Homebrew, contenedor van3twin construido (docker compose up -d).
# Ejecutar DESDE la carpeta que contiene docker-compose.yml:  ./setup-sionna-macos.sh
# =============================================================================
set -e

SIONNA_DIR="$HOME/van3twin-sionna"

# --- 0. Comprobaciones previas ----------------------------------------------
if [ ! -f "docker-compose.yml" ]; then
    echo "ERROR: ejecuta este script desde la carpeta que contiene docker-compose.yml"
    exit 1
fi
if ! command -v brew >/dev/null 2>&1; then
    echo "ERROR: se requiere Homebrew (https://brew.sh)"
    exit 1
fi

# --- 1. Dependencias del Mac --------------------------------------------------
# Python 3.12: mitsuba 3.6.2 (fijado por sionna-rt 1.0.2) publica wheels
# macosx_arm64 hasta cp313, pero TensorFlow 2.19 llega hasta cp312.
if ! command -v python3.12 >/dev/null 2>&1; then
    echo "[setup] Instalando python@3.12..."
    brew install python@3.12
fi
# LLVM: lo necesita Dr.Jit (backend CPU del ray tracer, al no haber CUDA).
if ! brew --prefix llvm >/dev/null 2>&1 || [ ! -e "$(brew --prefix llvm)/lib/libLLVM.dylib" ]; then
    echo "[setup] Instalando llvm..."
    brew install llvm
fi

# --- 2. Entorno virtual con Sionna v1.0 --------------------------------------
mkdir -p "$SIONNA_DIR"
cd "$SIONNA_DIR"
if [ ! -d venv ]; then
    python3.12 -m venv venv
fi
source venv/bin/activate
pip install --upgrade pip
# sionna 1.0.2 fija: sionna-rt==1.0.2 -> mitsuba==3.6.2 + drjit==1.0.3
# (todos con wheels macosx_arm64) y numpy<2.0.
# TF ~2.19: compatible con numpy 1.26.x y con Python 3.12 en arm64.
pip install "sionna==1.0.2" "tensorflow~=2.19.0"

# --- 3. Servidor y escenarios desde el contenedor ----------------------------
cd - >/dev/null
docker compose up -d
docker compose cp \
  van3twin:/home/vanet/VaN3Twin/ns-3-dev/src/sionna/sionna_v1_server_script.py \
  "$SIONNA_DIR/"
docker compose cp \
  van3twin:/home/vanet/VaN3Twin/ns-3-dev/src/sionna/scenarios \
  "$SIONNA_DIR/scenarios"

# --- 4. Verificación ----------------------------------------------------------
export DRJIT_LIBLLVM_PATH="$(brew --prefix llvm)/lib/libLLVM.dylib"
"$SIONNA_DIR/venv/bin/python" - <<'EOF'
import drjit, mitsuba, sionna.rt
print(f"[setup] OK -> drjit {drjit.__version__} | mitsuba {mitsuba.__version__} | sionna-rt importado")
print("[setup] Backend CPU (LLVM) listo; no se requiere GPU NVIDIA.")
EOF

echo ""
echo "[setup] Instalación completa en $SIONNA_DIR"
echo "[setup] Arranca el servidor con:  ./run-sionna-server.sh"
